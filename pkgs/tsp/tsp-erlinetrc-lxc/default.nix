{ stdenv, tsp_erlinetrc, erlang, buildLXC, bash, coreutils, lib }:

buildLXC ({ configuration, lxcLib }:
  let
    tsp_bash = (import ../tsp-bash) { inherit stdenv buildLXC bash coreutils; };
    tsp_dev_proc_sys = (import ../tsp-dev-proc-sys) { inherit stdenv buildLXC coreutils; };
    tsp_home = (import ../tsp-home) { inherit stdenv buildLXC coreutils bash; };
    tsp_network = (import ../tsp-network) { inherit buildLXC lib; };
    wrapped = stdenv.mkDerivation rec {
      name = "${tsp_erlinetrc.name}-lxc-wrapper";
      buildCommand = ''
        mkdir -p $out/sbin
        printf '#! ${stdenv.shell}
        export HOME=/home/${configuration."home.user"}
        export LOG_DIR=/var/log/${wrapped.name}
        ${coreutils}/bin/mkdir -p $LOG_DIR
        exec ${erlang}/bin/erl -pa ${tsp_erlinetrc}/deps/*/ebin ${tsp_erlinetrc}/ebin -tsp_erlinetrc router_node router@${configuration."erlinetrc.router.hostname"} -tsp_erlinetrc name \\"${configuration."erlinetrc.name"}\\" -tsp_erlinetrc output_path \\"${configuration."erlinetrc.output_path"}\\" -sname erlinetrc ${if configuration ? "erlinetrc.erlang.cookie" then "-setcookie ${configuration."erlinetrc.erlang.cookie"}" else ""} -sasl sasl_error_logger \\{file,\\"$LOG_DIR/sasl\\"\\} -sasl errlog_type error -s tsp_erlinetrc -noinput > $LOG_DIR/stdout 2> $LOG_DIR/stderr 0<&-' > $out/sbin/erlinetrc-start
        chmod +x $out/sbin/erlinetrc-start
      '';
    };
  in
    {
      name = "${tsp_erlinetrc.name}-lxc";
      storeMounts = { bash         = tsp_bash;
                      dev_proc_sys = tsp_dev_proc_sys;
                      home         = tsp_home;
                      network      = tsp_network;
                      inherit wrapped; };
      lxcConf = lxcLib.sequence [
        (if configuration."erlinetrc.start" then
           lxcLib.setInit "${wrapped}/sbin/erlinetrc-start"
         else
           lxcLib.id)
      ];
      options = {
        start           = lxcLib.mkOption { optional = true; default = false; };
        name            = lxcLib.mkOption { optional = false; };
        router.hostname = lxcLib.mkOption { optional = false; };
        output_path     = lxcLib.mkOption { optional = false; };
        erlang.cookie   = lxcLib.mkOption { optional = true; };
        network         = lxcLib.includeOptions tsp_network;
        home            = lxcLib.includeOptions tsp_home;
        dev_proc_sys    = lxcLib.includeOptions tsp_dev_proc_sys;
        bash            = lxcLib.includeOptions tsp_bash;
      };
      configuration = {
        home.user  = "erlinetrc";
        home.uid   = 1000;
        home.group = "erlinetrc";
        home.gid   = 1000;
      };
    })
