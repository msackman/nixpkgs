{stdenv, lib}:
{name, pkgs ? [], pkg ? null}:

assert pkgs == [] -> pkg != null;
assert pkg == null -> pkgs != [];

let
  interleave = xs: ys:
    if xs == []
    then ys
    else if ys == []
      then xs
      else [(builtins.head xs) (builtins.head ys)] ++
           interleave (builtins.tail xs) (builtins.tail ys);
  pkgs_ = if pkgs == [] then [pkg] else pkgs;
  depFiles = map baseNameOf pkgs_;
  pkgsDeps = interleave depFiles pkgs_;
  joinStrings = sep: lib.fold (e: acc: e + sep + acc) "";
in
  stdenv.mkDerivation {
    name = "${name}-rootfs";
    exportReferencesGraph = pkgsDeps;
    buildCommand = ''
      mkdir -p $out/rootfs
      mkdir -p $out/lxc
      ${joinStrings "\n" (map (p: "printf \"%s\n\" \""+p+"\" >> pkgs") pkgs_)}
      cat pkgs ${joinStrings " " depFiles} | sort | uniq | grep '^[^0-9]' > $out/dependencies

      for dir in $(cat $out/dependencies); do
        mkdir -p $out/rootfs$dir
        printf "%s %s none ro,bind 0 0\n" $dir $out/rootfs$dir >> $out/lxc/fstab
      done
    '';
  }
