{ stdenv, tsp_http, erlang, tsp, coreutils, graphviz, callPackage }:

tsp.container ({ global, configuration, containerLib }:
  let
    tsp_bash = callPackage ../tsp-bash-lxc { };
    tsp_home = callPackage ../tsp-home-lxc { };
    tsp_network = callPackage ../tsp-network-lxc { };
    wrapped = stdenv.mkDerivation rec {
      name = "${tsp_http.name}-lxc-wrapper";
      buildCommand = ''
        mkdir -p $out/sbin
        printf '#! ${stdenv.shell}
        export HOME=/home/${configuration.home.user}
        export PATH=${graphviz}/bin:${coreutils}/bin:$PATH
        export LOG_DIR=/var/log/${wrapped.name}
        mkdir -p $LOG_DIR
        exec ${erlang}/bin/erl -pa ${tsp_http}/deps/*/ebin ${tsp_http}/ebin -tsp_http router_node router@${configuration.router.hostname} -tsp_http docroot \\"${tsp_http}/priv/www\\" -sname http ${if containerLib.hasConfigurationPath configuration ["erlang" "cookie"] then "-setcookie ${configuration.erlang.cookie}" else ""} -s tsp_http -noinput > $LOG_DIR/stdout 2> $LOG_DIR/stderr 0<&-' > $out/sbin/http-start
        chmod +x $out/sbin/http-start
      '';
    };
    doStart = configuration.start;
  in
    {
      name = "${tsp_http.name}-lxc";
      storeMounts = { bash         = tsp_bash;
                      home         = tsp_home;
                      network      = tsp_network;
                      inherit (tsp) systemd_host;
                      inherit wrapped;
                    } // (if doStart then { inherit (tsp) init; } else {});
      options = {
        start           = containerLib.mkOption { optional = true; default = false; };
        router.hostname = containerLib.mkOption { optional = false; };
        erlang.cookie   = containerLib.mkOption { optional = true; };
      };
      configuration = {
        home.user  = "http";
        home.uid   = 1000;
        home.group = "http";
        home.gid   = 1000;
      } // (if doStart then { init.init = "${wrapped}/sbin/http-start"; } else {});
    })
