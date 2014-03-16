{ stdenv, tsp, lib, coreutils }:

tsp.container ({ global, configuration, containerLib }:
  let
    inherit (lib) fold splitString;
    inherit (builtins) getAttr attrNames hasAttr listToAttrs filter length isString elem;
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

    addNetwork = network:
      let fullNetwork = nic network; in
      { name = "interface"; type = "bridge";
        value = [
            { name = "target"; dev = fullNetwork.name; }
            { name = "source"; bridge = fullNetwork.link; }
          ] ++ (if fullNetwork ? hwaddr then
                  [{ name = "mac"; address = fullNetwork.hwaddr; }]
                else
                  []);
      };
    networks = map addNetwork configuration.networks;

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
    containerConf = containerLib.extendContainerConf ["devices"] networks;
    onCreate = [ create ];
    onSterilise = [ sterilise ];
    options = {
      hostname = containerLib.mkOption { optional = true; };
      networks = containerLib.mkOption {
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
