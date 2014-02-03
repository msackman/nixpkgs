{ buildLXC }:
  {ip, gw, hostname} :
    buildLXC {
      name = "network-lxc";
      lxcConf = ''lxcConfLib: dir:
        {conf = lxcConfLib.sequence [
          (lxcConfLib.addNetwork {
            type           = "veth";
            link           = "br0";
            name           = "eth0";
            flags          = "up";
            ipv4           = "${ip}";
            "ipv4.gateway" = "${gw}";})
          (lxcConfLib.setPath "utsname" "${hostname}")
        ];}
      '';
    }
