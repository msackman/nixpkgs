{ stdenv, tsp, coreutils, lib, procps, callPackage, hadoop }:

tsp.container ({ global, configuration, containerLib }:
  let
    tsp_hadoop = callPackage ../tsp-hadoop-lxc { };
    tsp_network = callPackage ../tsp-network-lxc { };
    tsp_systemd_guest = callPackage ../tsp-systemd-guest-lxc { };
    tsp_systemd_units = callPackage ../tsp-systemd-units-lxc { };
    wrapped = stdenv.mkDerivation {
      name = "${hadoop.name}-namenode-wrapper";
      # Thankfully, -format with -nonInteractive makes format
      # idempotent: it detects the existing format if it exists and
      # does not continue.
      buildCommand = ''
        mkdir -p $out/sbin
        printf '#! ${stdenv.shell}
        ${hadoop}/bin/hdfs --config ${confDir} namenode -format -nonInteractive
        exec ${hadoop}/sbin/hadoop-daemon.sh --config ${confDir} --script hdfs start namenode
        ' > $out/sbin/hadoop-namenode-start
        chmod +x $out/sbin/hadoop-namenode-start
      '';
    };
    confDir = configuration.hadoop.config;
    hadoopConfigured = configuration ? hadoop &&
                       configuration.hadoop ? config &&
                       configuration.hadoop ? hadoopLogDir;
  in
    {
      name = "${hadoop.name}-namenode-lxc";
      imports = {
        network       = tsp_network;
        systemd_guest = tsp_systemd_guest;
        hadoop        = tsp_hadoop;
        systemd_units = tsp_systemd_units;
        inherit (tsp) systemd_host;
      };
      configuration = if hadoopConfigured then {
        systemd_units.systemd_services = builtins.listToAttrs [{
          name = hadoop.name;
          value = {
            description = hadoop.name;
            environment = {
              HADOOP_LOG_DIR  = configuration.hadoop.hadoopLogDir;
              YARN_LOG_DIR    = configuration.hadoop.yarnLogDir;
              HADOOP_CONF_DIR = configuration.hadoop.config;
              HADOOP_PID_DIR  = configuration.hadoop.pidDir;
            };
            path = [ coreutils procps ];
            serviceConfig = {
              Type = "forking";
              ExecStart = "${wrapped}/sbin/hadoop-namenode-start";
              PIDFile = "${configuration.hadoop.pidDir}/hadoop--namenode.pid";
              Restart = "always";
            };
          };
        }];
      } else {};
    })