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
      touch $out/pkgs
      ${joinStrings "\n" (map (f: "cat ${f} >> $out/pkgs") depFiles)}
    '';
  }
