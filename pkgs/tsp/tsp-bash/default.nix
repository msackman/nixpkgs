{ stdenv, buildLXC, bash, coreutils }:

buildLXC ({ configuration, lxcLib }:
  let
    createIn = ./on-create.sh.in;
    create = stdenv.mkDerivation rec {
      name = "${bash.name}-oncreate";
      buildCommand = ''
        sed -e "s|@bash@|${bash}|g" \
            -e "s|@coreutils@|${coreutils}|g" \
            ${createIn} > $out
        chmod +x $out
      '';
    };
  in
    {
      name = "${bash.name}-lxc";
      storeMounts = { inherit bash; };
      lxcConf =
        if configuration."bash.start" then
          lxcLib.setInit "${bash}/bin/bash"
        else
          lxcLib.id;
       onCreate = [ create ];
       options = {
         start = lxcLib.mkOption { optional = true; default = false; };
       };
    })
