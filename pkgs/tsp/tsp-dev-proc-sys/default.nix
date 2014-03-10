{ stdenv, tsp, coreutils }:

tsp.container ({ configuration, lxcLib }:
  let
    name = "tsp-dev-proc-sys";
    boolToStr = b: if b then "true" else "false";
    createIn = ./on-create.sh.in;
    steriliseIn = ./on-sterilise.sh.in;
    create = stdenv.mkDerivation {
      name = "${name}-oncreate";
      buildCommand = ''
        sed -e "s|@coreutils@|${coreutils}|g" \
            -e "s|@dev@|${boolToStr (! configuration.dev.skip)}|g" \
            -e "s|@proc@|${boolToStr (! configuration.proc.skip)}|g" \
            -e "s|@sysfs@|${boolToStr (! configuration.sysfs.skip)}|g" \
            ${createIn} > $out
        chmod +x $out
      '';
    };
    sterilise = stdenv.mkDerivation {
      name = "${name}-onsterilise";
      buildCommand = ''
        sed -e "s|@coreutils@|${coreutils}|g" \
            -e "s|@dev@|${boolToStr (! configuration.dev.skip)}|g" \
            -e "s|@proc@|${boolToStr (! configuration.proc.skip)}|g" \
            -e "s|@sysfs@|${boolToStr (! configuration.sysfs.skip)}|g" \
            ${steriliseIn} > $out
        chmod +x $out
      '';
    };
  in
    {
      name = "${name}-lxc";
      lxcConf =
        if configuration.dev.skip then
          lxcLib.id
        else
          lxcLib.setPath "autodev" 1;
       onCreate = [ create ];
       onSterilise = [ sterilise ];
       options      = {
         dev.skip   = lxcLib.mkOption { optional = true; default = false; };
         proc.skip  = lxcLib.mkOption { optional = true; default = false; };
         sysfs.skip = lxcLib.mkOption { optional = true; default = false; };
       };
    })
