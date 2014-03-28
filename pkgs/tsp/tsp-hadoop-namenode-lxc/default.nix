{ stdenv, tsp, coreutils, lib, callPackage, hadoop }:

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
        ${coreutils}/bin/mkdir -p "$HADOOP_PID_DIR"
        ${hadoop}/bin/hdfs --config ${confDir}/ namenode -format -nonInteractive
        exec ${hadoop}/bin/hdfs --config ${confDir}/ namenode' > $out/sbin/hadoop-namenode-start
        chmod +x $out/sbin/hadoop-namenode-start
      '';
    };
    confDir = configuration.hadoop.config;
    hasConfDir = configuration ? hadoop && configuration.hadoop ? config;
  in
    {
      name = "${hadoop.name}-namenode-lxc";
      storeMounts = {
        network = tsp_network;
        systemd_guest = tsp_systemd_guest;
        hadoop = tsp_hadoop;
        systemd_units = tsp_systemd_units;
      };
      configuration = if hasConfDir then {
        systemd_units.systemd_services = builtins.listToAttrs [{
          name = hadoop.name;
          value = {
            description = hadoop.name;
            environment = {
              HADOOP_LOG_DIR = configuration.hadoopLogDir;
              YARN_LOG_DIR   = configuration.yarnLogDir;
              HADOOP_PID_DIR = configuration.pidDir;
            };
            path = [ coreutils ];
            serviceConfig = {
              Type = "forking";
              ExecStart = "${wrapped}/sbin/hadoop-namenode-start";
              PIDFile = "${configuration.pidDir}/hadoop-root-namenode.pid";
              Restart = "always";
            };
          };
        }];
      } else {};
      options = {
        hadoopLogDir = containerLib.mkOption { optional = true; default = "/var/log/hadoop"; };
        yarnLogDir = containerLib.mkOption { optional = true; default = "/var/log/yarn"; };
        pidDir = containerLib.mkOption { optional = true; default = "/run/hadoop"; };
      };
    })