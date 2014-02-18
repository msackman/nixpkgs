{ stdenv, tsp_router, erlang, bridge_utils, nettools, buildLXC, bash, coreutils, lib }:

buildLXC ({ configuration, lxcLib }:
  let
    tsp_bash = (import ../tsp-bash) { inherit stdenv buildLXC bash coreutils; };
    tsp_dev_proc_sys = (import ../tsp-dev-proc-sys) { inherit stdenv buildLXC coreutils; };
    tsp_home = (import ../tsp-home) { inherit stdenv buildLXC coreutils bash; };
    tsp_network = (import ../tsp-network) { inherit buildLXC lib; };
    wrapped = stdenv.mkDerivation rec {
      name = "${tsp_router.name}-lxc-wrapper";
      buildCommand = ''
        mkdir -p $out/sbin
        printf '#! ${stdenv.shell}
        export HOME=/home/${configuration."home.user"}
        export PATH=${bridge_utils}/bin:${bridge_utils}/sbin:${nettools}/bin:${nettools}/sbin:$PATH
        brctl addbr ${configuration."router.internal_bridge"}
        brctl addif ${configuration."router.internal_bridge"} ${configuration."router.internal_bridge.nic"}
        ifconfig ${configuration."router.internal_bridge"} ${configuration."router.internal_bridge.ip"} netmask ${configuration."router.internal_bridge.netmask"} up
        ${erlang}/bin/erl -pa ${tsp_router}/deps/*/ebin ${tsp_router}/ebin -tsp node_name \\"${configuration."router.identity"}\\" -tsp serf_addr \\"${configuration."router.serfdom"}\\" -sname router -s tsp' > $out/sbin/router-start
        chmod +x $out/sbin/router-start
      '';
    };
  in
    {
      name = "${tsp_router.name}-lxc";
      storeMounts = [ tsp_bash tsp_router tsp_dev_proc_sys tsp_home tsp_network wrapped ];
      lxcConf = lxcLib.sequence [
        (if configuration."router.start" then
           lxcLib.setInit "${wrapped}/sbin/router-start"
         else
           lxcLib.id)
        (lxcLib.replacePath "cap.drop" (old:
           let
             dropped = lib.splitString " " old.value;
             remains = builtins.filter (e: e != "sys_admin") dropped;
             rejoined = lib.concatStringsSep " " remains;
           in
             old // { value = rejoined; }))
      ];
      options = [
        (lxcLib.declareOption {
          name = "router.start";
          optional = true;
          default = false;
         })
        (lxcLib.declareOption {
          name = "router.identity";
          optional = false;
         })
        (lxcLib.declareOption {
          name = "router.internal_bridge";
          optional = true;
          default = "br0";
         })
        (lxcLib.declareOption {
          name = "router.internal_bridge.ip";
          optional = false;
         })
        (lxcLib.declareOption {
          name = "router.internal_bridge.netmask";
          optional = true;
         })
        (lxcLib.declareOption {
          name = "router.internal_bridge.nic";
          optional = false;
         })
        (lxcLib.declareOption {
          name = "router.serfdom";
          optional = false;
         })];
      configuration = {
        "home.user"  = "router";
        "home.uid"   = 1000;
        "home.group" = "router";
        "home.gid"   = 1000;
      };
    })
