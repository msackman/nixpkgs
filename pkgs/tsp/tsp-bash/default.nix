{ stdenv, tsp, bash, coreutils }:

tsp.container ({ configuration, lxcLib }:
  let
    createIn = ./on-create.sh.in;
    steriliseIn = ./on-sterilise.sh.in;
    create = stdenv.mkDerivation rec {
      name = "${bash.name}-oncreate";
      buildCommand = ''
        sed -e "s|@bash@|${bash}|g" \
            -e "s|@coreutils@|${coreutils}|g" \
            ${createIn} > $out
        chmod +x $out
      '';
    };
    sterilise = stdenv.mkDerivation rec {
      name = "${bash.name}-onsterilise";
      buildCommand = ''
        sed -e "s|@coreutils@|${coreutils}|g" \
            ${steriliseIn} > $out
        chmod +x $out
      '';
    };
  in
    {
      name = "${bash.name}-lxc";
      storeMounts = { inherit bash; };
      lxcConf =
        if configuration.start then
          lxcLib.setInit "${bash}/bin/bash"
        else
          lxcLib.id;
       onCreate = [ create ];
       onSterilise = [ sterilise ];
       options = {
         start = lxcLib.mkOption { optional = true; default = false; };
       };
    })
