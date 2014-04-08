{ tsp, utillinux, coreutils, erlang, nettools, iproute, netcat, host, callPackage }:

tsp.container ({ global, configuration, containerLib }:
  let
    tsp_bash = callPackage ../tsp-bash-lxc { };
    tsp_home = callPackage ../tsp-home-lxc { };
    tsp_network = callPackage ../tsp-network-lxc { };
    tsp_systemd_guest = callPackage ../tsp-systemd-guest-lxc { };
    tsp_systemd_units = callPackage ../tsp-systemd-units-lxc { };
  in
    {
      name = "shell-lxc";
      imports = {
        bash          = tsp_bash;
        network       = tsp_network;
        home          = tsp_home;
        systemd_units = tsp_systemd_units;
        systemd_guest = tsp_systemd_guest;
      };
      storeMounts = [ utillinux erlang nettools coreutils iproute netcat host ];
      configuration = {
        home.user  = "shell";
        home.uid   = 1000;
        home.group = "shell";
        home.gid   = 1000;
        systemd_units.systemd_services = {
          shell = {
            description = "Emergency Shell";
            serviceConfig = {
              Type = "simple";
              ExecStart = "${utillinux}/sbin/agetty --noclear -n -l /bin/sh console 38400";
            };
          };
        };
      };
    })
