{ tsp_rabbitmq_server, buildLXC, lib }:

buildLXC {
  name = "rabbitmq-server-lxc";
  pkgs = [ tsp_rabbitmq_server ];
  lxcConf = ''lxcConfLib:
    {conf = lxcConfLib.addNetwork {
      type           = "veth";
      link           = "br0";
      name           = "eth0";
      flags          = "up";
      ipv4           = "10.0.0.10";
      "ipv4.gateway" = "10.0.0.1";};
     exec = "${tsp_rabbitmq_server}/sbin/rabbitmq-server";
     lxcPkgs = [ ];
    }
    '';
}
