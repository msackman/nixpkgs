{ stdenv, makeWrapper, tsp_rabbitmq_server, buildLXC, bash, coreutils }:

let
  user = "rabbit";
  uid = 1000;
  group = "rabbit";
  gid = 1000;
  tsp_bash = (import ../tsp-bash) { inherit stdenv buildLXC bash coreutils; };
  tsp_dev_proc_sys = (import ../tsp-dev-proc-sys) { inherit stdenv buildLXC coreutils; };
  tsp_home = (import ../tsp-home) { inherit stdenv buildLXC coreutils bash tsp_bash; };
  wrapped = stdenv.mkDerivation rec {
    name = "${tsp_rabbitmq_server.name}-wrapped";
    buildInputs = [ makeWrapper ];
    buildCommand = ''
      mkdir -p $out/sbin
      for f in rabbitmq-server rabbitmqctl rabbitmq-plugins; do
        makeWrapper ${tsp_rabbitmq_server}/sbin/$f $out/sbin/$f --set HOME /home/${user}
      done
    '';
  };
in
  buildLXC {
    name = "rabbitmq-server-lxc";
    pkgs = [ wrapped bash ];
    lxcConf = ''lxcConfLib: dir:
      {conf = lxcConfLib.addNetwork {
        type           = "veth";
        link           = "br0";
        name           = "eth0";
        flags          = "up";
        ipv4           = "10.0.0.10";
        "ipv4.gateway" = "10.0.0.1";};
       exec = "${wrapped}/sbin/rabbitmq-server";
       lxcPkgs = [ "${tsp_bash}" "${tsp_dev_proc_sys}" "${tsp_home user uid group gid}" ];
      }
      '';
  }
