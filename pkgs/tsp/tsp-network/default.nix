{ tsp, lib }:

tsp.container ({ configuration, lxcLib }:
  {
    name = "network-lxc";
    lxcConf =
      let
        inherit (lib) fold;
        inherit (builtins) getAttr attrNames hasAttr listToAttrs filter;
        inherit (lxcLib) sequence removePath appendPath setPath;
        baseNetwork = {
          type  = "veth";
          link  = "br0";
          name  = "eth0";
          flags = "up";
        };
        networkConfiguration = network: fold (name: acc:
          acc ++ (if hasAttr name network then
                    [{inherit name; value = getAttr name network;}]
                  else
                    []
                 )) [] ((attrNames baseNetwork) ++ [ "ipv4" "ipv4.gateway" ]);
        nic = network: baseNetwork // (listToAttrs (networkConfiguration network));
        hostname = if configuration ? hostname then
                     [(setPath "utsname" configuration.hostname)]
                   else
                     [];
        listDelete = toDelete: filter (e: e != toDelete);
        addNetwork = network: acc:
          let fullNetwork = nic network; in
          # 'type' must come first as it symbolises the start of a new network section.
          fold (name: acc:
            [(appendPath "network.${name}" (getAttr name fullNetwork))] ++ acc)
            acc (["type"] ++ (listDelete "type" (attrNames fullNetwork)));
        networks = fold addNetwork hostname configuration.networks;
      in
        sequence networks;
    options = {
      hostname = lxcLib.mkOption { optional = true; };
      networks = lxcLib.mkOption { optional = true; default = []; };
    };
  })
