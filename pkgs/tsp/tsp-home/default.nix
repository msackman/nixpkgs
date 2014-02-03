{ stdenv, buildLXC, coreutils, bash, tsp_bash }:
let
  createIn = ./on-create.sh.in;
  create = user: uid: group: gid: stdenv.mkDerivation rec {
    name = "tsp-home-oncreate";
    buildCommand = ''
      mkdir -p $out/bin
      sed -e "s|@coreutils@|${coreutils}|g" \
          -e "s|@user@|${user}|g" \
          -e "s|@uid@|${uid}|g" \
          -e "s|@group@|${group}|g" \
          -e "s|@gid@|${gid}|g" \
          -e "s|@shell@|${bash}/bin/sh|g" \
          ${createIn} > $out/bin/on-create.sh
    '';
  };
in
  user: uid: group: gid: buildLXC {
    name = "tsp-home-lxc";
    pkgs = [ bash ];
    lxcConf = ''lxcConfLib: dir:
      {onCreate = ["${create (toString user) (toString uid) (toString group) (toString gid)}/bin/on-create.sh"];
       lxcPkgs = [ "${tsp_bash}" ];
      }'';
  }