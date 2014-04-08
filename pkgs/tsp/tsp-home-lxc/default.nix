{ stdenv, tsp, coreutils, bash }:

tsp.container ({ global, configuration, containerLib }:
  let
    name = "tsp-home";
    createIn = ./on-create.sh.in;
    steriliseIn = ./on-sterilise.sh.in;
    create = stdenv.mkDerivation {
      name = "${name}-oncreate";
      buildCommand = ''
        sed -e "s|@coreutils@|${coreutils}|g" \
            -e "s|@user@|${configuration.user}|g" \
            -e "s|@uid@|${toString configuration.uid}|g" \
            -e "s|@group@|${configuration.group}|g" \
            -e "s|@gid@|${toString configuration.gid}|g" \
            -e "s|@shell@|${bash}/bin/sh|g" \
            ${createIn} > $out
        chmod +x $out
      '';
    };
    sterilise = stdenv.mkDerivation {
      name = "${name}-onsterilise";
      buildCommand = ''
        sed -e "s|@coreutils@|${coreutils}|g" \
            ${steriliseIn} > $out
        chmod +x $out
      '';
    };
  in
    {
      name = "${name}-lxc";
      storeMounts = [ bash ];
      onCreate = [ create ];
      onSterilise = [ sterilise ];
      options = {
        user  = containerLib.mkOption { optional = false; };
        uid   = containerLib.mkOption { optional = false; };
        group = containerLib.mkOption { optional = false; };
        gid   = containerLib.mkOption { optional = false; };
      };
    })
