{stdenv, lib}:
{name, pkgs ? [], pkg ? null}:

assert pkgs == [] -> pkg != null;
assert pkg == null -> pkgs != [];

let
  pkgs_ = if pkgs == [] then [pkg] else pkgs;
  depFiles = map baseNameOf pkgs_;
  pkgsDeps = lib.zipTwoLists depFile pkgs_;
  joinStrings = sep: lib.fold (e: acc: e + sep + acc) "";
in
  stdenv.mkDerivation {
    name = "${name}-rootfs";
    exportReferencesGraph = pkgsDeps;
    buildCommand = ''
      mkdir -p $out/rootfs
      mkdir -p $out/lxc
      touch -p $out/pkgs
      for p in ${joinStrings " " depFiles}; do
        cat $p >> $out/pkgs
      done
    '';
  }
