{ stdenv, makeWrapper, tsp_rabbitmq_server, buildLXC }:

let
  wrapped = stdenv.mkDerivation rec {
    name = "${tsp_rabbitmq_server.name}-wrapped";
    buildInputs = [ makeWrapper ];
    buildCommand = ''
      mkdir -p $out/sbin
      for f in rabbitmq-server rabbitmqctl rabbitmq-plugins; do
        makeWrapper ${tsp_rabbitmq_server}/sbin/$f $out/sbin/$f --set HOME /home/${name}
      done
    '';
  };
in
  buildLXC {
    name = "rabbitmq-server-lxc";
    pkgs = [ wrapped ];
    lxcConf = ''lxcConfLib: dir:
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
