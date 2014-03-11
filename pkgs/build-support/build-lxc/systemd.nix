{ tsp, lib }:

tsp.container ({ configuration, lxcLib }:
  {
    name = "systemd-lxc";
    options = {
      after      = lxcLib.mkOption { optional = true; default = [ "network.target" ]; };
      before     = lxcLib.mkOption { optional = true; default = []; };
      bindsTo    = lxcLib.mkOption { optional = true; default = []; };
      conflicts  = lxcLib.mkOption { optional = true; default = []; };
      partOf     = lxcLib.mkOption { optional = true; default = []; };
      requiredBy = lxcLib.mkOption { optional = true; default = []; };
      requires   = lxcLib.mkOption { optional = true; default = []; };
      wantedBy   = lxcLib.mkOption { optional = true; default = [ "multi-user.target" ]; };
      wants      = lxcLib.mkOption { optional = true; default = []; };
      enabled    = lxcLib.mkOption { optional = true; default = false; };
      name       = lxcLib.mkOption { optional = true; default = null; };
      dir        = lxcLib.mkOption { optional = true; default = null; };
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
                    if [ ! -f "${dir}/config" ]; then
                      ${pkg.create}
                    else
                      ${pkg.upgrade}
                    fi
                  '';
                  serviceConfig = {
                    ExecStart = "${pkg.start}";
                    ExecStop  = "${pkgs.lxc}/bin/lxc-stop -n ${name}";
                    Type      = "simple";
                    Restart   = "always";
                  };
                  unitConfig.RequiresMountsFor = dir;
                };
              }];
            };
          };
  })
