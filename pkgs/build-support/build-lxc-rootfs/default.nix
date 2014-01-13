{stdenv, lib}:
{name, pkgs ? [], pkg ? null}:

assert pkgs == [] -> pkg != null;
assert pkg == null -> pkgs != [];

let
  pkgs_ = if pkgs == [] then [pkg] else pkgs;
  pkgsDeps = lib.fold (e: acc: [e e] ++ acc) [] pkgs_;
in
  stdenv.mkDerivation {
    name = "${name}-rootfs";
    exportReferencesGraph = pkgsDeps;
    buildCommand = ''
      mkdir -p $out/rootfs
      mkdir -p $out/lxc
      printf '%s\n' '${pkgs_}' > $out/pkgs
    '';
  }
