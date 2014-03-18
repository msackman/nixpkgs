{ stdenv, tsp, coreutils, systemd, lib }:

# This component is the guest-systemd
tsp.container ({ global, configuration, containerLib }:
  let
    name = "tsp-systemd-guest";
    doInit = configuration.asInit;
    allUnits = containerLib.gatherPathsWithSuffix ["systemd_units"] global;
    allUnitsList = lib.concatLists (builtins.filter (e: builtins.isList e) allUnits);
    createIn = ./on-create.sh.in;
    steriliseIn = ./on-create.sh.in;
    create = stdenv.mkDerivation {
      name = "${name}-oncreate";
      buildCommand = ''
        sed -e "s|@coreutils@|${coreutils}|g" \
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
      storeMounts = { inherit systemd; }
                    // (if doInit then { inherit (tsp) init; } else {});
      options = {
        asInit = containerLib.mkOption { optional = true; default = true; };
        allUnits = containerLib.mkOption { optional = true; default = allUnitsList; };
      };
      configuration = if doInit then { init.init = "${systemd}/lib/systemd/systemd"; } else {};
      onCreate = [ create ];
      onSterilise = [ sterilise ];
    })
