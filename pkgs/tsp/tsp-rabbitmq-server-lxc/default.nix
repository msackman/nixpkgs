{ stdenv, makeWrapper, tsp_rabbitmq_server, tsp, callPackage }:

tsp.container ({ global, configuration, containerLib }:
  let
    tsp_bash = callPackage ../tsp-bash-lxc { };
    tsp_home = callPackage ../tsp-home-lxc { };
    tsp_network = callPackage ../tsp-network-lxc { };
    wrapped = stdenv.mkDerivation rec {
      name = "${tsp_rabbitmq_server.name}-lxc-wrapper";
      buildInputs = [ makeWrapper ];
      buildCommand = ''
        mkdir -p $out/sbin
        for f in rabbitmq-server rabbitmqctl rabbitmq-plugins; do
          makeWrapper ${tsp_rabbitmq_server}/sbin/$f $out/sbin/$f \
            --set HOME /home/${configuration.home.user} \
            --set ERL_INETRC /home/${configuration.home.user}/.rabbitmq/3.2.2/etc/rabbitmq/erl_inetrc
        done
      '';
    };
  in
    {
      name = "rabbitmq-server-lxc";
      imports = {
        bash    = tsp_bash;
        network = tsp_network;
        home    = tsp_home;
      };
      storeMounts = [ wrapped ];
      configuration = {
        home.user  = "rabbit";
        home.uid   = 1000;
        home.group = "rabbit";
        home.gid   = 1000;
      };
    })
