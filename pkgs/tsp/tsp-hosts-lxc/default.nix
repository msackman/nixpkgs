{ stdenv, tsp, coreutils, lib }:

tsp.container ({ configuration, lxcLib }:
  let
    name = "tsp-hosts";
    createIn = ./on-create.sh.in;
    steriliseIn = ./on-sterilise.sh.in;
    create = stdenv.mkDerivation {
      name = "${name}-oncreate";
      buildCommand = ''
        sed -e "s|@coreutils@|${coreutils}|g" \
            -e "s|@hosts@|${hosts}|g" \
            ${createIn} > $out
        chmod +x $out
      '';
    };
    sterilise = stdenv.mkDerivation {
      name = "${name}-onsterilise";
      buildCommand = ''
        sed -e "s|@coreutils@|${coreutils}|g" \
            ${steriliseIn} > $out
        chmod +x $out
      '';
    };
    hosts = stdenv.mkDerivation {
      name = "${name}-hosts";
      buildCommand = lib.concatStringsSep "\n"
        (map (entry: "printf '%s %s\n' \"${entry.ip}\" \"${entry.host}\" >> $out")
         configuration.hosts);
    };
  in
    {
      name = "${name}-lxc";
      storeMounts = { inherit hosts; };
      onCreate = [ create ];
      onSterilise = [ sterilise ];
      options = { hosts = lxcLib.mkOption { optional = false; }; };
    })
