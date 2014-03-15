{ stdenv, tsp, bash, coreutils }:

tsp.container ({ configuration, containerLib }:
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
    doStart = configuration.start;
  in
    {
      name = "${bash.name}-lxc";
      storeMounts = { inherit bash; } // (if doStart then { inherit (tsp) init; } else {});
      onCreate = [ create ];
      onSterilise = [ sterilise ];
      options = {
        start = containerLib.mkOption { optional = true; default = false; };
      };
      configuration = if doStart then { init.init = "${bash}/bin/bash"; } else {};
    })
