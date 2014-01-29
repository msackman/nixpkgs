{stdenv, lib, lxc, nix, coreutils, gnused}:
  {name, pkgs ? [], pkg ? null, lxcConf ? ""}:

  assert pkgs == [] -> pkg != null;
  assert pkg == null -> pkgs != [];
  assert builtins.isString lxcConf;

  let

    interleave = xs: ys:
      if xs == []
      then ys
      else if ys == []
        then xs
        else [(builtins.head xs) (builtins.head ys)] ++
             interleave (builtins.tail xs) (builtins.tail ys);
    joinStrings = sep: lib.fold (e: acc: e + sep + acc);

    pkgs_ = if pkgs == [] then [pkg] else pkgs;
    depFiles = map baseNameOf pkgs_;
    pkgsDeps = interleave depFiles pkgs_;

    library = ./library.nix;
    createSh = ./lxc-create.sh.in;
  in

    stdenv.mkDerivation {
      name = "${name}-lxc";
      exportReferencesGraph = pkgsDeps;
      buildCommand = ''
        mkdir -p $out/bin
        mkdir $out/lxc

        ${joinStrings "\n" "" (map (p: "printf \"%s\n\" \""+p+"\" >> pkgs") pkgs_)}
        cat pkgs ${joinStrings " " "" depFiles} | sort | uniq | grep '^[^0-9]' > dependencies

        printf "%s" '${lxcConf}' > $out/lxc/default.nix

        for dir in $(cat dependencies); do
          if [ -d $dir ]; then
            printf "%s\n" "$dir" >> $out/lxc/storeMounts
          fi
        done

        sed -e "s|@shell@|${stdenv.shell}|g" \
            -e "s|@out@|$out|g" \
            -e "s|@nix@|${nix}|g" \
            -e "s|@library@|${library}|g" \
            -e "s|@coreutils@|${coreutils}|g" \
            -e "s|@sed@|${gnused}|g" \
            ${createSh} > $out/bin/lxc-create-${name}.sh
        chmod +x $out/bin/lxc-create-${name}.sh
      '';
    }

#
#        sed -e "s|@shell@|${stdenv.shell}|g" \
#            -e "s|@lxc-start@|${lxc}/bin/lxc-start|g" \
#            -e "s|@exec@|${exec}|g" \
#            ${startSh} > $out/bin/lxc-start-${name}.sh
#        chmod +x $out/bin/lxc-start-${name}.sh
#
#        sed -e "s|@name@|${name}|g" \
#            ${moduleNix} > $out/lxc/module.nix
