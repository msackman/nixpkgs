{stdenv, lib, lxc, coreutils}:
  let
    inherit (builtins) getAttr isAttrs isFunction isString isBool hasAttr attrNames filter concatLists listToAttrs elem length head;
    inherit (lib) id foldl fold sort substring attrValues;
    lxcLib = rec {
      inherit sequence id;

      declareOption = option@{ name, optional, ... }: options:
        assert ! hasAttr name options;
        options // listToAttrs [{ inherit name; value =
          ((if option ? default then { default = option.default; } else {}) //
            { inherit optional; });}];

      setPath = name: value: config:
        assert ! (hasPath name config);
        appendPath name value config;

      appendPath = name: value: config:
        config ++ [{inherit name value;}];

      removePath = name:
        filter (e: e.name != name);

      replacePath = name: fun:
        map (e: if e.name == name then fun e else e);

      ensurePath = name: value: config:
        if elem {inherit name value;} config then
          config
        else
          appendPath name value config;

      setInit = path:
        assert isString path;
        setPath "extra.init" path;

      emptyConfig = [];

      defaults = sequence [
        (setPath "tty" 1)
        (setPath "pts" 1024)
        (setPath "pivotdir" "lxc_putold")
        (setPath "network.type" "empty")
        (appendPath "cgroup.devices.deny" "a")          # no implicit access to devices
        (appendPath "cgroup.devices.allow" "c 1:3 rwm"   ) # /dev/null and zero
        (appendPath "cgroup.devices.allow" "c 1:5 rwm"   )
        (appendPath "cgroup.devices.allow" "c 5:1 rwm"   ) # consoles
        (appendPath "cgroup.devices.allow" "c 5:0 rwm"   )
        (appendPath "cgroup.devices.allow" "c 4:0 rwm"   )
        (appendPath "cgroup.devices.allow" "c 4:1 rwm"   )
        (appendPath "cgroup.devices.allow" "c 1:9 rwm"   ) # /dev/urandom,/dev/random
        (appendPath "cgroup.devices.allow" "c 1:8 rwm"   )
        (appendPath "cgroup.devices.allow" "c 136:* rwm" ) # /dev/pts/ - pts namespaces are "coming soon"
        (appendPath "cgroup.devices.allow" "c 5:2 rwm"   )
        (appendPath "cgroup.devices.allow" "c 10:200 rwm") # tuntap
        (setPath "cap.drop"
          (joinStrings " " ""
            ["setpcap" "sys_module" "sys_rawio" "sys_pacct" "sys_admin"
             "sys_nice" "sys_resource" "sys_time" "sys_tty_config" "mknod"
             "audit_write" "audit_control" "mac_override mac_admin"]))
        (appendPath "haltsignal" "SIGTERM")
        ] emptyConfig;

      hasPath = path: fold (e: acc: if acc then acc else e == path) false;

      configToString = config:
        joinStrings "\n" "" (
          map (attrs: "lxc.${attrs.name} = ${toString attrs.value}") config);
    };
    isLxcPkg = thing: isAttrs thing && hasAttr "isLxc" thing && thing.isLxc;
    runPkg = pkg: configuration:
        ({ name, lxcConf ? id, storeMounts ? {}, onCreate ? [], options ? [], configuration ? {}}:
           { inherit name lxcConf onCreate options configuration;
             ## Slightly hacky: assume lxc is needed by everything. In
             ## truth, this is true, but we might be better off not
             ## quite inserting it EVERYWHERE!
             storeMounts = { inherit lxc; } // storeMounts; })
        (pkg.fun { inherit configuration lxcLib; });
    lxcPkgs = filter isLxcPkg;
    sequence = list: init: foldl (acc: f: f acc) init list;
    joinStrings = sep: lib.fold (e: acc: e + sep + acc);

    ## We need to finalise configuration and
    ## storeMounts. Configuration depends on storeMounts and
    ## storeMounts depends on configuration (though progress is
    ## guaranteed). Both onCreate and lxcConf depend on on storeMounts
    ## and configuration. Also lxcConf is also a list of functions and
    ## we can't do equality on functions. However, once storeMounts
    ## and configuration has stopped changing, we should then just be
    ## able to run through lxcConf, so lxcConf shouldn't come into the
    ## fixed point calculation (neither should onCreate).

    ## 1. Establish fixed point on configuration and storeMounts.
    ## 2. Collect options
    ## 3. Add to configuration default values from options. If this alters configuration, goto (1).
    ## 4. Verify options
    ## 5. write out lxc.conf, lxc-create.sh and lxc-start.sh scripts

    storeMountsAndConfig = pkg: result@{ configuration, storeMounts }:
      let
        configuration1 = collectConfiguration configuration pkg;
        storeMounts1 = storeMounts // collectStoreMounts configuration pkg;
        result1 = { configuration = configuration1;
                    storeMounts   = storeMounts1; };
      in
        if result == result1 then
          result
        else
          storeMountsAndConfig pkg result1;

    collectConfiguration = configuration: pkg:
      let
        pkgSet = runPkg pkg configuration;
        pkgStoreMounts = pkgSet.storeMounts;
        configuration1 = configuration // pkgSet.configuration;
      in
        fold (name: configuration:
               let pkg = getAttr name pkgStoreMounts; in
               if isLxcPkg pkg then
                 collectConfiguration configuration pkg
               else
                 configuration
             ) configuration1 (attrNames pkgStoreMounts);

    collectStoreMounts = configuration: pkg:
      let
        pkgSet = runPkg pkg configuration;
        pkgStoreMounts = pkgSet.storeMounts;
        storeMountsAttrList =
          map (name:
                let pkg = getAttr name pkgStoreMounts; in
                if isLxcPkg pkg then
                  { inherit name; value = collectStoreMounts configuration pkg; }
                else
                  { inherit name; value = {}; }
              ) (attrNames pkgStoreMounts);
      in
        listToAttrs storeMountsAttrList;

    collectOptions = configuration: pkg: options:
      let
        pkgSet = runPkg pkg configuration;
        localOptions = sequence pkgSet.options options;
        lxcPkgsStoreMounts = lxcPkgs (attrValues pkgSet.storeMounts);
      in
        fold (collectOptions configuration) localOptions lxcPkgsStoreMounts;

    extendConfig = options: configuration:
      fold (optName: config:
        let opt = getAttr optName options; in
          if opt ? "default" && ! (hasAttr optName config) then
            config // (listToAttrs [{ name = optName; value = opt.default; }])
          else
            config) configuration (attrNames options);

    storeMountsConfigsOptions = pkg: configuration: storeMounts: options:
      let
        mountsAndConfig = storeMountsAndConfig pkg { inherit configuration storeMounts; };
        collectedOptions = collectOptions mountsAndConfig.configuration pkg options;
        extendedConfig = extendConfig collectedOptions mountsAndConfig.configuration;
      in
        if extendedConfig == mountsAndConfig.configuration then
          # Although we have now extended the config, there's the
          # possibility that we have values in the storeMounts attrset
          # that have closure captured an older config. Therefore at
          # this point, with the config fully done, we go back and
          # regenerate the storeMounts completely.
          let
            mountsAndConfig = storeMountsAndConfig pkg
                                { configuration = extendedConfig;
                                  storeMounts = {}; };
          in
            mountsAndConfig // { options = collectedOptions; }
        else
          storeMountsConfigsOptions pkg extendedConfig mountsAndConfig.storeMounts options;

    validateRequiredOptions = { options, configuration, ... }:
      fold (optName: acc:
        let opt = getAttr optName options; in
          if (! (opt ? optional)) || ! opt.optional then
            if ! hasAttr optName configuration then
              throw "Unable to find required configuration ${optName}."
            else
              acc
          else
            acc) true (attrNames options);

    validateUsedOptionsDeclared = { options, configuration, ... }:
      fold (confName: acc:
        if (! hasAttr confName options) then
          throw "Configuration ${confName} used but not declared in any package reached."
        else
          acc
      ) true (attrNames configuration);

    storeMountsFile = name: configuration: pkg:
      let
        f = path: pkg: acc:
          let
            pkgSet = runPkg pkg configuration;
            pkgStoreMounts = pkgSet.storeMounts;
          in
            fold (name: acc:
                   let pkg = getAttr name pkgStoreMounts; in
                   if isLxcPkg pkg then
                     f (path + name + ".") pkg acc
                   else
                     [{name = path + name; value = pkg;}] ++ acc
                 ) acc (attrNames pkgStoreMounts);
        pkgs = f (name + ".") pkg [];
      in
        stdenv.mkDerivation {
          name = "${name}-storeMounts";
          exportReferencesGraph = concatLists (map (pkg: [pkg.name pkg.value]) pkgs);
          buildCommand = joinStrings "\n" ""
            ((map (pkg: "cat ${pkg.name} >> deps") pkgs) ++
            ["cat deps | sort | uniq | grep '^[^0-9]' > $out"]);
        };

    lxcConfBaseInit = name: allLxcPkgs: configuration:
      let
        allLxcConfFuns = map (pkg: (runPkg pkg configuration).lxcConf) allLxcPkgs;
        completeConfig = sequence allLxcConfFuns lxcLib.defaults;
        init = (head (filter (e: e.name == "extra.init") completeConfig)).value;
        config = filter (e: (substring 0 6 e.name) != "extra.") completeConfig;
      in
        {lxcConfig =
          stdenv.mkDerivation {
            name = "${name}-lxcConfBase";
            buildCommand = "printf '%s' '${lxcLib.configToString config}' > $out";
          };
         inherit init; };

    createStartScripts = pkg: allLxcPkgs: configuration: {init, ...}:
      let
        name = pkg.name;
        allOnCreate = concatLists (map (pkg: (runPkg pkg configuration).onCreate) allLxcPkgs);
        createFile = ./lxc-create.sh.in;
        startFile = ./lxc-start.sh.in;
      in
        stdenv.mkDerivation {
          name = "${name}-lxc-scripts";
          buildCommand = ''
            mkdir -p $out/bin
            sed -e "s|@shell@|${stdenv.shell}|g" \
                -e "s|@coreutils@|${coreutils}|g" \
                -e "s|@lxcConfigBase@|${pkg.lxcConfig}|g" \
                -e "s|@storeMounts@|${pkg.mounts}|g" \
                -e "s|@onCreate@|${joinStrings " " "" allOnCreate}|g" \
                -e "s|@name@|${name}|g" \
                -e "s|@init@|${init}|g" \
                ${createFile} > $out/bin/lxc-create-${name}
            chmod +x $out/bin/lxc-create-${name}

            sed -e "s|@shell@|${stdenv.shell}|g" \
                -e "s|@name@|${name}|g" \
                -e "s|@lxc-execute@|${lxc}/bin/lxc-execute|g" \
                ${startFile} > $out/bin/lxc-start-${name}
            chmod +x $out/bin/lxc-start-${name}
          '';
        };

    collectLxcPkgs = configuration: pkg:
      let
        f = pkg: acc:
          let
            pkgSet = runPkg pkg configuration;
            pkgStoreMounts = pkgSet.storeMounts;
            acc1 = [pkg] ++ acc;
          in
            fold (name: acc2:
                   let pkg = getAttr name pkgStoreMounts; in
                   if isLxcPkg pkg then
                     f pkg acc2
                   else
                     acc2
                 ) acc1 (attrNames pkgStoreMounts);
      in
        f pkg [];

  in fun:
    assert builtins.isFunction fun;
    let
      pkg = {
        inherit fun name validated mounts scripts module;
        inherit (mountsConfigOptions) configuration;
        inherit (lxcConfigInit) lxcConfig;
        isLxc = true;
      };
      allLxcPkgs = collectLxcPkgs mountsConfigOptions.configuration pkg;
      mountsConfigOptions = storeMountsConfigsOptions pkg {} {} {};
      validated = (validateRequiredOptions mountsConfigOptions) &&
                  (validateUsedOptionsDeclared mountsConfigOptions);
      name = (runPkg pkg mountsConfigOptions.configuration).name;
      mounts = if validated then
                 storeMountsFile name mountsConfigOptions.configuration pkg
               else
                 throw "Unable to validate configuration.";
      lxcConfigInit = if validated then
                        lxcConfBaseInit name allLxcPkgs mountsConfigOptions.configuration
                      else
                        throw "Unable to validate configuration.";
      scripts = createStartScripts
                  pkg allLxcPkgs mountsConfigOptions.configuration lxcConfigInit;
      module = (import ./module.nix) pkg;
    in
      pkg
