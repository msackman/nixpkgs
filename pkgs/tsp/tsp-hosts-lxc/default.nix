{ stdenv, buildLXC, coreutils, lib }:

buildLXC ({ configuration, lxcLib }:
  let
    createIn = ./on-create.sh.in;
    create = stdenv.mkDerivation rec {
      name = "tsp-hosts-oncreate";
      buildCommand = ''
        sed -e "s|@coreutils@|${coreutils}|g" \
            -e "s|@hosts@|${hosts}|g" \
            ${createIn} > $out
        chmod +x $out
      '';
    };
    hosts = stdenv.mkDerivation rec {
      name = "tsp-hosts-hosts";
      buildCommand = lib.concatStringsSep "\n"
        (map (entry: "printf '%s %s\n' \"${entry.ip}\" \"${entry.host}\" >> $out")
         configuration.hosts);
    };
  in
    {
      name = "tsp-hosts-lxc";
      storeMounts = { inherit hosts; };
      onCreate = [ create ];
      options = { hosts = lxcLib.mkOption { optional = false; }; };
    })
