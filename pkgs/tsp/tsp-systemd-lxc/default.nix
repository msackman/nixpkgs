{ stdenv, tsp, coreutils, systemd }:

tsp.container ({ global, configuration, containerLib }:
  let
    name = "tsp-systemd";
    doInit = configuration.asInit;
    units = containerLib.gatherPathsWithSuffix ["systemd" "units"] global;
  in
    {
      name = "${name}-lxc";
      storeMounts = { inherit systemd; }
                    // (if doInit then { inherit (tsp) init; } else {});
      options = {
        units = containerLib.mkOption {
                  optional = true;
                  default  = [];
                };
        asInit = containerLib.mkOption { optional = true; default = false; };
      };
      configuration = { units = units ++ units; } //
                      (if doInit then { init.init = "${systemd}/lib/systemd/systemd"; } else {});
    })
