{stdenv, lib, lxc, nix, coreutils, gnused}:
  {name, pkgs ? [], pkg ? null, lxcConf ? ""}:

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
      name = "${name}-lxc";
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
