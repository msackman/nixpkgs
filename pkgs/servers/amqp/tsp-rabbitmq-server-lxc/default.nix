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
      ipv4           = "192.168.99.99";
      "ipv4.gateway" = "192.168.99.1";};
     exec = "${tsp_rabbitmq_server}/sbin/rabbitmq-server";
     lxcPkgs = [ ];
    }
    '';
}
