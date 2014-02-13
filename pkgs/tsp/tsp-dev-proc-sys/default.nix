{ stdenv, buildLXC, coreutils, lib }:

buildLXC ({ configuration, lxcLib }:
  let
    createIn = ./on-create.sh.in;
    create = stdenv.mkDerivation rec {
      name = "tsp-dev-proc-sys-oncreate";
      buildCommand = ''
        mkdir -p $out/bin
        sed -e "s|@coreutils@|${coreutils}|g" \
            ${createIn} > $out/bin/on-create.sh
      '';
    };
  in
    {
      name = "tsp-dev-proc-sys-lxc";
      lxcConf =
        let
          defaults = {
            proc  = lxcLib.addMountEntry (dir: "proc "+dir+"/rootfs/proc proc nosuid,nodev,noexec 0 0");
            sysfs = lxcLib.addMountEntry (dir: "sysfs "+dir+"/rootfs/sys sysfs nosuid,nodev,noexec 0 0");
            dev   = lxcLib.setPath "autodev" 1;
          };
        in
          lib.fold (name: acc:
            if builtins.getAttr "dev-proc-sys.${name}.skip" configuration then
              acc
            else
              acc ++ (builtins.getAttr name defaults)) [] (builtins.attrNames defaults);
       onCreate = [ "${create}/bin/on-create.sh" ];
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
           name = "dev-proc-sys.sys.skip";
           optional = true;
           default = false;
          })];
    })