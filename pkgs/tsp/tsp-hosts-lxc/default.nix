{ stdenv, tsp, coreutils, lib }:

tsp.container ({ global, configuration, containerLib }:
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
      options = {
        hosts = containerLib.mkOption {
                  optional = false;
                  validator =
                    lib.fold ({ip, host}: acc:
                      assert builtins.isString ip;
                      assert builtins.isString host;
                      let components = lib.splitString "." ip; in
                      assert builtins.length components == 4;
                      acc) true;
                };
      };
    })
