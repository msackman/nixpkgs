lxcDesc:
  { config, pkgs, ... }:
    with pkgs.lib;
    let
      name = lxcDesc.name;
      cfg = builtins.getAttr name config.services.lxc;
      createScript = lxcDesc.scripts + "/bin/lxc-create-${name}";
      startScript = lxcDesc.scripts + "/bin/lxc-start-${name}";
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
            containerPath = mkOption {
              type = types.path;
              default = "/var/lxc/${name}";
              description = ''
                Path to the container.
              '';
            };
            containerName = mkOption {
              type = types.str;
              default = "${name}";
              description = ''
                The name to run the contain as.
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
            wantedBy = [ "multi-user.target" ];
            after = [ "network.target" ];
            preStart = ''
              if [ ! -d "${cfg.containerPath}" ]; then
                mkdir -p $(dirname "${cfg.containerPath}")
                ${createScript} ${cfg.containerPath}
              fi
            '';
            serviceConfig = {
              ExecStart = "${startScript} ${cfg.containerPath} ${cfg.containerName}";
              ExecStop = "${pkgs.lxc}/bin/lxc-stop -k -n ${cfg.containerName}";
              Type = "forking";
              Restart = "always";
            };
            unitConfig.RequiresMountsFor = "${cfg.containerPath}";
          };
        }];
      };
    }