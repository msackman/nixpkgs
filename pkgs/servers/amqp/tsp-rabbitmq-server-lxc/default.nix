{ tsp_rabbitmq_server, buildLXCRootFS, lib }:

buildLXCRootFS {
  name = "rabbitmq-server-lxc";
  pkgs = [ tsp_rabbitmq_server ];
  lxcFun = defaults:
    [{"network.type"  = "veth";}
     {"network.link"  = "br0" ;}
     {"network.name"  = "eth0";}
     {"network.flags" = "up"  ;}] ++ (
     builtins.filter (attrs:
       "network." != lib.substring 0 8 (builtins.head (builtins.attrNames attrs))
     ) defaults
    );
  exec = ${tsp_rabbitmq_server}/sbin/rabbitmq-server
}
