{ stdenv, tsp, lib, coreutils, callPackage, iproute }:

tsp.container ({ global, configuration, containerLib }:
  let
    inherit (lib) fold splitString optionalString;
    inherit (builtins) getAttr attrNames hasAttr listToAttrs filter length isString elem elemAt head;
    tsp_systemd_units = callPackage ../tsp-systemd-units-lxc { };
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

    systemdGuestService = network:
      let
        fullNetwork = nic network;
        ipPrefix = lib.splitString "/" fullNetwork.ipv4;
        ipv4 = head ipPrefix;
        mask = if length ipPrefix == 2 then elemAt ipPrefix 1 else "24";
      in
        {
          description = "Network interface configuration for ${fullNetwork.name}";
          wantedBy = [ "network-interfaces.target" ];
          serviceConfig.type = "oneshot";
          serviceConfig.RemainAfterExit = true;
          script =
            ''
              printf "bringing up interface...\n"
              ${iproute}/sbin/ip link set "${fullNetwork.name}" up
            ''
            + optionalString (fullNetwork ? hwaddr)
              ''
                printf "setting MAC address to ${fullNetwork.hwaddr}...\n"
                ${iproute}/sbin/ip link set "${fullNetwork.name}" address "${fullNetwork.hwaddr}"
              ''
            + optionalString (fullNetwork ? mtu)
              ''
                printf "setting MTU to ${toString fullNetwork.mtu}...\n"
                ${iproute}/sbin/ip link set "${fullNetwork.name}" mtu "${toString fullNetwork.mtu}"
              ''
            + optionalString (fullNetwork ? ipv4)
              ''
                printf "configuring interface...\n"
                ${iproute}/sbin/ip -4 addr flush dev "${fullNetwork.name}"
                ${iproute}/sbin/ip -4 addr add "${ipv4}/${mask}" dev "${fullNetwork.name}"
              '';
        };

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
    storeMounts = { systemd_units = tsp_systemd_units; };
    configuration = { systemd_units.systemd_units = map systemdGuestService configuration.networks; };
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
