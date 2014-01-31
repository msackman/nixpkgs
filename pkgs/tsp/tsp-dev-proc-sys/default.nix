{ stdenv, buildLXC, coreutils }:
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
  buildLXC {
    name = "tsp-dev-proc-sys-lxc";
    lxcConf = ''lxcConfLib: dir:
      {conf = lxcConfLib.sequence [
        (lxcConfLib.addMountEntry ("proc "+dir+"/rootfs/proc proc nosuid,nodev,noexec 0 0"))
        (lxcConfLib.addMountEntry ("sysfs "+dir+"/rootfs/sys sysfs nosuid,nodev,noexec 0 0"))
        (lxcConfLib.setPath "autodev" 1)];
       onCreate = ["${create}/bin/on-create.sh"];
      }'';
  }