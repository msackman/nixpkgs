{ tsp_rabbitmq_server, buildLXCRootFS, lib }:

buildLXCRootFS {
  name = "rabbitmq-server-lxc";
  pkgs = [ tsp_rabbitmq_server ];
  lxcFun = libraryPath: ''
    let lxcConfigLib = (import ${libraryPath}) lib; in
    {configFun = lxcConfigLib.addNetwork {
      type = "veth";
      link = "br0";
      name = "eth0";
      flags = "up";
      ipv4 = "192.168.99.99";
      "ipv4.gateway" = "192.168.99.1";};
     execFun = "${tsp_rabbitmq_server}/sbin/rabbitmq-server";
    }
    '';
}
