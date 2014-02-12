{ stdenv, serfdom, buildLXC, bash, coreutils, gnused }:

let
  user = "serfdom";
  uid = 1000;
  group = "serfdom";
  gid = 1000;
  tsp_bash = (import ../tsp-bash) { inherit stdenv buildLXC bash coreutils; };
  tsp_dev_proc_sys = (import ../tsp-dev-proc-sys) { inherit stdenv buildLXC coreutils; };
  tsp_home = (import ../tsp-home) { inherit stdenv buildLXC coreutils bash tsp_bash; };
  tsp_network = (import ../tsp-network) { inherit buildLXC; };
  init = {ip, publicIP, hostname}: builtins.toFile "init" ''
    #! @shell@
    @serfdom@/bin/serf agent -rpc-addr=${ip}:7373 -tag router=${publicIP} -tag x=y -node=${hostname}
  '';
  wrapped = options: stdenv.mkDerivation rec {
    name = "${serfdom.name}-wrapped";
    buildCommand = ''
      mkdir -p $out/sbin
      sed -e "s|@shell@|${stdenv.shell}|g" \
          -e "s|@serfdom@|${serfdom}|g" \
          ${init {inherit ip publicIP hostname;}} > $out/sbin/serf.init
      chmod +x $out/sbin/serf.init
    '';
  };
in
  {ip, gw ? "", hostname, publicIP} :
  let
    realised = wrapped {inherit publicIP ip hostname;};
  in buildLXC {
    name = "serfdom-lxc";
    pkgs = [ realised bash ];
    lxcConf = ''lxcConfLib: dir:
      {lxcPkgs = [ "${tsp_bash}" "${tsp_dev_proc_sys}" "${tsp_home user uid group gid}"
                   "${tsp_network {inherit gw ip hostname;}}" ];
       conf = options:
         if options."serfdom.start" then
           lxcConfLib.setInit "${wrapped options}/bin/serf"
         else
           lxcConfLib.id;
       options = [
         (lxcConfLib.declareOption {
           name = "serfdom.start";
           optional = true;
           default = false;
         })
         (lxcConfLib.declareOption {
           name = "serfdom.publicIP";
           optional = false;
         })
       ];
       configuration = {
         "home.user"  = "serfdom";
         "home.uid"   = 1000;
         "home.group" = "serfdom";
         "home.gid"   = 1000;
       };
      }
      '';
  }
