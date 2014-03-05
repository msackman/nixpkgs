attrsOrPath:
  { config, pkgs, ... }:
    with pkgs.lib;
    let
      lxcDesc = if builtins.isAttrs attrsOrPath then
                  attrsOrPath
                else
                  (import attrsOrPath) { inherit pkgs; };
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
              if [ ! -f "/var/lib/lxc/${name}/config" ]; then
                ${createScript}
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
    }