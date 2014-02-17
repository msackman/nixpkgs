{ buildLXC, lib }:

buildLXC ({ configuration, lxcLib }:
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
        networkConfiguration = fold (name: acc:
          acc ++ (if hasAttr "network.${name}" configuration then
                    [{inherit name; value = getAttr "network.${name}" configuration;}]
                  else
                    []
                 )) [] [ "ipv4" "gateway" ];
        network = baseNetwork // (listToAttrs networkConfiguration);
        hostname = if configuration ? "network.hostname" then
                     [(setPath "utsname" configuration."network.hostname")]
                   else
                     [];
        listDelete = toDelete: filter (e: e != toDelete);
        addNetwork =
          # 'type' must come first. Yes, lxc.conf is retarded.
          fold (name: acc:
            [(removePath "network.${name}")
             (appendPath "network.${name}" (getAttr name network))] ++ acc)
            hostname (["type"] ++ (listDelete "type" (attrNames network)));
      in
        sequence addNetwork;
    options = [
      (lxcLib.declareOption {
        name = "network.ipv4";
        optional = true;
       })
      (lxcLib.declareOption {
        name = "network.gateway";
        optional = true;
       })
      (lxcLib.declareOption {
        name = "network.hostname";
        optional = true;
       })];
  })
