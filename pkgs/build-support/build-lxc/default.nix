{stdenv, lib, lxc, coreutils, gnused}:
  let
    inherit (builtins) getAttr isAttrs hasAttr filter concatLists;
    inherit (lib) id foldl;
    lxcLib = { };
    isLxcPkg  = thing: isAttrs thing && hasAttr "isLxc" thing && thing.isLxc;
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

    reachFixedPoint = pkg: f: init: ## we have a problem here - not necessarily the right thing to do to change configuration
      let g = old:
        let result = f old (runPkg pkg { configuration = old; inherit lxcLib; }); in
        if result.equal then old else g result.new;
      in g init;
    storeMountDependentFixedPoint = pkg: fun: init:
      let result = reachFixedPoint pkg (old: pkgSet:
        let
          storeMounts = pkgSet.storeMounts;
          result = fun old.result storeMounts;
          new = { inherit storeMounts result; };
        in
          { equal = new == old; inherit new; }
        ) init;
      in result.result;
    collectOptions = pkg:
      storeMountDependentFixedPoint pkg (oldOptions: storeMounts:
        let
          pkgs = lxcPkgs storeMounts;
          localOptions = runPkg pkg { }
          sequence pkg.options oldOptions;
        in
          fold collectOptions localOptions pkgs;
      );
  in fun:
  assert builtins.isFunction fun;
    {
      inherit fun;
      isLxc = true;
    }
  let

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
