{ stdenv, serfdom, tsp, callPackage }:

tsp.container ({ global, configuration, containerLib }:
  let
    tsp_home = callPackage ../tsp-home-lxc { };
    tsp_network = callPackage ../tsp-network-lxc { };
    tsp_systemd_guest = callPackage ../tsp-systemd-guest-lxc { };
    tsp_systemd_units = callPackage ../tsp-systemd-units-lxc { };
    wrapped = stdenv.mkDerivation rec {
      name = "${serfdom.name}-lxc-wrapper";
      buildCommand = ''
        mkdir -p $out/sbin
        printf '#! ${stdenv.shell}
        exec ${serfdom}/bin/serf agent -rpc-addr=${configuration.rpcIP}:7373 -tag router=${configuration.routerIP} -node=${configuration.identity}' > $out/sbin/serfdom-start
        chmod +x $out/sbin/serfdom-start
      '';
    };
  in
    {
      name = "serfdom-lxc";
      storeMounts = { home          = tsp_home;
                      network       = tsp_network;
                      systemd_guest = tsp_systemd_guest;
                      systemd_units = tsp_systemd_units;
                      inherit (tsp) systemd_host;
                      inherit wrapped;
                    };
      options = {
        start        = containerLib.mkOption { optional = true; default = false; };
        routerIP     = containerLib.mkOption { optional = false; };
        rpcIP        = containerLib.mkOption { optional = false; };
        identity     = containerLib.mkOption { optional = false; };
      };
      configuration = {
        home.user  = "serfdom";
        home.uid   = 1000;
        home.group = "serfdom";
        home.gid   = 1000;
        systemd_units.systemd_services = {
          serfdom = {
            description = "${serfdom.name}";
            wantedBy = [ "multi-user.target" ];
            requires = [ "network.target" ];
            after = [ "network.target" ];
            serviceConfig = {
              Type = "simple";
              ExecStart = "${wrapped}/sbin/serfdom-start";
            };
          };
        };
      };
    })
