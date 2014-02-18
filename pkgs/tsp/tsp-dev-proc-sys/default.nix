{ stdenv, buildLXC, coreutils }:

buildLXC ({ configuration, lxcLib }:
  let
    boolToStr = b: if b then "true" else "false";
    createIn = ./on-create.sh.in;
    create = stdenv.mkDerivation rec {
      name = "tsp-dev-proc-sys-oncreate";
      buildCommand = ''
        sed -e "s|@coreutils@|${coreutils}|g" \
            -e "s|@dev@|${boolToStr (! configuration."dev-proc-sys.dev.skip")}|g" \
            -e "s|@proc@|${boolToStr (! configuration."dev-proc-sys.proc.skip")}|g" \
            -e "s|@sysfs@|${boolToStr (! configuration."dev-proc-sys.sysfs.skip")}|g" \
            ${createIn} > $out
        chmod +x $out
      '';
    };
  in
    {
      name = "tsp-dev-proc-sys-lxc";
      lxcConf =
        if configuration."dev-proc-sys.dev.skip" then
          lxcLib.id
        else
          lxcLib.setPath "autodev" 1;
       onCreate = [ create ];
       options = [
         (lxcLib.declareOption {
           name = "dev-proc-sys.dev.skip";
           optional = true;
           default = false;
          })
         (lxcLib.declareOption {
           name = "dev-proc-sys.proc.skip";
           optional = true;
           default = false;
          })
         (lxcLib.declareOption {
           name = "dev-proc-sys.sysfs.skip";
           optional = true;
           default = false;
          })];
    })
