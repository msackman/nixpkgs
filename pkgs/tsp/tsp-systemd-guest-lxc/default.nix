{ stdenv, tsp, coreutils, systemd, lib }:

# This component is the guest-systemd
tsp.container ({ global, configuration, containerLib }:
  let
    name = "tsp-systemd-guest";
    doInit = configuration.asInit;
    allUnits = containerLib.gatherPathsWithSuffix ["systemd_units"] global;
    allUnitsList = lib.concatLists (builtins.filter (e: builtins.isList e) allUnits);
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
    })
