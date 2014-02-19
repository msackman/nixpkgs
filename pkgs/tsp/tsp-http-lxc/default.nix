{ stdenv, tsp_http, erlang, buildLXC, bash, coreutils, lib }:

buildLXC ({ configuration, lxcLib }:
  let
    tsp_bash = (import ../tsp-bash) { inherit stdenv buildLXC bash coreutils; };
    tsp_dev_proc_sys = (import ../tsp-dev-proc-sys) { inherit stdenv buildLXC coreutils; };
    tsp_home = (import ../tsp-home) { inherit stdenv buildLXC coreutils bash; };
    tsp_network = (import ../tsp-network) { inherit buildLXC lib; };
    wrapped = stdenv.mkDerivation rec {
      name = "${tsp_http.name}-lxc-wrapper";
      buildCommand = ''
        mkdir -p $out/sbin
        printf '#! ${stdenv.shell}
        export HOME=/home/${configuration."home.user"}
        ${erlang}/bin/erl -pa ${tsp_http}/deps/*/ebin ${tsp_http}/ebin -tsp_http router_node router@${configuration."http.router.hostname"} -sname http ${if configuration ? "http.erlang.cookie" then "-setcookie ${configuration."http.erlang.cookie"}" else ""} -s tsp_http' > $out/sbin/http-start
        chmod +x $out/sbin/http-start
      '';
    };
  in
    {
      name = "${tsp_http.name}-lxc";
      storeMounts = [ tsp_bash tsp_http tsp_dev_proc_sys tsp_home tsp_network wrapped ];
      lxcConf = lxcLib.sequence [
        (if configuration."http.start" then
           lxcLib.setInit "${wrapped}/sbin/http-start"
         else
           lxcLib.id)
      ];
      options = [
        (lxcLib.declareOption {
          name = "http.start";
          optional = true;
          default = false;
         })
        (lxcLib.declareOption {
          name = "http.router.hostname";
          optional = false;
         })
        (lxcLib.declareOption {
          name = "http.erlang.cookie";
          optional = true;
         })];
      configuration = {
        "home.user"  = "http";
        "home.uid"   = 1000;
        "home.group" = "http";
        "home.gid"   = 1000;
      };
    })
