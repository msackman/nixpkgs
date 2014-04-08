{stdenv, lib, lxc, libvirt, coreutils, gnused}:
  let
    inherit (builtins) getAttr isAttrs isFunction isString isBool hasAttr attrNames filter concatLists listToAttrs elem length head tail removeAttrs isList;
    inherit (lib) id foldl fold sort substring attrValues recursiveUpdate concatStrings concatStringsSep;
    containerLib = rec {
      inherit sequence id isLxcPkg;

      hasConfigurationPath = config: path:
        if path == [] then
          true
        else
          let hd = head path; tl = tail path; in
          if hasAttr hd config then
            hasConfigurationPath (getAttr hd config) tl
          else
            false;

      mkOption = desc@{ validator ? (_value: true), ... }:
        assert desc ? optional;
        assert (desc ? default) -> desc.optional;
        assert isFunction validator;
        {_isOption = true; inherit validator;} // desc;

      ensureList = e: if isList e then e else [e];

      extendContainerConf = path: values: conf:
        if path == [] then
          conf // { value = ((if conf ? value then ensureList conf.value else []) ++
                             (ensureList values)); }
        else
          let
            hd = head path;
            tl = tail path;
            confValueList = ensureList conf.value;
            found = filter (e: e.name == hd) confValueList;
            others = filter (e: e != foundVal) confValueList;
            foundVal = if conf ? value && found != [] then head found else {name = hd;};
          in
            conf // { value = [(extendContainerConf tl values foundVal)] ++
                              (if conf ? value then others else []); };

      setValue = path: default: fun: conf:
        if path == [] then
          fun conf
        else
          let
            hd = head path;
            tl = tail path;
            confValueList = ensureList conf.value;
            found = filter (e: e.name == hd) confValueList;
            foundVal = head found;
            others = filter (e: e != foundVal) confValueList;
          in
            if found == [] then
              extendContainerConf path default conf
            else
              conf // { value = [(setValue tl default fun foundVal)] ++ others; };

      gatherPathsWithSuffix = suffixPath: config:
        assert isList suffixPath;
        if suffixPath == [] then
          [config]
        else if isAttrs config then
          let
            hd = head suffixPath;
            tl = tail suffixPath;
            local = if hasAttr hd config then
                      gatherPathsWithSuffix tl (getAttr hd config)
                    else
                      [];
            deep = concatLists
                     (map (gatherPathsWithSuffix suffixPath) (attrValues config));
          in
            assert isString hd;
            local ++ deep
        else
          [];
    };

    isLxcPkg = thing: isAttrs thing && thing ? _isLxc && thing._isLxc;
    lxcPkgs = filter isLxcPkg;
    runPkg = { pkg, global, configuration, ...}:
        ({ name, containerConf ? id, storeMounts ? [], imports ? {}, onCreate ? [], onSterilise ? [],
           options ? {}, configuration ? {}, module ? (_: {})}:
           { inherit name onCreate onSterilise options configuration module storeMounts imports containerConf; })
        (pkg.fun { inherit global configuration containerLib; });
    isOption = thing: isAttrs thing && thing ? _isOption && thing._isOption;
    sequence = list: init: foldl (acc: f: f acc) init list;

    descendPkg = imports: global: configuration: name:
      { inherit name global;
        pkg = getAttr name imports;
        configuration = if hasAttr name configuration then
                          getAttr name configuration
                        else
                          {};
      };

    descend = descenderFun: pkgFun: pkgConf@{ global, configuration, ...}: acc:
      let
        pkgSet = runPkg pkgConf;
        pkgImports = pkgSet.imports;
        childResult = fold (name: acc:
                             descenderFun (descendPkg pkgImports global configuration name) acc
                           ) acc (attrNames pkgImports);
      in
        pkgFun childResult pkgSet;

    importsConfigsOptions = pkg: configuration:
      let result = analyse { inherit pkg configuration; global = configuration; }; in
      if configuration == result.configuration then
        # Configuration is now stable but are stable without any
        # missing defaults from options mixed in. Thus we now need to
        # mix those in and run through once again. Eventually, we
        # should find that mixing in any defaults makes no change
        # whatsoever, and then we finally exit.
        let
          extendedConfig = extendConfig result.options configuration;
          result2 = analyse { inherit pkg; configuration = extendedConfig; global = extendedConfig; };
        in
          if configuration == result2.configuration then
            result2
          else
            importsConfigsOptions pkg result2.configuration
      else
        importsConfigsOptions pkg result.configuration;

    analyse = pkgConfOrig@{ global, configuration, ... }:
      let
        # function f here permits options to be dependent on
        # configuration. Yes, that's a bit of a nutty idea, but here
        # it is anyway.
        f = pkgConf@{ configuration, ... }:
              let
                pkgSet = runPkg pkgConf;
                pkgOptions = pkgSet.options;
                configuration1 = extendConfig pkgOptions configuration;
              in
                if configuration == configuration1 then
                  { inherit pkgSet pkgOptions; configurationWithOptions = configuration; }
                else
                  f (pkgConf // { configuration = configuration1; });
        pkgConf = f pkgConfOrig;
        pkgSet = pkgConf.pkgSet;
      in
        let
          pkgImports = pkgSet.imports;
          configForChildren = recursiveUpdate configuration pkgSet.configuration;
          gathered = fold (name: acc@{configurationAcc, optionsAcc, importsAcc}:
            let childPkgConf = descendPkg pkgImports global configForChildren name; in
            assert isLxcPkg childPkgConf.pkg;
            let childResult = analyse childPkgConf; in
            {
              configurationAcc = [{inherit name; value = childResult.configuration;}] ++ configurationAcc;
              optionsAcc       = [{inherit name; value = childResult.options;}] ++ optionsAcc;
              importsAcc       = [{inherit name; value = childResult.imports;}] ++ importsAcc;
            })
            {configurationAcc = []; optionsAcc = []; importsAcc = [];} (attrNames pkgImports);
          childrenConfiguration = listToAttrs gathered.configurationAcc;
          childrenOptions = listToAttrs gathered.optionsAcc;
          childrenImports = listToAttrs gathered.importsAcc;
        in
          {
            # The newer value should always win, but the newer value
            # may contain defaults from options, so we have to be
            # careful that we don't mix in any options at this point,
            # and only add those in permanently once we're otherwise
            # finished with everything.
            configuration = recursiveUpdate configForChildren childrenConfiguration;
            options       = recursiveUpdate childrenOptions pkgConf.pkgOptions;
            imports       = childrenImports;
          };

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

    validateRequiredOptions = { options, configuration, ... }:
      fold (optName: acc:
             let opt = getAttr optName options; in
             if isOption opt then
               if hasAttr optName configuration then
                 (opt.validator (getAttr optName configuration)) && acc
               else if opt.optional then
                 acc
               else
                 throw "Unable to find required configuration ${optName}."
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

    storeMountsFile = name: nonLxcPkgs:
      let
        pkgs = (fold (pkg: {num, list}:
                        {
                          num  = num+1;
                          list = [{name = toString num; value = pkg;}] ++ list;
                        }) {num = 0; list = [];} nonLxcPkgs
               ).list;
      in
        stdenv.mkDerivation {
          name = "${name}-storeMounts";
          exportReferencesGraph = concatLists (map (pkg: [pkg.name pkg.value]) pkgs);
          buildCommand = ''
            mkdir $out
            '' + (concatStringsSep "\n" (map (pkg: "cat ${pkg.name} >> deps;") pkgs)) + ''
            cat deps | sort | uniq | grep '^[^0-9]' > $out/mounts
            for m in $(cat $out/mounts); do
              printf '<filesystem type='"'"'mount'"'"'>\n<source dir='"'"'%s'"'"'/>\n<target dir='"'"'%s'"'"'/>\n</filesystem>\n' "$m" "$m" >> $out/mounts.xml
            done
          '';
        };

    containerConf = {name, ...}: allLxcPkgs:
      let default =
        { name = "domain"; type = "lxc";
          value = [
            { name = "name"; value = name; }
            { name = "vcpu"; value = "1"; }
            { name = "memory"; unit = "MiB"; value = "64"; }
            { name = "on_poweroff"; value = "destroy"; }
            { name = "on_reboot"; value = "restart"; }
            { name = "on_crash"; value = "destroy"; }
            { name = "os"; value = [{name = "type"; value = "exe";}]; }
            { name = "devices";
              value = [{name = "emulator"; value = "${libvirt}/libexec/libvirt_lxc";}
                       {name = "filesystem"; type = "mount";
                        value = [
                         {name = "source"; dir = "@rootfs@"; }
                         {name = "target"; dir = "/"; }
                        ];}
                       "@storeMounts@"
                       {name = "console"; type = "pty";}]; }
          ]; };
      in
        fold (pkg: pkg.containerConf) default allLxcPkgs;

    toXML = thing:
      if isString thing then
        thing
      else if isList thing then
        "\n" + (concatStringsSep "\n" (map toXML thing)) + "\n"
      else
        assert isAttrs thing;
        assert (thing ? name) && (isString thing.name);
        let keys = filter (e: e != "value" && e != "name") (attrNames thing); in
        concatStrings
          (["<${thing.name} "] ++
           (map (name: ''${name}='"'"'${getAttr name thing}'"'"' '') keys) ++
           (if thing ? value then
              [">" (toXML thing.value) "</${thing.name}>"]
            else
              ["/>"]
           ));

    containerConfBase = pkg@{name, configuration, mounts, ...}: allLxcPkgs:
        stdenv.mkDerivation {
          name = "${name}-containerConfBase";
          buildCommand = ''
            mkdir $out
            printf '%s' '${toXML (containerConf pkg allLxcPkgs)}' > config.xml
            sed -e "/@storeMounts@/{
                      r ${mounts}/mounts.xml
                      d
                      }" \
                config.xml > $out/config.xml
          '';
        };

    createScripts = { pkg, configuration, ...}: allLxcPkgs:
      let
        name = pkg.name;
        allOnCreate = concatLists (map (pkg: pkg.onCreate) allLxcPkgs);
        allOnSterilise = concatLists (map (pkg: pkg.onSterilise) allLxcPkgs);
        createFile = ./lxc-create.sh.in;
        startFile = ./lxc-start.sh.in;
        stopFile = ./lxc-stop.sh.in;
        steriliseFile = ./lxc-sterilise.sh.in;
        upgradeFile = ./lxc-upgrade.sh.in;
      in
        stdenv.mkDerivation {
          name = "${name}-lxc-scripts";
          buildCommand = ''
            mkdir -p $out/bin
            sed -e "s|@shell@|${stdenv.shell}|g" \
                -e "s|@coreutils@|${coreutils}|g" \
                -e "s|@gnused@|${gnused}|g" \
                -e "s|@containerConfig@|${pkg.containerConfig}|g" \
                -e "s|@storeMounts@|${pkg.mounts}/mounts|g" \
                -e "s|@gcbase@|$NIX_STORE/../var/nix/gcroots|g" \
                -e "s|@onCreate@|${concatStringsSep " " allOnCreate}|g" \
                -e "s|@name@|${name}|g" \
                -e "s|@sterilise@|$out/bin/lxc-sterilise-${name}|g" \
                -e "s|@scripts@|$out|g" \
                -e "s|@libvirt@|${libvirt}|g" \
                ${createFile} > $out/bin/lxc-create-${name}
            chmod +x $out/bin/lxc-create-${name}

            sed -e "s|@shell@|${stdenv.shell}|g" \
                -e "s|@coreutils@|${coreutils}|g" \
                -e "s|@name@|${name}|g" \
                -e "s|@libvirt@|${libvirt}|g" \
                -e "s|@stop@|$out/bin/lxc-stop-${name}|g" \
                -e "s|@onSterilise@|${concatStringsSep " " allOnSterilise}|g" \
                -e "s|@gcbase@|$NIX_STORE/../var/nix/gcroots|g" \
                ${steriliseFile} > $out/bin/lxc-sterilise-${name}
            chmod +x $out/bin/lxc-sterilise-${name}

            sed -e "s|@shell@|${stdenv.shell}|g" \
                -e "s|@name@|${name}|g" \
                -e "s|@coreutils@|${coreutils}|g" \
                -e "s|@creator@|$out/bin/lxc-create-${name}|g" \
                ${upgradeFile} > $out/bin/lxc-upgrade-${name}
            chmod +x $out/bin/lxc-upgrade-${name}

            sed -e "s|@shell@|${stdenv.shell}|g" \
                -e "s|@name@|${name}|g" \
                -e "s|@libvirt@|${libvirt}|g" \
                ${startFile} > $out/bin/lxc-start-${name}
            chmod +x $out/bin/lxc-start-${name}

            sed -e "s|@shell@|${stdenv.shell}|g" \
                -e "s|@name@|${name}|g" \
                -e "s|@libvirt@|${libvirt}|g" \
                ${stopFile} > $out/bin/lxc-stop-${name}
            chmod +x $out/bin/lxc-stop-${name}
          '';
        };

    groupPkgs = pkgConf:
      let
        f = pkgConf: acc:
          descend (child: acc: f child acc)
                  ({lxc, other}: pkgSet:
                    {
                      lxc = [pkgSet] ++ lxc;
                      other = pkgSet.storeMounts ++ other;
                    })
                  pkgConf acc;
      in
        f pkgConf {lxc = []; other = [];};

  in fun:
    assert isFunction fun;
    let
      pkg = {
        inherit fun pkg name validated mounts scripts module containerConfig;
        inherit (importsConfigOptions) configuration options;
        global = pkg.configuration;
        create    = "${scripts}/bin/lxc-create-${name}";
        sterilise = "${scripts}/bin/lxc-sterilise-${name}";
        upgrade   = "${scripts}/bin/lxc-upgrade-${name}";
        start     = "${scripts}/bin/lxc-start-${name}";
        stop      = "${scripts}/bin/lxc-stop-${name}";
        _isLxc    = true;
      };
      importsConfigOptions = importsConfigsOptions pkg {};
      validated = (validateRequiredOptions importsConfigOptions) &&
                  (validateUsedOptionsDeclared importsConfigOptions);
      name = (runPkg pkg).name;
      mounts = if validated then
                 storeMountsFile name groupedPkgs.other
               else
                 throw "Unable to validate configuration.";
      groupedPkgs = groupPkgs pkg;
      containerConfig = if validated then
                          containerConfBase pkg groupedPkgs.lxc
                        else
                          throw "Unable to validate configuration.";
      scripts = createScripts pkg groupedPkgs.lxc;
      module = { config, pkgs, ... }: {
                 imports = (map (pkgSet: pkgSet.module pkg) groupedPkgs.lxc);
               };
    in
      pkg
