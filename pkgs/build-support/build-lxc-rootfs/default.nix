{stdenv, lib}:
{name, pkgs ? [], pkg ? null, lxcFun ? lib.id}:

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
  ];

  lxcConfig = lxcFun lxcConfigDefaults;
  lxcConfigFile = builtins.toFile "lxc.config.in"
    (joinStrings "\n" "" (
      map (attrs: lib.fold (
        name: acc: "lxc."+name+ " = "+(toString (builtins.getAttr name attrs))
        ) "" (builtins.attrNames attrs)) lxcConfig
    ));
  mountPoints = ["proc" "sys" "dev"]; #manually keep in sync with lxc.mount.entry

  createSh = ./create-rootfs.sh.in;
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

      sed -e "s|@out@|$out|g" \
          -e "s|@shell@|${stdenv.shell}|g" \
          -e "s|@mountPoints@|$mountPoints|g" \
          ${createSh} > $out/bin/${name}-create-rootfs.sh
      chmod +x $out/bin/${name}-create-rootfs.sh
    '';
  }
