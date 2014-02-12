{ stdenv, buildLXC, coreutils, bash, tsp_bash }:

buildLXC ({ configuration, lxcLib }:
  let
    createIn = ./on-create.sh.in;
    create = stdenv.mkDerivation rec {
      name = "tsp-home-oncreate";
      buildCommand = ''
        mkdir -p $out/bin
        sed -e "s|@coreutils@|${coreutils}|g" \
            -e "s|@user@|${configuration.\"home.user\"}|g" \
            -e "s|@uid@|${configuration.\"home.uid\"}|g" \
            -e "s|@group@|${configuration.\"home.group\"}|g" \
            -e "s|@gid@|${configuration.\"home.gid\"}|g" \
            -e "s|@shell@|${bash}/bin/sh|g" \
            ${createIn} > $out/bin/on-create.sh
      '';
    };
  in
    {
      name = "tsp-home-lxc";
      storeMounts = [ tsp_bash ];
      onCreate = [ "${create}/bin/on-create.sh" ];
      options = [
        (lxcLib.declareOption {
          name = "home.user";
          optional = false;
         })
        (lxcLib.declareOption {
          name = "home.uid";
          optional = false;
         })
        (lxcLib.declareOption {
          name = "home.group";
          optional = false;
         })
        (lxcLib.declareOption {
          name = "home.gid";
          optional = false;
         })];
    })
