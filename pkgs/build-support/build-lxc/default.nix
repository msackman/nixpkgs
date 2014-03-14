{stdenv, lib, lxc, libvirt, coreutils, gnused}:
  let
    inherit (builtins) getAttr isAttrs isFunction isString isBool hasAttr attrNames filter concatLists listToAttrs elem length head tail removeAttrs isList;
    inherit (lib) id foldl fold sort substring attrValues recursiveUpdate concatStringsSep;
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

      mkOption = desc@{ validator ? (_value: true), ... }:
        assert desc ? optional;
        assert (desc ? default) -> desc.optional;
        assert isFunction validator;
        {_isOption = true; inherit validator;} // desc;

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
          (concatStringsSep " "
            ["setpcap" "sys_module" "sys_rawio" "sys_pacct" "sys_admin"
             "sys_nice" "sys_resource" "sys_time" "sys_tty_config" "mknod"
             "audit_write" "audit_control" "mac_override mac_admin"]))
        (appendPath "haltsignal" "SIGTERM")
        ] emptyConfig;

      hasPath = path: fold (e: acc: if acc then acc else e == path) false;

      configToString = config:
        concatStringsSep "\n" (
          map (attrs: "lxc.${attrs.name} = ${toString attrs.value}") config);
    };
    isLxcPkg = thing: isAttrs thing && thing ? _isLxc && thing._isLxc;
    lxcPkgs = filter isLxcPkg;
    runPkg = { pkg, configuration, ...}:
        ({ name, lxcConf ? id, libVirtConf ? {}, storeMounts ? {}, onCreate ? [], onSterilise ? [],
           options ? {}, configuration ? {}, module ? (_: {})}:
           { inherit name lxcConf onCreate onSterilise options configuration module storeMounts libVirtConf; })
        (pkg.fun { inherit configuration lxcLib; });
    isOption = thing: isAttrs thing && thing ? _isOption && thing._isOption;
    sequence = list: init: foldl (acc: f: f acc) init list;

    descendPkg = storeMounts: configuration: name:
      { inherit name;
        pkg = getAttr name storeMounts;
        configuration = if hasAttr name configuration then
                          getAttr name configuration
                        else
                          {};
      };

    descend = descenderFun: pkgFun: pkgConf@{ configuration, ...}: acc:
      let
        pkgSet = runPkg pkgConf;
        pkgStoreMounts = pkgSet.storeMounts;
        childResult = fold (name: acc:
                             descenderFun (descendPkg pkgStoreMounts configuration name) acc
                           ) acc (attrNames pkgStoreMounts);
      in
        pkgFun childResult pkgSet;

    storeMountsConfigsOptions = pkg: configuration:
      let result = analyse { inherit pkg configuration; }; in
      if configuration == result.configuration then
        result
      else
        storeMountsConfigsOptions pkg result.configuration;

    analyse = pkgConf@{ configuration, ... }:
      let
        pkgSet = runPkg pkgConf;
        pkgOptions = pkgSet.options;
        configuration1 = extendConfig pkgOptions configuration;
      in
        if configuration == configuration1 then
          let
            pkgStoreMounts = pkgSet.storeMounts;
            gathered = fold (name: acc@{configurationAcc, optionsAcc, storeMountsAcc}:
              let childPkgConf = descendPkg pkgStoreMounts configuration name; in
              if isLxcPkg childPkgConf.pkg then
                let childResult = analyse childPkgConf; in
                {
                  configurationAcc = [{inherit name; value = childResult.configuration;}] ++ configurationAcc;
                  optionsAcc       = [{inherit name; value = childResult.options;}] ++ optionsAcc;
                  storeMountsAcc   = [{inherit name; value = childResult.storeMounts;}] ++ storeMountsAcc;
                }
              else
                acc // { storeMountsAcc = [{inherit name; value = {};}] ++ storeMountsAcc; })
              {configurationAcc = []; optionsAcc = []; storeMountsAcc = [];} (attrNames pkgStoreMounts);
              childrenConfiguration = listToAttrs gathered.configurationAcc;
              childrenOptions = listToAttrs gathered.optionsAcc;
              childrenStoreMounts = listToAttrs gathered.storeMountsAcc;
          in
            {
              configuration = recursiveUpdate
                                (recursiveUpdate childrenConfiguration pkgSet.configuration)
                                configuration;
              options       = recursiveUpdate childrenOptions pkgOptions;
              storeMounts   = childrenStoreMounts;
            }
        else
          analyse (pkgConf // { configuration = configuration1; });

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
            '' + (concatStringsSep "\n" (map (pkg: "cat ${pkg.name} >> deps") pkgs)) + ''\n
            cat deps | grep '^[^0-9]' | sort | uniq > $out/mounts
            for m in $(cat $out/mounts); do
              printf '<filesystem type='"'"'mount'"'"'>\n<source dir='"'"'%s'"'"'/>\n<target dir='"'"'%s'"'"'/>\n</filesystem>\n' "$m" "$m" >> $out/mounts.xml
            done
          '';
        };

    toLibVirt = libVirtConfs:
      let
        merged = fold (libVirtConf: acc:
                   let
                     attrsList = fold (name: listAcc:
                       let
                         value = getAttr name libVirtConf;
                         valueList = if isList value then value else [value];
                         newValue = if hasAttr name acc then
                                      valueList ++ (getAttr name acc)
                                    else
                                      valueList;
                       in
                         [{inherit name; value = newValue;}] ++ listAcc
                     ) [] (attrNames libVirtConf);
                   in
                     acc // (listToAttrs attrsList)
                 ) {} libVirtConfs;
      in
        fold (name: acc:
          (acc + ''
            <${name}>
          '' + (concatStringsSep "\n" (getAttr name merged)) + ''
            </${name}>
          '')) "" (attrNames merged);

    lxcConfBase = {name, configuration, mounts, ...}: allLxcPkgs:
      let
        allLxcConfFuns = map (pkg: pkg.lxcConf) allLxcPkgs;
        allLibVirtConf = map (pkg: pkg.libVirtConf) allLxcPkgs;
        configLXC = sequence allLxcConfFuns lxcLib.defaults;
        configLibVirt = toLibVirt allLibVirtConf;
        configXMLIn = ./config.xml.in;
      in
        stdenv.mkDerivation {
          name = "${name}-lxcConfBase";
          buildCommand = ''
            mkdir $out
            printf '%s' '${lxcLib.configToString configLXC}' > $out/config
            printf '%s' '${configLibVirt}' > devices
            sed -e "s|@emulator@|${libvirt}/libexec/libvirt_lxc|g" \
                -e "s|@name@|${name}|g" \
                -e "/@devices@/{
                        r devices
                        d
                        }" \
                -e "/@storeMounts@/{
                        r ${mounts}/mounts.xml
                        d
                        }" \
                ${configXMLIn} > $out/config.xml
          '';
        };

    createScripts = { pkg, configuration, ...}: allLxcPkgs:
      let
        name = pkg.name;
        allOnCreate = concatLists (map (pkg: pkg.onCreate) allLxcPkgs);
        allOnSterilise = concatLists (map (pkg: pkg.onSterilise) allLxcPkgs);
        createFile = ./lxc-create.sh.in;
        startFile = ./lxc-start.sh.in;
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
                -e "s|@lxcConfigBase@|${pkg.lxcConfig}|g" \
                -e "s|@storeMounts@|${pkg.mounts}/mounts|g" \
                -e "s|@gcbase@|$NIX_STORE/../var/nix/gcroots|g" \
                -e "s|@onCreate@|${concatStringsSep " " allOnCreate}|g" \
                -e "s|@name@|${name}|g" \
                -e "s|@sterilise@|$out/bin/lxc-sterilise-${name}|g" \
                -e "s|@scripts@|$out|g" \
                ${createFile} > $out/bin/lxc-create-${name}
            chmod +x $out/bin/lxc-create-${name}

            sed -e "s|@shell@|${stdenv.shell}|g" \
                -e "s|@coreutils@|${coreutils}|g" \
                -e "s|@name@|${name}|g" \
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
                -e "s|@lxc-execute@|${lxc}/bin/lxc-execute|g" \
                ${startFile} > $out/bin/lxc-start-${name}
            chmod +x $out/bin/lxc-start-${name}
          '';
        };

    groupPkgs = pkgConf:
      let
        f = pkgConf: acc:
          descend (child: acc@{all, lxc, other}:
                    if isLxcPkg child.pkg then
                      f child acc
                    else
                      {
                        all = [child.pkg] ++ all;
                        other = [child.pkg] ++ other;
                        inherit lxc;
                      })
                  ({all, lxc, other}: pkgSet:
                    {
                      all = [pkgSet] ++ all;
                      lxc = [pkgSet] ++ lxc;
                      inherit other;
                    })
                  pkgConf acc;
      in
        f pkgConf {all = []; lxc = []; other = [];};

  in fun:
    assert isFunction fun;
    let
      pkg = {
        inherit fun pkg name validated mounts scripts module lxcConfig;
        inherit (mountsConfigOptions) configuration options;
        create    = "${scripts}/bin/lxc-create-${name}";
        sterilise = "${scripts}/bin/lxc-sterilise-${name}";
        upgrade   = "${scripts}/bin/lxc-upgrade-${name}";
        start     = "${scripts}/bin/lxc-start-${name}";
        _isLxc    = true;
      };
      mountsConfigOptions = storeMountsConfigsOptions pkg {};
      validated = (validateRequiredOptions mountsConfigOptions) &&
                  (validateUsedOptionsDeclared mountsConfigOptions);
      name = (runPkg pkg).name;
      mounts = if validated then
                 storeMountsFile name groupedPkgs.other
               else
                 throw "Unable to validate configuration.";
      groupedPkgs = groupPkgs pkg;
      lxcConfig = if validated then
                    lxcConfBase pkg groupedPkgs.lxc
                  else
                    throw "Unable to validate configuration.";
      scripts = createScripts pkg groupedPkgs.lxc;
      module = { config, pkgs, ... }: {
                 imports = (map (pkgSet: pkgSet.module pkg) groupedPkgs.lxc);
               };
    in
      pkg
