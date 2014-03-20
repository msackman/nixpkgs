{ tsp, lib }:

tsp.container ({ global, configuration, containerLib }:
  {
    name = "systemd-host-lxc";
    options = {
      after      = containerLib.mkOption { optional = true; default = [ "network.target" ]; };
      before     = containerLib.mkOption { optional = true; default = []; };
      bindsTo    = containerLib.mkOption { optional = true; default = []; };
      conflicts  = containerLib.mkOption { optional = true; default = []; };
      partOf     = containerLib.mkOption { optional = true; default = []; };
      requiredBy = containerLib.mkOption { optional = true; default = []; };
      requires   = containerLib.mkOption { optional = true; default = []; };
      wantedBy   = containerLib.mkOption { optional = true; default = [ "multi-user.target" ]; };
      wants      = containerLib.mkOption { optional = true; default = []; };
      enabled    = containerLib.mkOption { optional = true; default = false; };
      name       = containerLib.mkOption { optional = true; default = null; };
      dir        = containerLib.mkOption { optional = true; default = null; };
    };
    module =
      pkg: { config, pkgs, ... }:
        with pkgs.lib;
        let
          name = if configuration.name == null then pkg.name else configuration.name;
          dir = if configuration.dir == null then "/var/lib/lxc/${name}" else configuration.dir;
        in
          {
            config = mkIf configuration.enabled {
              environment.systemPackages = [pkgs.lxc];
              systemd.services = builtins.listToAttrs [{
                inherit name;
                value = {
                  description = "LXC container: ${name}";
                  inherit (configuration)
                    after before bindsTo conflicts partOf requiredBy requires wantedBy wants;
                  preStart = ''
                    if [ ! -f "${dir}/creator" ]; then
                      ${pkg.create}
                    else
                      ${pkg.upgrade}
                    fi
                  '';
                  serviceConfig = {
                    ExecStart       = "${pkg.start}";
                    ExecStop        = "${pkg.stop}";
                    Type            = "oneshot";
                    Restart         = "always";
                    RemainAfterExit = true;
                  };
                  unitConfig.RequiresMountsFor = dir;
                };
              }];
            };
          };
  })
