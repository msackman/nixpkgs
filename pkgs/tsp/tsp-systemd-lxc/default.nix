{ stdenv, tsp, coreutils, systemd }:

tsp.container ({ global, configuration, containerLib }:
  let
    name = "tsp-systemd";
    doInit = configuration.asInit;
    allUnits = containerLib.gatherPathsWithSuffix ["systemd" "units"] global;
  in
    {
      name = "${name}-lxc";
      storeMounts = { inherit systemd; }
                    // (if doInit then { inherit (tsp) init; } else {});
      options = {
        allUnits = containerLib.mkOption {
                  optional = true;
                  default  = ["thedefault"];
                };
        asInit = containerLib.mkOption { optional = true; default = false; };
      };
      configuration = { inherit allUnits; } //
                      (if doInit then { init.init = "${systemd}/lib/systemd/systemd"; } else {});
    })
