{ stdenv, serfdom, buildLXC, bash, coreutils, gnused }:

buildLXC ({ configuration, lxcLib }:
  let
    tsp_dev_proc_sys = (import ../tsp-dev-proc-sys) { inherit stdenv buildLXC coreutils; };
    tsp_home = (import ../tsp-home) { inherit stdenv buildLXC coreutils bash; };
    tsp_network = (import ../tsp-network) { inherit buildLXC; };
    init = builtins.toFile "init" ''
      #! ${stdenv.shell}
      ${serfdom}/bin/serf agent -rpc-addr=${configuration."serfdom.rpcIP"}:7373 -tag router=${configuration."serfdom.routerIP"} -tag x=y -node=${configuration."network.hostname"}
    '';
    wrapped = stdenv.mkDerivation rec {
      name = "${serfdom.name}-lxc-wrapper";
      buildCommand = ''
        mkdir -p $out/sbin
        cp ${init} > $out/sbin/serf.init
        chmod +x $out/sbin/serf.init
      '';
    };
  in
    {
      name = "serfdom-lxc";
      storeMounts = [ tsp_dev_proc_sys tsp_home tsp_network wrapped ];
      lxcConf =
        if configuration."serfdom.start" then
          lxcLib.setInit "${wrapped}/sbin/serf.init"
        else
          lxcLib.id;
      options = [
        (lxcLib.declareOption {
          name = "serfdom.start";
          optional = true;
          default = false;
         })
        (lxcLib.declareOption {
          name = "serfdom.routerIP";
          optional = false;
         })
        (lxcLib.declareOption {
          name = "serfdom.rpcIP";
          optional = false;
         })];
      configuration = {
        "home.user"  = "serfdom";
        "home.uid"   = 1000;
        "home.group" = "serfdom";
        "home.gid"   = 1000;
      };
    })
