{ stdenv, tsp_erlinetrc, erlang, tsp, coreutils, callPackage }:

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
      name = "${tsp_erlinetrc.name}-lxc-wrapper";
      buildCommand = ''
        mkdir -p $out/sbin
        printf '#! ${stdenv.shell}
        export HOME=/home/${configuration.home.user}
        export LOG_DIR=/var/log/${wrapped.name}
        ${coreutils}/bin/mkdir -p $LOG_DIR
        exec ${erlang}/bin/erl -pa ${tsp_erlinetrc}/deps/*/ebin ${tsp_erlinetrc}/ebin -tsp_erlinetrc router_node router@${configuration.router.hostname} -tsp_erlinetrc name \\"${configuration.name}\\" -tsp_erlinetrc output_path \\"${configuration.output_path}\\" -sname erlinetrc ${cookieStr} -sasl sasl_error_logger \\{file,\\"$LOG_DIR/sasl\\"\\} -sasl errlog_type error -s tsp_erlinetrc -noinput' > $out/sbin/erlinetrc-start
        chmod +x $out/sbin/erlinetrc-start
      '';
    };
  in
    {
      name = "${tsp_erlinetrc.name}-lxc";
      storeMounts = { bash          = tsp_bash;
                      home          = tsp_home;
                      network       = tsp_network;
                      systemd_guest = tsp_systemd_guest;
                      systemd_units = tsp_systemd_units;
                      inherit (tsp) systemd_host;
                      inherit wrapped;
                    };
      options = {
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
        systemd_units.systemd_units = [{
          description = "${tsp_erlinetrc.name}";
          wantedBy = [ "multi-user.target" ];
          serviceConfig = {
            Type = "simple";
            ExecStart = "${wrapped}/sbin/erlinetrc-start";
          };
        }];
      };
    })
