{ stdenv, tsp, coreutils, systemd }:

# This component is the guest-systemd
tsp.container ({ global, configuration, containerLib }:
  let
    name = "tsp-systemd-guest";
    doInit = configuration.asInit;
    allUnits = containerLib.gatherPathsWithSuffix ["systemd-units"] global;
  in
    {
      name = "${name}-lxc";
      storeMounts = { inherit systemd; }
                    // (if doInit then { inherit (tsp) init; } else {});
      options = {
        asInit = containerLib.mkOption { optional = true; default = true; };
      };
      configuration = if doInit then { init.init = "${systemd}/lib/systemd/systemd"; } else {};
    })
