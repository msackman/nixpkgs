{ stdenv, makeWrapper, tsp_rabbitmq_server, buildLXC, bash, coreutils, lib }:

buildLXC ({ configuration, lxcLib }:
  let
    tsp_bash = (import ../tsp-bash) { inherit stdenv buildLXC bash coreutils; };
    tsp_dev_proc_sys = (import ../tsp-dev-proc-sys) { inherit stdenv buildLXC coreutils; };
    tsp_home = (import ../tsp-home) { inherit stdenv buildLXC coreutils bash; };
    tsp_network = (import ../tsp-network) { inherit buildLXC lib; };
    wrapped = stdenv.mkDerivation rec {
      name = "${tsp_rabbitmq_server.name}-lxc-wrapper";
      buildInputs = [ makeWrapper ];
      buildCommand = ''
        mkdir -p $out/sbin
        for f in rabbitmq-server rabbitmqctl rabbitmq-plugins; do
          makeWrapper ${tsp_rabbitmq_server}/sbin/$f $out/sbin/$f \
            --set HOME /home/${configuration."home.user"} \
            --set ERL_INETRC /home/${configuration."home.user"}/.rabbitmq/3.2.2/etc/rabbitmq/erl_inetrc
        done
      '';
    };
  in
    {
      name = "rabbitmq-server-lxc";
      storeMounts = [ tsp_bash tsp_dev_proc_sys tsp_network tsp_home tsp_rabbitmq_server wrapped ];
      lxcConf =
        if configuration."rabbitmq_server.start" then
          lxcLib.setInit "${wrapped}/sbin/rabbitmq-server"
        else
          lxcLib.id;
      options = [
        (lxcLib.declareOption {
          name = "rabbitmq_server.start";
          optional = true;
          default = false;
         })];
      configuration = {
        "home.user"  = "rabbit";
        "home.uid"   = 1000;
        "home.group" = "rabbit";
        "home.gid"   = 1000;
      };
    })
