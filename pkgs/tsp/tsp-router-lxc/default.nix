{ stdenv, tsp_router, erlang, bridge_utils, iproute, tsp, coreutils, iptables, lib, callPackage }:

tsp.container ({ global, configuration, containerLib }:
  let
    tsp_bash = callPackage ../tsp-bash-lxc { };
    tsp_home = callPackage ../tsp-home-lxc { };
    tsp_network = callPackage ../tsp-network-lxc { };
    tsp_systemd_guest = callPackage ../tsp-systemd-guest-lxc { };
    tsp_systemd_units = callPackage ../tsp-systemd-units-lxc { };
    logDirName = tsp_router.name;

    # Erlang is monumentally stupid and demands that it can take the
    # value passed via -config and add a ".config" suffix and then
    # that's the name of the file. Hence the daftness in what follows:
    configFile = stdenv.mkDerivation rec {
      name = "${tsp_router.name}-config";
      buildCommand = ''
        mkdir -p $out
        printf '
        [
          {sasl, [{sasl_error_logger, {file, "/var/log/${logDirName}/sasl.log"}}]},
          {lager, [
            {handlers, [
              {lager_console_backend, info},
              {lager_file_backend, [{file, "/var/log/${logDirName}/error.log"}, {level, error}]},
              {lager_file_backend, [{file, "/var/log/${logDirName}/console.log"}, {level, info}]}
             ]},
            {error_logger_redirect, false}
           ]},
          {tsp, [
            {node_name, "${configuration.identity}"},
            {serf_addr, "${configuration.serfdom}"},
            {tap_name,  "tsp%%d"},
            {eth_dev,   undefined},
            {bridge,    "${configuration.internal_bridge}"},
            {join_at_start, [${peers}]}
           ]}
        ].
        ' > $out/config.config
      '';
    };
    peers = toString (lib.intersperse "," (map (e: ''"${e}"'') configuration.peers));
    cookieStr = if containerLib.hasConfigurationPath configuration ["erlang" "cookie"] then
                  "-setcookie ${configuration.erlang.cookie}"
                else
                  "";
    wrapped = stdenv.mkDerivation rec {
      name = "${tsp_router.name}-lxc-wrapper";
      buildCommand = ''
        mkdir -p $out/sbin
        printf '#! ${stdenv.shell}
        export HOME=/home/${configuration.home.user}
        export PATH=${bridge_utils}/bin:${bridge_utils}/sbin:${iproute}/bin:${iproute}/sbin:${coreutils}/bin:$PATH
        brctl addbr ${configuration.internal_bridge}
        brctl addif ${configuration.internal_bridge} "eth0"
        ip link set "${configuration.internal_bridge}" up
        ip -4 addr add "${configuration.sdn.guest_ip}/${toString configuration.sdn.prefix}" dev "${configuration.internal_bridge}"
        export LOG_DIR=/var/log/${logDirName}
        mkdir -p $LOG_DIR # still need this for lager and sasl logs
        exec ${erlang}/bin/erl -pa ${tsp_router}/deps/*/ebin ${tsp_router}/ebin -sname router ${cookieStr} -config ${configFile}/config -s tsp -noinput' > $out/sbin/router-start
        chmod +x $out/sbin/router-start  # */ <- hack for emacs mode
      '';
    };

    bridgeOptions = {
      bridge    = containerLib.mkOption {optional = false;};
      network   = containerLib.mkOption {optional = false;};
      prefix    = containerLib.mkOption {optional = false;};
      host_ip   = containerLib.mkOption {optional = false;};
      guest_ip  = containerLib.mkOption {optional = false;};
      interface = containerLib.mkOption {optional = true;};
    };
  in
    {
      name = "${tsp_router.name}-lxc";
      storeMounts = { bash          = tsp_bash;
                      home          = tsp_home;
                      network       = tsp_network;
                      systemd_guest = tsp_systemd_guest;
                      systemd_units = tsp_systemd_units;
                      inherit (tsp) systemd_host;
                      inherit wrapped;
                    };
      containerConf =
        containerLib.extendContainerConf ["devices"]
                                         { name = "hostdev"; mode = "capabilities"; type = "misc";
                                           value = { name = "source";
                                                     value = { name = "char";
                                                               value = "/dev/net/tun";
                                                             };
                                                   };
                                         };
      options = {
        sdn = bridgeOptions;
        external = bridgeOptions;
        identity        = containerLib.mkOption { optional = false; };
        serfdom         = containerLib.mkOption { optional = false; };
        internal_bridge = containerLib.mkOption { optional = true; default = "internalBridge"; };
        erlang.cookie   = containerLib.mkOption { optional = true; };
        peers           = containerLib.mkOption { optional = true; default = []; };
      };
      configuration = {
        home.user  = "router";
        home.uid   = 1000;
        home.group = "router";
        home.gid   = 1000;
        network.networks = [{link = configuration.sdn.bridge;}     # eth0
                            {link = configuration.external.bridge; # eth1
                             mtu  = 1500;
                             ipv4 = "${configuration.external.guest_ip}/${toString configuration.external.prefix}";}];
        network.defaultGateway = configuration.external.host_ip;
      } // (if configuration ? home then {
        systemd_units.systemd_services = builtins.listToAttrs [{
          name = tsp_router.name;
          value = {
            description = tsp_router.name;
            serviceConfig = {
              Type = "simple";
              ExecStart = "${wrapped}/sbin/router-start";
              Restart = "always";
            };
          };
        }];
      } else {});
      module =
        pkg: { config, pkgs, ... }:
        {
          config = pkgs.lib.mkIf configuration.systemd_host.enabled {
            boot.kernel.sysctl."net.ipv4.ip_forward" = 1;
            networking.bridges = builtins.listToAttrs [
                { name = configuration.sdn.bridge; value = { interfaces = []; }; }
                { name = configuration.external.bridge; value = { interfaces = []; }; }
              ];
            networking.interfaces = builtins.listToAttrs [
                { name = configuration.sdn.bridge; value = {
                    ipAddress = configuration.sdn.host_ip; prefixLength = configuration.sdn.prefix; }; }
                { name = configuration.external.bridge; value = {
                    ipAddress = configuration.external.host_ip; prefixLength = configuration.external.prefix; }; }
              ];
            networking.nat.enable = true;
            networking.nat.externalInterface = configuration.external.interface;
            networking.nat.internalIPs = [ "${configuration.external.network}/${toString configuration.external.prefix}" ];

            systemd.services.tsp-router-network = {
              description = "Firewall NAT for TSP Router";
              before = ["${pkg.name}.service"];
              requires = ["${pkg.name}.service" "network.target"];
              wantedBy = ["${pkg.name}.service"];
              after = ["network.target"];
              serviceConfig = {
                Type = "oneshot";
                RemainAfterExit = true;
              };
              script = ''
                ${iptables}/sbin/iptables -t nat -D PREROUTING -p tcp --dport 33441 \
                  -i "${configuration.external.interface}" -j DNAT \
                  --to-destination "${configuration.external.guest_ip}" || true
                ${iptables}/sbin/iptables -t nat -D PREROUTING -p udp --dport 33441 \
                  -i "${configuration.external.interface}" -j DNAT \
                  --to-destination "${configuration.external.guest_ip}" || true

                ${iptables}/sbin/iptables -t nat -I PREROUTING -p tcp --dport 33441 \
                  -i "${configuration.external.interface}" -j DNAT \
                  --to-destination "${configuration.external.guest_ip}"
                ${iptables}/sbin/iptables -t nat -I PREROUTING -p udp --dport 33441 \
                  -i "${configuration.external.interface}" -j DNAT \
                  --to-destination "${configuration.external.guest_ip}"

                ${iptables}/sbin/iptables -t nat -D POSTROUTING -o "${configuration.external.interface}" \
                  -s "${configuration.sdn.network}/${toString configuration.sdn.prefix}" -j MASQUERADE || true
                ${iptables}/sbin/iptables -t nat -D POSTROUTING -o "${configuration.sdn.bridge}" \
                  ! -s "${configuration.sdn.network}/${toString configuration.sdn.prefix}" \
                  -d "${configuration.sdn.network}/${toString configuration.sdn.prefix}" \
                  -j MASQUERADE || true

                ${iptables}/sbin/iptables -t nat -I POSTROUTING -o "${configuration.external.interface}" \
                  -s "${configuration.sdn.network}/${toString configuration.sdn.prefix}" -j MASQUERADE
                ${iptables}/sbin/iptables -t nat -I POSTROUTING -o "${configuration.sdn.bridge}" \
                  ! -s "${configuration.sdn.network}/${toString configuration.sdn.prefix}" \
                  -d "${configuration.sdn.network}/${toString configuration.sdn.prefix}" \
                  -j MASQUERADE
              '';
            };
          };
        };
    })
