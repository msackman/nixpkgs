{ stdenv, tsp, bash, coreutils, callPackage }:

tsp.container ({ global, configuration, containerLib }:
  let
    tsp_systemd_units = callPackage ../tsp-systemd-units-lxc { };
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
    enable = configuration.enable;
  in
    {
      name = "${bash.name}-lxc";
      storeMounts = { inherit bash; } // (if enable then { systemd = tsp_systemd_units; } else {});
      onCreate = [ create ];
      onSterilise = [ sterilise ];
      options = {
        enable = containerLib.mkOption { optional = true; default = false; };
      };
      configuration = if enable then { systemd.units = ["hello"]; } else {};
    })
