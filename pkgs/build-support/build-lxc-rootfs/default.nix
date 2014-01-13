{stdenv, lib}:
{name, pkgs ? [], pkg ? null}:

assert pkgs == [] -> pkg != null;
assert pkg == null -> pkgs != [];

let
  pkgs_ = if pkgs == [] then [pkg] else pkgs;
  pkgsDeps = lib.fold (e: acc: [(toString e) (baseNameOf e)] ++ acc) [] pkgs_;
  joinStrings = sep: lib.fold (e: acc: e + sep + acc) "";
in
  stdenv.mkDerivation {
    name = "${name}-rootfs";
    exportReferencesGraph = pkgsDeps;
    buildCommand = ''
      mkdir -p $out/rootfs
      mkdir -p $out/lxc
      printf '%s\n' '${joinStrings "\n" (map toString pkgs_)}' > $out/pkgs
    '';
  }
