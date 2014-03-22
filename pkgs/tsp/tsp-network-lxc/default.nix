{ stdenv, tsp, lib, coreutils, callPackage, iproute, ethtool }:

tsp.container ({ global, configuration, containerLib }:
  let
    inherit (lib) fold foldl splitString optionalString;
    inherit (builtins) getAttr attrNames hasAttr listToAttrs filter length isString elem elemAt head;
    tsp_systemd_units = callPackage ../tsp-systemd-units-lxc { };
    name = "network";

    baseNetwork = {
      type  = "veth"; ## In truth, we don't support anything else just ATM.
      link  = "br0";
      flags = "up";
    };
    validKeys = (attrNames baseNetwork) ++ ["ipv4" "ipv4.gateway" "mtu" "hwaddr"];

    extendNetwork = network:
      baseNetwork // (listToAttrs (fold (key: acc:
        if hasAttr key network then
          [{ name = key; value = getAttr key network; }] ++ acc
        else
          acc
      ) [] validKeys));

    configureNetwork = nicNum: network:
      let
        guestNicName = "eth${toString nicNum}";
        fullNetwork = extendNetwork network;
        ipPrefix = lib.splitString "/" fullNetwork.ipv4;
        ipv4 = head ipPrefix;
        mask = if length ipPrefix == 2 then elemAt ipPrefix 1 else "24";
      in
        {
          containerConf =
            { name = "interface"; type = "bridge";
              value = [
                  { name = "source"; bridge = fullNetwork.link; }
                ] ++ (if fullNetwork ? hwaddr then
                        [{ name = "mac"; address = fullNetwork.hwaddr; }]
                      else
                        []);
            };
          systemd_unit_pair =
            {
              name = "network-${guestNicName}";
              value =
                {
                  description = "Network interface configuration for ${guestNicName}";
                  wantedBy = [ "network.target" ];
                  requires = [];
                  before = [ "network.target" ];
                  after = [ "network-interfaces.target" ];
                  serviceConfig.Type = "oneshot";
                  serviceConfig.RemainAfterExit = true;
                  script =
                    ''
                      printf "bringing up interface...\n"
                      ${iproute}/sbin/ip link set "${guestNicName}" up
                    ''
                    + optionalString (fullNetwork ? hwaddr)
                      ''
                        printf "setting MAC address to ${fullNetwork.hwaddr}...\n"
                        ${iproute}/sbin/ip link set "${guestNicName}" address "${fullNetwork.hwaddr}"
                      ''
                    + optionalString (fullNetwork ? mtu)
                      ''
                        printf "setting MTU to ${toString fullNetwork.mtu}...\n"
                        ${iproute}/sbin/ip link set "${guestNicName}" mtu "${toString fullNetwork.mtu}"
                      ''
                    + optionalString (fullNetwork ? ipv4)
                      ''
                        printf "configuring interface...\n"
                        ${iproute}/sbin/ip -4 addr flush dev "${guestNicName}"
                        ${iproute}/sbin/ip -4 addr add "${ipv4}/${mask}" dev "${guestNicName}"
                      ''
                    + optionalString (fullNetwork ? "ipv4.gateway")
                      ''
                        printf "adding gateway...\n"
                        ${iproute}/sbin/ip route add default via "${fullNetwork."ipv4.gateway"}" || true
                      ''
                    + ''
                        printf "turning off TOE expectations...\n"
                        for opt in rx tx sg tso ufo gso gro lro rxvlan txvlan rxhash; do
                          ${ethtool}/sbin/ethtool --offload "${guestNicName}" "$opt" off || true
                        done
                      '';
                };
            };
        };

    networks =
      let nets = configuration.networks; in
      (foldl ({num, list}: network:
         {
           num  = num + 1;
           list = list ++ [(configureNetwork num network)];
         }) {num = 0; list = [];} nets).list;

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
    containerConf = containerLib.extendContainerConf ["devices"] (map (e: e.containerConf) networks);
    onCreate = [ create ];
    onSterilise = [ sterilise ];
    storeMounts = { systemd_units = tsp_systemd_units; };
    configuration = { systemd_units.systemd_services = listToAttrs (map (e: e.systemd_unit_pair) networks); };
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
                         if (name == "ipv4") || (name == "ipv4.gateway") then
                           let components = splitString "." value; in
                           assert length components == 4;
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
