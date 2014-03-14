{ stdenv, tsp, lib, coreutils }:

tsp.container ({ configuration, lxcLib }:
  let
    inherit (lib) fold splitString;
    inherit (builtins) getAttr attrNames hasAttr listToAttrs filter length isString elem;
    inherit (lxcLib) sequence removePath appendPath setPath;
    name = "network";
    baseNetwork = {
      type  = "veth";
      link  = "br0";
      name  = "eth0";
      flags = "up";
    };
    validKeys = (attrNames baseNetwork) ++ ["ipv4" "ipv4.gateway" "mtu" "hwaddr"];
    networkConfiguration = network: fold (name: acc:
      acc ++ (if hasAttr name network then
                [{inherit name; value = getAttr name network;}]
              else
                []
             )) [] validKeys;
    nic = network: baseNetwork // (listToAttrs (networkConfiguration network));
    hostname = if configuration ? hostname then
                 [(setPath "utsname" configuration.hostname)]
               else
                 [];
    listDelete = toDelete: filter (e: e != toDelete);

    addNetworkLXC = network: acc:
      let fullNetwork = nic network; in
      # 'type' must come first as it symbolises the start of a new network section.
      fold (name: acc:
        [(appendPath "network.${name}" (getAttr name fullNetwork))] ++ acc)
        acc (["type"] ++ (listDelete "type" (attrNames fullNetwork)));
    networksLXC = fold addNetworkLXC hostname configuration.networks;

    addNetworkLibVirt = network:
      let fullNetwork = nic network; in ''
      <interface type='"'"'bridge'"'"'>
        <target dev='"'"'${fullNetwork.name}'"'"'/>
        <source bridge='"'"'${fullNetwork.link}'"'"'/>
        ${if fullNetwork ? hwaddr then ''<mac address='"'"'${fullNetwork.hwaddr}'"'"'/>'' else ""}
      </interface>
      '';
    networksLibVirt = map addNetworkLibVirt configuration.networks;

    createIn = ./on-create.sh.in;
    steriliseIn = ./on-sterilise.sh.in;
    create = stdenv.mkDerivation {
      name = "${name}-oncreate";
      buildCommand = ''
        sed -e "s|@coreutils@|${coreutils}|g" \
            -e "s|@hostname@|${configuration.hostname}|g" \
            ${createIn} > $out
        chmod +x $out
      '';
    };
    sterilise = stdenv.mkDerivation {
      name = "${name}-onsterilise";
      buildCommand = ''
        sed -e "s|@coreutils@|${coreutils}|g" \
            ${steriliseIn} > $out
        chmod +x $out
      '';
    };
  in
  {
    name = "${name}-lxc";
    lxcConf = sequence networksLXC;
    libVirtConf = { devices = networksLibVirt; };
    onCreate = [ create ];
    onSterilise = [ sterilise ];
    options = {
      hostname = lxcLib.mkOption { optional = true; };
      networks = lxcLib.mkOption {
                   optional = true;
                   default = [];
                   validator =
                     fold (network@{...}: acc:
                       fold (name: acc:
                         let value = getAttr name network; in
                         assert elem name validKeys;
                         if (name == "ipv4") || (name == "ipv4.gateway" && value != "auto") then
                           let components = splitString "." value; in
                           assert length components == 4;
                           acc
                         else if name == "ipv4.gateway" then
                           assert value == "auto";
                           acc
                         else if name == "hwaddr" then
                           let components = splitString ":" value; in
                           assert length components == 6;
                           acc
                         else
                           assert isString value;
                           acc
                       ) acc (attrNames network)) true;
                 };
    };
  })
