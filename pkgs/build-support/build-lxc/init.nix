{ stdenv, tsp, coreutils, lxc }:

tsp.container ({ configuration, containerLib }:
  let
    name = "init";
    createIn = ./init-on-create.sh.in;
    steriliseIn = ./init-on-sterilise.sh.in;
    create = stdenv.mkDerivation {
      name = "${name}-oncreate";
      buildCommand = ''
        sed -e "s|@coreutils@|${coreutils}|g" \
            -e "s|@init@|${configuration.init}|g" \
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
      options = {
        init = containerLib.mkOption { optional = false; };
      };
      onCreate = [ create ];
      onSterilise = [ sterilise ];
      storeMounts = { inherit lxc; };
    })