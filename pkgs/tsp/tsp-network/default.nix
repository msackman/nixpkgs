{ buildLXC, lib }:

buildLXC ({ configuration, lxcLib }:
  {
    name = "network-lxc";
    lxcConf =
      let
        inherit (lib) fold;
        inherit (builtins) getAttr attrNames hasAttr listToAttrs;
        inherit (lxcLib) sequence removePath appendPath setPath;
        baseNetwork = {
          network.type  = "veth";
          network.link  = "br0";
          network.name  = "eth0";
          network.flags = "up";
        };
        networkConfiguration = fold (name: acc:
          acc ++ (if hasAttr name configuration then
                    [{inherit name; value = getAttr name configuration;}]
                  else
                    []
                 )) [] [ "network.ipv4" "network.gateway" ]
        network = acc // (listToAttrs networkConfiguration)
        hostname = if options ? "network.hostname" then
                     [setPath "utsname" (configuration."network.hostname")]
                   else
                     [];
        listDelete = toDelete: filter (e: e != toDelete);
        addNetwork = network:
          # 'type' must come first. Yes, lxc.conf is retarded.
          sequence (fold (name: acc:
            [(removePath "network.${name}")
             (appendPath "network.${name}" (getAttr name network))] ++ acc
          ) [] (["type"] ++ (listDelete "type" (attrNames network))));
      in
        sequence ([(lxcLib.addNetwork network)] ++ hostname);
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