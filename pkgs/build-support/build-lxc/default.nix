{stdenv, lib, lxc, coreutils}:
  let
    inherit (builtins) getAttr isAttrs isFunction isString hasAttr attrNames filter concatLists listToAttrs elem length head;
    inherit (lib) id foldl fold sort;
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
        (setPath "console" "none")
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
        ] emptyConfig;

      hasPath = path: fold (e: acc: if acc then acc else e == path) false;

      configToString = config:
        joinStrings "\n" "" (
          map (attrs: "lxc.${attrs.name} = ${toString attrs.value}") config);
    };
    isLxcPkg = thing: isAttrs thing && hasAttr "isLxc" thing && thing.isLxc;
    runPkg = pkg: configuration:
        ({ name, lxcConf ? id, storeMounts ? [], onCreate ? [], options ? [], configuration ? {}}:
           { inherit name lxcConf storeMounts onCreate options configuration; })
        (pkg.fun { inherit configuration lxcLib; });
    lxcPkgs = filter isLxcPkg;
    nonLxcPkgs = filter (e: ! (isLxcPkg e));
    sequence = list: init: foldl (acc: f: f acc) init list;
    joinStrings = sep: lib.fold (e: acc: e + sep + acc);
    attrValues = set: fold (name: acc: [(getAttr name set)] ++ acc) [] (attrNames set);

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

    lazyStoreMountConfigEq = a: b:
      a.configuration == b.configuration &&
      (attrNames a.storeMounts) == (attrNames b.storeMounts);

    storeMountsAndConfig = pkg: result@{ configuration, storeMounts }:
      let
        pkgSet = runPkg pkg configuration;
        configuration1 = configuration // pkgSet.configuration;
        storeMounts1 = fold (sm: acc: acc // (listToAttrs [{name = sm.name; value = sm;}]))
                         storeMounts pkgSet.storeMounts;
        localResult = { configuration = configuration1; storeMounts = storeMounts1; };
        lxcPkgsStoreMounts = lxcPkgs pkgSet.storeMounts;
        childrenResult = fold storeMountsAndConfig localResult lxcPkgsStoreMounts;
      in
        if (lazyStoreMountConfigEq result localResult) &&
           (lazyStoreMountConfigEq localResult childrenResult) then
          localResult
        else
          storeMountsAndConfig pkg childrenResult;

    collectOptions = configuration: pkg: options:
      let
        pkgSet = runPkg pkg configuration;
        localOptions = sequence pkgSet.options options;
        lxcPkgsStoreMounts = lxcPkgs pkgSet.storeMounts;
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

    storeMountsFile = name: storeMounts:
      let pkgs = nonLxcPkgs (attrValues storeMounts); in
      stdenv.mkDerivation {
        name = "${name}-storeMounts";
        exportReferencesGraph = concatLists (map (e: [e.name e]) pkgs);
        buildCommand = joinStrings "\n" ""
          ((map (pkg: "cat ${pkg.name} >> deps") pkgs) ++
          ["cat deps | sort | uniq | grep '^[^0-9]' > $out"]);
      };

    lxcConfBaseInit = name: allLxcPkgs: configuration:
      let
        allLxcConfFuns = map (pkg: (runPkg pkg configuration).lxcConf) allLxcPkgs;
        completeConfig = sequence allLxcConfFuns lxcLib.defaults;
        init = (head (filter (e: e.name == "extra.init") completeConfig)).value;
        config = filter (e: e.name != "extra.init") completeConfig;
      in
        {lxcConfig =
          stdenv.mkDerivation {
            name = "${name}-lxcConfBase";
            buildCommand = "printf '%s' '${lxcLib.configToString config}' > $out";
          };
         inherit init;};

    createStartScripts = pkg: allLxcPkgs: configuration: init:
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
                -e "s|@init@|${init}|g" \
                ${createFile} > $out/bin/lxc-create-${name}
            chmod +x $out/bin/lxc-create-${name}

            sed -e "s|@shell@|${stdenv.shell}|g" \
                -e "s|@coreutils@|${coreutils}|g" \
                -e "s|@lxc-start@|${lxc}/bin/lxc-start|g" \
                ${startFile} > $out/bin/lxc-start-${name}
            chmod +x $out/bin/lxc-start-${name}
          '';
        };

  in fun:
    assert builtins.isFunction fun;
    let
      pkg = {
        inherit fun name validated mounts scripts;
        inherit (mountsConfigOptions) configuration;
        inherit (lxcConfigInit) lxcConfig;
        isLxc = true;
      };
      allLxcPkgs = [pkg] ++ (lxcPkgs (attrValues mountsConfigOptions.storeMounts));
      mountsConfigOptions = storeMountsConfigsOptions pkg {} {} {};
      validated = (validateRequiredOptions mountsConfigOptions) &&
                  (validateUsedOptionsDeclared mountsConfigOptions);
      name = (runPkg pkg mountsConfigOptions.configuration).name;
      mounts = if validated then
                 storeMountsFile name mountsConfigOptions.storeMounts
               else
                 throw "Unable to validate configuration.";
      lxcConfigInit = if validated then
                        lxcConfBaseInit name allLxcPkgs mountsConfigOptions.configuration
                      else
                        throw "Unable to validate configuration.";
      scripts = createStartScripts
                  pkg allLxcPkgs mountsConfigOptions.configuration lxcConfigInit.init;
    in
      pkg
