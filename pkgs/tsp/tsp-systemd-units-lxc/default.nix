{ stdenv, tsp, coreutils }:

# This component is just a collector for guest-systemd units
tsp.container ({ global, configuration, containerLib }:
  let
    name = "tsp-systemd-units";
  in
    {
      name = "${name}-lxc";
      options = {
        systemd-units = containerLib.mkOption {
                  optional = true;
                  default  = [];
                };
      };
    })
