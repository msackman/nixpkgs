{stdenv, lib, lxc, coreutils, gnused}:
  let
    inherit (builtins) getAttr isAttrs hasAttr attrNames filter concatLists listToAttrs elem length;
    inherit (lib) id foldl fold sort;
    lxcLib = rec {
      declareOption = option@{ name, optional, ... }: options:
        assert ! hasAttr name options;
        options // listToAttrs [{ inherit name; value =
          ((if option ? default then { default = option.default; } else {}) //
            { inherit optional; });}];
    };
    isLxcPkg = thing: isAttrs thing && hasAttr "isLxc" thing && thing.isLxc;
    runPkg = pkg: configuration:
        ({ name, lxcConf ? id, storeMounts ? [], onCreate ? [], options ? [], configuration ? {}}:
           { inherit name lxcConf storeMounts onCreate options configuration; })
        (pkg.fun { inherit configuration lxcLib; });
    lxcPkgs = filter isLxcPkg;
    sequence = list: init: foldl (acc: f: f acc) init list;

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

  in fun:
    assert builtins.isFunction fun;
    let
      pkg = {
        inherit fun name validated;
        isLxc = true;
      };
      mountsConfigOptions = storeMountsConfigsOptions pkg {} {} {};
      validated = (validateRequiredOptions mountsConfigOptions) &&
                  (validateUsedOptionsDeclared mountsConfigOptions);
      name = (runPkg pkg mountsConfigOptions.configuration).name;
    in
      pkg // mountsConfigOptions

/*
    interleave = xs: ys:
      if xs == []
      then ys
      else if ys == []
        then xs
        else [(builtins.head xs) (builtins.head ys)] ++
             interleave (builtins.tail xs) (builtins.tail ys);
    joinStrings = sep: lib.fold (e: acc: e + sep + acc);

    pkgs_ = if pkg == null then pkgs else [pkg];
    depFiles = map baseNameOf pkgs_;
    pkgsDeps = interleave depFiles pkgs_;

    library = ./library.nix;
    createSh = ./lxc-create.sh.in;
    startSh = ./lxc-start.sh.in;

    lxcConfBuilder = if builtins.isString lxcConf then
        ''printf '%s' '${lxcConf}' > $out/lxc/pkg.nix''
      else
        ''cp ${lxcConf} $out/lxc/pkg.nix'';

    lxcStoreMounts = ./store-mounts.nix.in;
    onCreate = ./on-create.sh.in;
  in

    stdenv.mkDerivation {
      name = "build-lxc-${name}";
      exportReferencesGraph = pkgsDeps;
      buildCommand = ''
        mkdir -p $out/bin
        mkdir $out/lxc

        touch pkgs
        touch $out/lxc/storeMounts
        ${joinStrings "\n" "" (map (p: "printf \"%s\n\" \""+p+"\" >> pkgs") pkgs_)}
        if [ -s pkgs ]; then
          cat pkgs ${joinStrings " " "" depFiles} | sort | uniq | grep '^[^0-9]' > dependencies

          for dir in $(cat dependencies); do
            if [ -d $dir ]; then
              printf "%s\n" "$dir" >> $out/lxc/storeMounts
            fi
          done
        fi

        ${lxcConfBuilder}
        sed -e "s|@path@|$out|g" ${lxcStoreMounts} > $out/lxc/default.nix
        sed -e "s|@path@|$out|g" ${onCreate} > $out/lxc/onCreate.sh

        sed -e "s|@shell@|${stdenv.shell}|g" \
            -e "s|@out@|$out|g" \
            -e "s|@nix@|${nix}|g" \
            -e "s|@library@|${library}|g" \
            -e "s|@coreutils@|${coreutils}|g" \
            -e "s|@sed@|${gnused}|g" \
            ${createSh} > $out/bin/lxc-create-${name}.sh
        chmod +x $out/bin/lxc-create-${name}.sh

        sed -e "s|@shell@|${stdenv.shell}|g" \
            -e "s|@coreutils@|${coreutils}|g" \
            -e "s|@lxc-start@|${lxc}/bin/lxc-start|g" \
            ${startSh} > $out/bin/lxc-start-${name}.sh
        chmod +x $out/bin/lxc-start-${name}.sh
      '';
    }
*/