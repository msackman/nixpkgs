{ stdenv, tsp, coreutils, lib, procps, callPackage, hadoop }:

tsp.container ({ global, configuration, containerLib }:
  let
    tsp_hadoop = callPackage ../tsp-hadoop-lxc { };
    tsp_network = callPackage ../tsp-network-lxc { };
    tsp_systemd_guest = callPackage ../tsp-systemd-guest-lxc { };
    tsp_systemd_units = callPackage ../tsp-systemd-units-lxc { };
    wrapped = stdenv.mkDerivation {
      name = "${hadoop.name}-datanode-wrapper";
      buildCommand = ''
        mkdir -p $out/sbin
        printf '#! ${stdenv.shell}
        exec ${hadoop}/sbin/hadoop-daemon.sh --config ${confDir} --script hdfs start datanode
        ' > $out/sbin/hadoop-datanode-start
        chmod +x $out/sbin/hadoop-datanode-start
      '';
    };
    confDir = configuration.hadoop.config;
    hadoopConfigured = configuration ? hadoop &&
                       configuration.hadoop ? config &&
                       configuration.hadoop ? hadoopLogDir;
  in
    {
      name = "${hadoop.name}-datanode-lxc";
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
              ExecStart = "${wrapped}/sbin/hadoop-datanode-start";
              PIDFile = "${configuration.hadoop.pidDir}/hadoop--datanode.pid";
              Restart = "always";
            };
          };
        }];
      } else {};
    })