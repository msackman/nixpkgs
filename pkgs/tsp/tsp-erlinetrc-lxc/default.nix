{ stdenv, tsp_erlinetrc, erlang, tsp, coreutils, callPackage }:

tsp.container ({ global, configuration, containerLib }:
  let
    tsp_bash = callPackage ../tsp-bash-lxc { };
    tsp_home = callPackage ../tsp-home-lxc { };
    tsp_network = callPackage ../tsp-network-lxc { };
    wrapped = stdenv.mkDerivation rec {
      name = "${tsp_erlinetrc.name}-lxc-wrapper";
      buildCommand = ''
        mkdir -p $out/sbin
        printf '#! ${stdenv.shell}
        export HOME=/home/${configuration.home.user}
        export LOG_DIR=/var/log/${wrapped.name}
        ${coreutils}/bin/mkdir -p $LOG_DIR
        exec ${erlang}/bin/erl -pa ${tsp_erlinetrc}/deps/*/ebin ${tsp_erlinetrc}/ebin -tsp_erlinetrc router_node router@${configuration.router.hostname} -tsp_erlinetrc name \\"${configuration.name}\\" -tsp_erlinetrc output_path \\"${configuration.output_path}\\" -sname erlinetrc ${if containerLib.hasConfigurationPath configuration ["erlang" "cookie"] then "-setcookie ${configuration.erlang.cookie}" else ""} -sasl sasl_error_logger \\{file,\\"$LOG_DIR/sasl\\"\\} -sasl errlog_type error -s tsp_erlinetrc -noinput > $LOG_DIR/stdout 2> $LOG_DIR/stderr 0<&-' > $out/sbin/erlinetrc-start
        chmod +x $out/sbin/erlinetrc-start
      '';
    };
    doStart = configuration.start;
  in
    {
      name = "${tsp_erlinetrc.name}-lxc";
      storeMounts = { bash         = tsp_bash;
                      home         = tsp_home;
                      network      = tsp_network;
                      inherit (tsp) systemd;
                      inherit wrapped;
                    } // (if doStart then { inherit (tsp) init; } else {});
      options = {
        start           = containerLib.mkOption { optional = true; default = false; };
        name            = containerLib.mkOption { optional = false; };
        router.hostname = containerLib.mkOption { optional = false; };
        output_path     = containerLib.mkOption { optional = false; };
        erlang.cookie   = containerLib.mkOption { optional = true; };
      };
      configuration = {
        home.user  = "erlinetrc";
        home.uid   = 1000;
        home.group = "erlinetrc";
        home.gid   = 1000;
      } // (if doStart then { init.init  = "${wrapped}/sbin/erlinetrc-start"; } else {});
    })
