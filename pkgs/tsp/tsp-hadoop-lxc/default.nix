{ stdenv, tsp, coreutils, lib, callPackage, hadoop, writeTextFile }:

tsp.container ({ global, configuration, containerLib }:
  let
    tsp_bash = callPackage ../tsp-bash-lxc { };
    tsp_home = callPackage ../tsp-home-lxc { };
    logDirName = hadoop.name;
    createIn = ./on-create.sh.in;
    steriliseIn = ./on-sterilise.sh.in;
    create = stdenv.mkDerivation {
      name = "${hadoop.name}-oncreate";
      buildCommand = ''
        sed -e "s|@coreutils@|${coreutils}|g" \
            -e "s|@config@|${config}|g" \
            -e "s|@dirs@|${configuration.hadoopLogDir} ${configuration.yarnLogDir} ${configuration.pidDir}|g" \
            ${createIn} > $out
        chmod +x $out
      '';
    };
    sterilise = stdenv.mkDerivation {
      name = "${hadoop.name}-onsterilise";
      buildCommand = ''
        sed -e "s|@coreutils@|${coreutils}|g" \
            ${steriliseIn} > $out
        chmod +x $out
      '';
    };
    configIn = "${hadoop}/etc/hadoop";
    config = stdenv.mkDerivation {
      name = "${hadoop.name}-config";
      buildInputs = [ coreutils ];
      buildCommand = (''
        mkdir -p $out
        for p in $(echo ${configIn}/*); do
          ln -s $p $out/$(basename $p)
        done
      '' # */ <- hack for emacs mode
        + (lib.concatStrings (map (name:
             let
               value = builtins.getAttr name configuration;
               file = builtins.getAttr name siteConfigFiles;
             in
               if value == null then
                 ""
               else if builtins.isString value then
                 "\nrm $out/${file}\nln -s ${writeTextFile { inherit name; text = value; }} $out/${file}"
               else
                 "\nrm $out/${file}\nln -s ${value} $out/${file}"
           ) (builtins.attrNames siteConfigFiles))));
    };

    siteConfigFiles = {
      coreSite   = "core-site.xml";
      hdfsSite   = "hdfs-site.xml";
      httpfsSite = "httpfs-site.xml";
      mapredSite = "mapred-site.xml";
      yarnSite   = "yarn-site.xml";
      slaves     = "slaves";
    };
  in
    {
      name = "${hadoop.name}-lxc";
      storeMounts = {
        home = tsp_home;
        inherit coreutils tsp_bash;
      };
      onCreate = [ create ];
      onSterilise = [ sterilise ];
      containerConf = containerLib.setValue ["memory"]
                        { name = "memory"; unit = "MiB"; value = "1024"; }
                        # In theory I should ensure the new setting is
                        # max old.value and new.value but that would
                        # involve interpreting units and I CBA right
                        # now.
                        (_old: { name = "memory"; unit = "MiB"; value = "1024"; });
      configuration = {
        home.user  = "hadoop";
        home.uid   = 1000;
        home.group = "hadoop";
        home.gid   = 1000;
        config = "${config}";
      };
      options = {
        config = containerLib.mkOption { optional = false; };
        hadoopLogDir = containerLib.mkOption { optional = true; default = "/var/log/hadoop"; };
        yarnLogDir = containerLib.mkOption { optional = true; default = "/var/log/yarn"; };
        pidDir = containerLib.mkOption { optional = true; default = "/run/hadoop"; };
      } //
        builtins.listToAttrs (map (
          name: {inherit name; value = containerLib.mkOption { optional = true; default = null; };}
        ) (builtins.attrNames siteConfigFiles));
    })
