{ stdenv, makeWrapper, tsp_rabbitmq_server, erlang, buildLXC, procps, nettools, strace }:

let
  wrapped = stdenv.mkDerivation rec {
    name = "tsp-rabbitmq-server-${version}-wrapped";
    version = "3.2.2";
    buildInputs = [ makeWrapper ];
    buildCommand = ''
      mkdir -p $out/sbin
      for f in rabbitmq-server rabbitmqctl rabbitmq-plugins; do
        makeWrapper ${tsp_rabbitmq_server}/sbin/$f $out/sbin/$f --set HOME /home/${name}
      done
      makeWrapper ${erlang}/bin/erl $out/sbin/erl --set HOME /home/${name}
    '';
  };
in
  buildLXC {
    name = "rabbitmq-server-lxc";
    pkgs = [ wrapped procps nettools strace ];
    lxcConf = ''lxcConfLib:
      {conf = lxcConfLib.addNetwork {
        type           = "veth";
        link           = "br0";
        name           = "eth0";
        flags          = "up";
        ipv4           = "10.0.0.10";
        "ipv4.gateway" = "10.0.0.1";};
       exec = "${wrapped}/sbin/rabbitmq-server";
      }
      '';
  }
