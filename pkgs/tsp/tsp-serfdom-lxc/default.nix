{ stdenv, serfdom, buildLXC, bash, coreutils, lib }:

buildLXC ({ configuration, lxcLib }:
  let
    tsp_dev_proc_sys = (import ../tsp-dev-proc-sys) { inherit stdenv buildLXC coreutils; };
    tsp_home = (import ../tsp-home) { inherit stdenv buildLXC coreutils bash; };
    tsp_network = (import ../tsp-network) { inherit buildLXC lib; };
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
  in
    {
      name = "serfdom-lxc";
      storeMounts = { dev_proc_sys = tsp_dev_proc_sys;
                      home         = tsp_home;
                      network      = tsp_network;
                      inherit wrapped; };
      lxcConf =
        if configuration.start then
          lxcLib.setInit "${wrapped}/sbin/serfdom-start"
        else
          lxcLib.id;
      options = {
        start        = lxcLib.mkOption { optional = true; default = false; };
        routerIP     = lxcLib.mkOption { optional = false; };
        rpcIP        = lxcLib.mkOption { optional = false; };
        identity     = lxcLib.mkOption { optional = false; };
      };
      configuration = {
        home.user  = "serfdom";
        home.uid   = 1000;
        home.group = "serfdom";
        home.gid   = 1000;
      };
    })
