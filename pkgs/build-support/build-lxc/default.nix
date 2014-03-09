{stdenv, lib, lxc, coreutils}:
  let
    inherit (builtins) getAttr isAttrs isFunction isString isBool hasAttr attrNames filter concatLists listToAttrs elem length head tail removeAttrs;
    inherit (lib) id foldl fold sort substring attrValues recursiveUpdate;
    lxcLib = rec {
      inherit sequence id;

      hasConfigurationPath = config: path:
        if path == [] then
          true
        else
          let hd = head path; tl = tail path; in
          if hasAttr hd config then
            hasConfigurationPath (getAttr hd config) tl
          else
            false;

      mkOption = desc:
        assert desc ? optional;
        assert (desc ? default) -> desc.optional;
        {_isOption = true;} // desc;

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
    isLxcPkg = thing: isAttrs thing && thing ? _isLxc && thing._isLxc;
    lxcPkgs = filter isLxcPkg;
    runPkg = pkg: configuration:
        ({ name, lxcConf ? id, storeMounts ? {}, onCreate ? [], options ? {}, configuration ? {}}:
           { inherit name lxcConf onCreate options configuration;
             ## Slightly hacky: assume lxc is needed by everything. In
             ## truth, this is true, but we might be better off not
             ## quite inserting it EVERYWHERE!
             storeMounts = { inherit lxc; } // storeMounts; })
        (pkg.fun { inherit configuration lxcLib; });
    isOption = thing: isAttrs thing && thing ? _isOption && thing._isOption;
    sequence = list: init: foldl (acc: f: f acc) init list;
    joinStrings = sep: lib.fold (e: acc: e + sep + acc);

    descendPkg = storeMounts: configuration: name:
      { inherit name;
        pkg = getAttr name storeMounts;
        configuration = if hasAttr name configuration then
                          getAttr name configuration
                        else
                          {};
      };

    descend = descenderFun: pkgFun: { configuration, pkg, ...}: acc:
      let
        pkgSet = runPkg pkg configuration;
        pkgStoreMounts = pkgSet.storeMounts;
        childResult = fold (name: acc:
                             descenderFun (descendPkg pkgStoreMounts configuration name) acc
                           ) acc (attrNames pkgStoreMounts);
      in
        pkgFun childResult pkgSet;

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

    storeMountsAndConfig = pkg: result@{ configuration, ... }:
      let
        configuration1 = collectConfiguration { inherit configuration pkg; };
        storeMounts1 = collectStoreMounts { inherit configuration pkg; };
        result1 = { configuration = configuration1;
                    storeMounts   = storeMounts1; };
      in
        if result == result1 then
          result
        else
          storeMountsAndConfig pkg result1;

    collectConfiguration = pkgConf@{ configuration, ... }:
      descend (child: acc:
                if isLxcPkg child.pkg then
                  [{ name = child.name; value = collectConfiguration child; }] ++ acc
                else
                  acc)
              (childResult: pkgSet:
                recursiveUpdate
                  (recursiveUpdate (listToAttrs childResult) pkgSet.configuration)
                  configuration)
              pkgConf [];

    collectStoreMounts = pkgConf:
      descend (child: acc:
                [{ name = child.name;
                   value = (if isLxcPkg child.pkg then collectStoreMounts child else {});
                 }] ++ acc)
              (childResult: _pkgSet: listToAttrs childResult)
              pkgConf [];

    collectOptions = pkgConf:
      descend (child: acc:
                if isLxcPkg child.pkg then
                  [{ name = child.name; value = collectOptions child; }] ++ acc
                else
                  acc)
              (childResult: pkgSet:
                recursiveUpdate (listToAttrs childResult) pkgSet.options)
              pkgConf [];

    extendConfig = options: configuration:
      let
        extendedAttrList =
          fold (optName: acc:
                 let opt = getAttr optName options; in
                 if isOption opt then
                   if opt ? default && (! (hasAttr optName configuration)) then
                     [{name = optName; value = opt.default;}] ++ acc
                   else
                     acc
                 else
                   let
                     childConfig = if hasAttr optName configuration then
                                     getAttr optName configuration
                                   else
                                     {};
                   in
                     [{name = optName; value = (extendConfig opt childConfig); }] ++ acc
               ) [] (attrNames options);
      in
        recursiveUpdate configuration (listToAttrs extendedAttrList);

    storeMountsConfigsOptions = pkg: configuration: options:
      let
        mountsAndConfig = storeMountsAndConfig pkg { inherit configuration; };
        collectedOptions = collectOptions { inherit pkg; inherit (mountsAndConfig) configuration; };
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
                                { configuration = extendedConfig; };
          in
            (mountsAndConfig // { options = collectedOptions; })
        else
          storeMountsConfigsOptions pkg extendedConfig options;

    validateRequiredOptions = { options, configuration, ... }:
      fold (optName: acc:
             let opt = getAttr optName options; in
             if isOption opt then
               if ! opt.optional then
                 if ! (hasAttr optName configuration) then
                   throw "Unable to find required configuration ${optName}."
                 else
                   acc
               else
                 acc
             else
               assert isAttrs opt;
               let
                 childConfig = if hasAttr optName configuration then
                                 getAttr optName configuration
                               else
                                 throw "Unconfigured section ${optName}.";
               in
                 validateRequiredOptions { options = opt; configuration = childConfig; } && acc
           ) true (attrNames options);

    validateUsedOptionsDeclared = { options, configuration, ... }:
      fold (confName: acc:
             if hasAttr confName options then
               let
                 option = getAttr confName options;
                 childConfig = getAttr confName configuration;
               in
                 if isOption option then
                   acc
                 else
                   validateUsedOptionsDeclared { options = option; configuration = childConfig; } && acc
             else
               throw "Configuration ${confName} used but not declared in any package reached."
           ) true (attrNames configuration);

    storeMountsFile = name: configuration: pkg:
      let
        f = path: pkgConf: acc:
          descend (child: acc:
                    if isLxcPkg child.pkg then
                      f (path + child.name + ".") child acc
                    else
                      [{name = path + child.name; value = child.pkg;}] ++ acc)
                  (childResult: _pkgSet: childResult)
                  pkgConf acc;
        pkgs = f (name + ".") { inherit pkg configuration; } [];
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
        allLxcConfFuns = map (pkg: pkg.lxcConf) allLxcPkgs;
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
        allOnCreate = concatLists (map (pkg: pkg.onCreate) allLxcPkgs);
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
        f = pkgConf: acc:
          descend (child: acc: if isLxcPkg child.pkg then f child acc else acc)
                  (childResult: pkgSet: [pkgSet] ++ childResult)
                  pkgConf acc;
      in
        f { inherit pkg configuration; } [];

  in fun:
    assert builtins.isFunction fun;
    let
      pkg = {
        inherit fun name validated mounts scripts module;
        inherit (mountsConfigOptions) configuration options;
        inherit (lxcConfigInit) lxcConfig;
        _isLxc = true;
      };
      allLxcPkgs = collectLxcPkgs mountsConfigOptions.configuration pkg;
      mountsConfigOptions = storeMountsConfigsOptions pkg {} {};
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
