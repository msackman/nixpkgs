{ stdenv, tsp_router, erlang, bridge_utils, nettools, tsp, coreutils, iptables, lib, callPackage }:

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
            {bridge,    "${configuration.internal_bridge.name}"}
           ]}
        ].
        ' > $out/config.config
      '';
    };
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
        export PATH=${bridge_utils}/bin:${bridge_utils}/sbin:${nettools}/bin:${nettools}/sbin:${coreutils}/bin:$PATH
        brctl addbr ${configuration.internal_bridge.name}
        brctl addif ${configuration.internal_bridge.name} ${configuration.internal_bridge.nic}
        ifconfig ${configuration.internal_bridge.name} ${configuration.internal_bridge.ip} netmask ${configuration.internal_bridge.netmask} up
        export LOG_DIR=/var/log/${logDirName}
        mkdir -p $LOG_DIR # still need this for lager and sasl logs
        exec ${erlang}/bin/erl -pa ${tsp_router}/deps/*/ebin ${tsp_router}/ebin -sname router ${cookieStr} -config ${configFile}/config -s tsp -noinput' > $out/sbin/router-start
        chmod +x $out/sbin/router-start  # */ <- hack for emacs mode
      '';
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
        identity        = containerLib.mkOption { optional = false; };
        internal_bridge = {
          name           = containerLib.mkOption { optional = true; default = "br0"; };
          ip             = containerLib.mkOption { optional = false; };
          netmask        = containerLib.mkOption { optional = false; };
          nic            = containerLib.mkOption { optional = false; };
        };
        erlang.cookie   = containerLib.mkOption { optional = true; };
        serfdom         = containerLib.mkOption { optional = false; };
        external_ipv4   = containerLib.mkOption { optional = false; };
      };
      configuration = {
        home.user  = "router";
        home.uid   = 1000;
        home.group = "router";
        home.gid   = 1000;
      } // (if configuration ? home then {
        systemd_units.systemd_services = {
          router = {
            description = "${tsp_router.name}";
            serviceConfig = {
              Type = "simple";
              ExecStart = "${wrapped}/sbin/router-start";
              Restart = "always";
            };
          };
        };
      } else {});
      module =
        pkg: { config, pkgs, ... }:
        let externalNic = config.networking.nat.externalInterface; in
        {
          config = pkgs.lib.mkIf configuration.systemd_host.enabled {
            assertions = [{ assertion = builtins.isString config.networking.nat.externalInterface &&
                                        config.networking.nat.externalInterface != "";
                            message = "Must define config.networking.nat.externalInterface"; }];

            systemd.services.tsp_router_firewall_nat = {
              description = "Firewall NAT for TSP Router";
              before = ["${pkg.name}.service"];
              requires = ["${pkg.name}.service"];
              wantedBy = ["${pkg.name}.service"];
              serviceConfig = {
                Type = "oneshot";
                RemainAfterExit = true;
              };
              script = ''
                ${iptables}/sbin/iptables -t nat -D PREROUTING -p tcp --dport 33441 \
                  -i "${externalNic}" -j DNAT \
                  --to-destination "${configuration.external_ipv4}" || true
                ${iptables}/sbin/iptables -t nat -D PREROUTING -p udp --dport 33441 \
                  -i "${externalNic}" -j DNAT \
                  --to-destination "${configuration.external_ipv4}" || true
                ${iptables}/sbin/iptables -t nat -I PREROUTING -p tcp --dport 33441 \
                  -i "${externalNic}" -j DNAT \
                  --to-destination "${configuration.external_ipv4}"
                ${iptables}/sbin/iptables -t nat -I PREROUTING -p udp --dport 33441 \
                  -i "${externalNic}" -j DNAT \
                  --to-destination "${configuration.external_ipv4}"
              '';
            };
          };
        };
    })
