{ stdenv, buildLXC, bash, coreutils }:

buildLXC ({ configuration, lxcLib }:
  let
    createIn = ./on-create.sh.in;
    create = stdenv.mkDerivation rec {
      name = "${bash.name}-oncreate";
      buildCommand = ''
        mkdir -p $out/bin
        sed -e "s|@bash@|${bash}|g" \
            -e "s|@coreutils@|${coreutils}|g" \
            ${createIn} > $out/bin/on-create.sh
      '';
    };
  in
    {
      name = "${bash.name}-lxc";
      storeMounts = [ bash ];
      lxcConf =
        if configuration."bash.start" then
          lxcLib.setInit "${bash}/bin/bash"
        else
          lxcLib.id;
       onCreate = [ "${create}/bin/on-create.sh" ];
       options = [
         (lxcLib.declareOption {
           name = "bash.start";
           optional = true;
           default = false;
          })];
    })
