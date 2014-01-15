{stdenv, lib, lxc}:
{name, pkgs ? [], pkg ? null, lxcFun ? lib.id, exec, postCreateScript ? ""}:

assert pkgs == [] -> pkg != null;
assert pkg == null -> pkgs != [];

let
  interleave = xs: ys:
    if xs == []
    then ys
    else if ys == []
      then xs
      else [(builtins.head xs) (builtins.head ys)] ++
           interleave (builtins.tail xs) (builtins.tail ys);
  joinStrings = sep: lib.fold (e: acc: e + sep + acc);

  pkgs_ = if pkgs == [] then [pkg] else pkgs;
  depFiles = map baseNameOf pkgs_;
  pkgsDeps = interleave depFiles pkgs_;

  lxcConfigDefaults = [
    {"network.type" = "empty";}           # network is disabled by default
    {pts = 1024;}                         # use a dedicated pts for the container
    {console = "none";}                   # disable main console
    {tty = 1;}                            # no controlling tty at all

    {"cgroup.devices.deny" = "a";}          # no implicit access to devices
    {"cgroup.devices.allow" = "c 1:3 rwm"   ;} # /dev/null and zero
    {"cgroup.devices.allow" = "c 1:5 rwm"   ;}
    {"cgroup.devices.allow" = "c 5:1 rwm"   ;} # consoles
    {"cgroup.devices.allow" = "c 5:0 rwm"   ;}
    {"cgroup.devices.allow" = "c 4:0 rwm"   ;}
    {"cgroup.devices.allow" = "c 4:1 rwm"   ;}
    {"cgroup.devices.allow" = "c 1:9 rwm"   ;} # /dev/urandom,/dev/random
    {"cgroup.devices.allow" = "c 1:8 rwm"   ;}
    {"cgroup.devices.allow" = "c 136:* rwm" ;} # /dev/pts/ - pts namespaces are "coming soon"
    {"cgroup.devices.allow" = "c 5:2 rwm"   ;}
    {"cgroup.devices.allow" = "c 10:200 rwm";} # tuntap

    {pivotdir = "lxc_putold";}
    {mount = "@lxcDir@/lib/fstab";}
    #  WARNING: procfs is a known attack vector and should probably be disabled
    #           if your userspace allows it. eg. see http://blog.zx2c4.com/749
    {"mount.entry" =
       "proc @lxcDir@/rootfs/proc proc nosuid,nodev,noexec 0 0";}
    # WARNING: sysfs is a known attack vector and should probably be disabled
    # if your userspace allows it. eg. see http://bit.ly/T9CkqJ
    {"mount.entry" =
       "sysfs @lxcDir@/rootfs/sys sysfs nosuid,nodev,noexec 0 0";}

    {autodev = 1;}
    {rootfs = "@lxcDir@/rootfs";}
    {"cap.drop" = joinStrings " " ""
                  ["setpcap" "sys_module" "sys_rawio" "sys_pacct" "sys_admin"
                   "sys_nice" "sys_resource" "sys_time" "sys_tty_config" "mknod"
                   "audit_write" "audit_control" "mac_override mac_admin"];}
  ];

  lxcConfig = lxcFun lxcConfigDefaults;
  lxcConfigFile = builtins.toFile "lxc.config.in"
    (joinStrings "\n" "" (
      map (attrs: lib.fold (
        name: acc: "lxc."+name+ " = "+(toString (builtins.getAttr name attrs))
        ) "" (builtins.attrNames attrs)) lxcConfig
    ));
  mountPoints = ["dev"] ++
    (map (attrs:
      baseNameOf (builtins.elemAt (lib.splitString " " attrs."mount.entry") 1)
    ) (builtins.filter (builtins.hasAttr "mount.entry") lxcConfig));

  createSh = ./lxc-create.sh.in;
  startSh = ./lxc-start.sh.in;
  moduleNix = ./module.nix.in;
in
  stdenv.mkDerivation {
    name = "${name}-rootfs";
    exportReferencesGraph = pkgsDeps;
    buildCommand = ''
      mkdir -p $out/bin
      mkdir $out/lib
      cp ${lxcConfigFile} $out/lib/lxc.config.in

      ${joinStrings "\n" "" (map (p: "printf \"%s\n\" \""+p+"\" >> pkgs") pkgs_)}
      cat pkgs ${joinStrings " " "" depFiles} | sort | uniq | grep '^[^0-9]' > dependencies

      mountPoints='${joinStrings " " "" mountPoints}'
      for dir in $(cat dependencies); do
        if [ -d $dir ]; then
          printf "%s @lxcDir@/rootfs%s none ro,bind 0 0\n" $dir $dir >> $out/lib/fstab.in
          mountPoints="$mountPoints $dir"
        fi
      done

      sed -e "s|@shell@|${stdenv.shell}|g" \
          -e "s|@out@|$out|g" \
          -e "s|@mountPoints@|$mountPoints|g" \
          -e "s|@postCreateScript@|${postCreateScript}|g" \
          ${createSh} > $out/bin/lxc-create-${name}.sh
      chmod +x $out/bin/lxc-create-${name}.sh

      sed -e "s|@shell@|${stdenv.shell}|g" \
          -e "s|@lxc-start@|${lxc}/bin/lxc-start|g" \
          -e "s|@exec@|${exec}|g" \
          ${startSh} > $out/bin/lxc-start-${name}.sh
      chmod +x $out/bin/lxc-start-${name}.sh

      sed -e "s|@name@|${name}|g" \
          ${moduleNix} > $out/lib/module.nix
    '';
  }
