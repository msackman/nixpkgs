{ stdenv, tsp_router, erlang, bridge_utils, nettools, buildLXC, bash, coreutils, lib }:

buildLXC ({ configuration, lxcLib }:
  let
    tsp_bash = (import ../tsp-bash) { inherit stdenv buildLXC bash coreutils; };
    tsp_dev_proc_sys = (import ../tsp-dev-proc-sys) { inherit stdenv buildLXC coreutils; };
    tsp_home = (import ../tsp-home) { inherit stdenv buildLXC coreutils bash; };
    tsp_network = (import ../tsp-network) { inherit buildLXC lib; };
    mknodtuntap = stdenv.mkDerivation rec {
      name = "${tsp_router.name}-mknodtuntap";
      buildCommand = ''
        printf 'mkdir -p $LXC_ROOTFS_MOUNT/dev/net
        if [ ! -e "$LXC_ROOTFS_MOUNT/dev/net/tun" ]; then
          ${coreutils}/bin/mknod $LXC_ROOTFS_MOUNT/dev/net/tun c 10 200
        fi
        ' > $out
        chmod +x $out
      '';
    };
    wrapped = stdenv.mkDerivation rec {
      name = "${tsp_router.name}-lxc-wrapper";
      buildCommand = ''
        mkdir -p $out/sbin
        printf '#! ${stdenv.shell}
        export HOME=/home/${configuration.home.user}
        export PATH=${bridge_utils}/bin:${bridge_utils}/sbin:${nettools}/bin:${nettools}/sbin:${coreutils}/bin:$PATH
        brctl addbr ${configuration.internal_bridge.name}
        brctl addif ${configuration.internal_bridge.name} ${configuration.internal_bridge.nic}
        ifconfig ${configuration.internal_bridge.name} ${configuration.internal_bridge.ip} netmask ${configuration.internal_bridge.netmask} up
        export LOG_DIR=/var/log/${wrapped.name}
        mkdir -p $LOG_DIR
        exec ${erlang}/bin/erl -pa ${tsp_router}/deps/*/ebin ${tsp_router}/ebin -tsp node_name \\"${configuration.identity}\\" -tsp serf_addr \\"${configuration.serfdom}\\" -tsp tap_name \\"tsp%%d\\" -tsp eth_dev undefined -tsp bridge \\"${configuration.internal_bridge.name}\\" -sname router ${if lxcLib.hasConfigurationPath configuration ["erlang" "cookie"] then "-setcookie ${configuration.erlang.cookie}" else ""} -sasl sasl_error_logger \\{file,\\"$LOG_DIR/sasl\\"\\} -sasl errlog_type error -s tsp -noinput > $LOG_DIR/stdout 2> $LOG_DIR/stderr 0<&-' > $out/sbin/router-start
        chmod +x $out/sbin/router-start
      '';
    };
  in
    {
      name = "${tsp_router.name}-lxc";
      storeMounts = { bash         = tsp_bash;
                      dev_proc_sys = tsp_dev_proc_sys;
                      home         = tsp_home;
                      network      = tsp_network;
                      inherit wrapped; };
      lxcConf = lxcLib.sequence [
        (if configuration.start then
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
        (lxcLib.appendPath "hook.autodev" mknodtuntap)
      ];
      options = {
        start           = lxcLib.mkOption { optional = true; default = false; };
        identity        = lxcLib.mkOption { optional = false; };
        internal_bridge = {
          name           = lxcLib.mkOption { optional = true; default = "br0"; };
          ip             = lxcLib.mkOption { optional = false; };
          netmask        = lxcLib.mkOption { optional = false; };
          nic            = lxcLib.mkOption { optional = false; };
        };
        erlang.cookie   = lxcLib.mkOption { optional = true; };
        serfdom         = lxcLib.mkOption { optional = false; };
      };
      configuration = {
        home.user  = "router";
        home.uid   = 1000;
        home.group = "router";
        home.gid   = 1000;
      };
    })
