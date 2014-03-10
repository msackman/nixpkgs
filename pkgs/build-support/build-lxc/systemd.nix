{ tsp }:

tsp.container ({ configuration, lxcLib }:
  {
    name = "systemd-lxc";
    options = {
      wantedBy = lxcLib.mkOption { optional = true; default = [ "multi-user.target" ]; };
    };
    module =
      pkg: { config, pkgs, ... }:
        with pkgs.lib;
        let
          name = pkg.name;
          cfg = builtins.getAttr name config.services.lxc;
          createScript = pkg.scripts + "/bin/lxc-create-${name}";
          upgradeScript = pkg.scripts + "/bin/lxc-upgrade-${name}";
          startScript = pkg.scripts + "/bin/lxc-start-${name}";
        in
          {
            ###### interface
            options = {
              services.lxc = builtins.listToAttrs [
              { inherit name;
                value = {
                  enable = mkOption {
                    type = types.bool;
                    default = false;
                    description = ''
                      Whether to run the ${name} container.
                    '';
                  };
                };
              }];
            };

            ###### implementation
            config = mkIf cfg.enable {
              environment.systemPackages = [pkgs.lxc];
              systemd.services = builtins.listToAttrs [{
                inherit name;
                value = {
                  description = "LXC container: ${name}";
                  inherit (configuration) wantedBy;
                  after = [ "network.target" ];
                  preStart = ''
                    if [ ! -f "/var/lib/lxc/${name}/config" ]; then
                      ${createScript}
                    else
                      ${upgradeScript}
                    fi
                  '';
                  serviceConfig = {
                    ExecStart = "${startScript}";
                    ExecStop = "${pkgs.lxc}/bin/lxc-stop -n ${name}";
                    Type = "simple";
                    Restart = "always";
                  };
                  unitConfig.RequiresMountsFor = "/var/lib/lxc/${name}";
                };
              }];
            };
          };
  })
