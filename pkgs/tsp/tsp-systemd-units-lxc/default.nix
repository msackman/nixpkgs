{ stdenv, tsp, coreutils }:

tsp.container ({ global, configuration, containerLib }:
  let
    name = "tsp-systemd-units";
  in
    {
      name = "${name}-lxc";
      options = {
        units = containerLib.mkOption {
                  optional = true;
                  default  = [];
                };
      };
    })
