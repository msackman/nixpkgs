{ stdenv, buildLXC, coreutils, bash }:

buildLXC ({ configuration, lxcLib }:
  let
    createIn = ./on-create.sh.in;
    create = stdenv.mkDerivation rec {
      name = "tsp-home-oncreate";
      buildCommand = ''
        sed -e "s|@coreutils@|${coreutils}|g" \
            -e "s|@user@|${configuration."home.user"}|g" \
            -e "s|@uid@|${toString configuration."home.uid"}|g" \
            -e "s|@group@|${configuration."home.group"}|g" \
            -e "s|@gid@|${toString configuration."home.gid"}|g" \
            -e "s|@shell@|${bash}/bin/sh|g" \
            ${createIn} > $out
        chmod +x $out
      '';
    };
  in
    {
      name = "tsp-home-lxc";
      storeMounts = { inherit bash; };
      onCreate = [ create ];
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
