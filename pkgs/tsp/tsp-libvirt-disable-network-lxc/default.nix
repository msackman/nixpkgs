{ stdenv, tsp }:

tsp.container ({ global, configuration, containerLib }:
  {
    name = "tsp-libvirt-disable-network-lxc";
    options = {
      disable = containerLib.mkOption { optional = true; default = false; };
    };
    module = pkg: { config, pkgs, ... }:
      {
        config = pkgs.lib.mkIf (! configuration.disable) {
          systemd.services.libvirtd-disable-default-network = {
            description = "Disable libvirtd default network";
            requires = ["libvirtd.service"];
            after = ["libvirtd.service"];
            wantedBy = [ "multi-user.target" ];
            serviceConfig = {
              Type = "oneshot";
              RemainAfterExit = true;
            };
            script = ''
              ${pkgs.libvirt}/bin/virsh net-destroy default || true
              ${pkgs.libvirt}/bin/virsh net-undefine default || true
            '';
          };
        };
      };
  })