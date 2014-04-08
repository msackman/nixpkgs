{ stdenv, tsp_http, erlang, tsp, coreutils, graphviz, callPackage }:

tsp.container ({ global, configuration, containerLib }:
  let
    tsp_bash = callPackage ../tsp-bash-lxc { };
    tsp_home = callPackage ../tsp-home-lxc { };
    tsp_network = callPackage ../tsp-network-lxc { };
    tsp_systemd_guest = callPackage ../tsp-systemd-guest-lxc { };
    tsp_systemd_units = callPackage ../tsp-systemd-units-lxc { };
    cookieStr = if containerLib.hasConfigurationPath configuration ["erlang" "cookie"] then
                  "-setcookie ${configuration.erlang.cookie}"
                else
                  "";
    wrapped = stdenv.mkDerivation rec {
      name = "${tsp_http.name}-lxc-wrapper";
      buildCommand = ''
        mkdir -p $out/sbin
        printf '#! ${stdenv.shell}
        export HOME=/home/${configuration.home.user}
        export PATH=${graphviz}/bin:${coreutils}/bin:$PATH
        exec ${erlang}/bin/erl -pa ${tsp_http}/deps/*/ebin ${tsp_http}/ebin -tsp_http router_node router@${configuration.router.hostname} -tsp_http docroot \\"${tsp_http}/priv/www\\" -sname http ${cookieStr} -s tsp_http -noinput' > $out/sbin/http-start
        chmod +x $out/sbin/http-start
      ''; # */ <- hack for emacs mode
    };
  in
    {
      name = "${tsp_http.name}-lxc";
      imports = {
        bash          = tsp_bash;
        home          = tsp_home;
        network       = tsp_network;
        systemd_guest = tsp_systemd_guest;
        systemd_units = tsp_systemd_units;
        inherit (tsp) systemd_host;
      };
      options = {
        router.hostname = containerLib.mkOption { optional = false; };
        erlang.cookie   = containerLib.mkOption { optional = true; };
      };
      configuration = {
        home.user  = "http";
        home.uid   = 1000;
        home.group = "http";
        home.gid   = 1000;
      } // (if configuration ? home then {
        systemd_units.systemd_services = builtins.listToAttrs [{
          name = tsp_http.name;
          value = {
            description = tsp_http.name;
            serviceConfig = {
              Type = "simple";
              ExecStart = "${wrapped}/sbin/http-start";
            };
          };
        }];
      } else {});
    })
