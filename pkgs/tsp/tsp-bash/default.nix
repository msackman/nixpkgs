{ stdenv, buildLXC, bash, coreutils }:
let
  createIn = ./on-create.sh.in;
  create = stdenv.mkDerivation rec {
    name = "${bash.name}-oncreate";
    buildCommand = ''
      mkdir -p $out/bin
      sed -e "s|@bash@|${bash}|g" \
          -e "s|@coreutils@|${coreutils}|g" \
          ${createIn} > $out/bin/on-create.sh
    '';
  };
in
  buildLXC {
    name = "${bash.name}-lxc";
    pkgs = [ bash ];
    lxcConf = ''lxcConfLib: dir:
      {onCreate = ["${create}/bin/on-create.sh"];}
      '';
  }
