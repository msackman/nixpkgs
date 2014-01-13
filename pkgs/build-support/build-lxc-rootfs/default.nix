{ stdenv }:
{name, pkgs ? [], pkg ? null}:

assert pkgs == [] -> pkg != null;
assert pkg == null -> pkgs != [];

let
  pkgs_ = if pkgs == [] then [pkg] else pkgs;
in
  stdenv.mkDerivation {
    name = "${name}-rootfs";
    buildCommand = ''
      mkdir -p $out/rootfs
      mkdir -p $out/lxc
      printf '%s\n' '${pkgs_}' > $out/pkgs
    '';
  }
