{ stdenv, serfdom, tsp, coreutils, callPackage }:

tsp.container ({ global, configuration, containerLib }:
  let
    tsp_home = callPackage ../tsp-home-lxc { };
    tsp_network = callPackage ../tsp-network-lxc { };
    wrapped = stdenv.mkDerivation rec {
      name = "${serfdom.name}-lxc-wrapper";
      buildCommand = ''
        mkdir -p $out/sbin
        printf '#! ${stdenv.shell}
        export LOG_DIR=/var/log/${wrapped.name}
        ${coreutils}/bin/mkdir -p $LOG_DIR
        exec ${serfdom}/bin/serf agent -rpc-addr=${configuration.rpcIP}:7373 -tag router=${configuration.routerIP} -node=${configuration.identity} > $LOG_DIR/stdout 2> $LOG_DIR/stderr 0<&-' > $out/sbin/serfdom-start
        chmod +x $out/sbin/serfdom-start
      '';
    };
    doStart = configuration.start;
  in
    {
      name = "serfdom-lxc";
      storeMounts = { home         = tsp_home;
                      network      = tsp_network;
                      inherit (tsp) systemd_host;
                      inherit wrapped;
                    } // (if doStart then { inherit (tsp) init; } else {});
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
      } // (if doStart then { init.init = "${wrapped}/sbin/serfdom-start"; } else {});
    })
