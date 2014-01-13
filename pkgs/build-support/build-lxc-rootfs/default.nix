{stdenv, lib}:
{name, pkgs ? [], pkg ? null, bridge ? null}:

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
  joinStrings = sep: lib.fold (e: acc: e + sep + acc) "";

  pkgs_ = if pkgs == [] then [pkg] else pkgs;
  depFiles = map baseNameOf pkgs_;
  pkgsDeps = interleave depFiles pkgs_;

  configFile = builtins.toFile "config.in" ''
    ${if bridge == null then ''
        # network is disabled (-n=false)
        lxc.network.type = empty
      '' else ''
        # network configuration
        lxc.network.type = veth
        lxc.network.link = ${bridge}
        lxc.network.name = eth0
      ''}

    # root filesystem
    lxc.rootfs = @out@/rootfs

    # use a dedicated pts for the container (and limit the number of pseudo terminal
    # available)
    lxc.pts = 1024

    # disable the main console
    lxc.console = none

    # no controlling tty at all
    lxc.tty = 1

    # no implicit access to devices
    lxc.cgroup.devices.deny = a

    # /dev/null and zero
    lxc.cgroup.devices.allow = c 1:3 rwm
    lxc.cgroup.devices.allow = c 1:5 rwm

    # consoles
    lxc.cgroup.devices.allow = c 5:1 rwm
    lxc.cgroup.devices.allow = c 5:0 rwm
    lxc.cgroup.devices.allow = c 4:0 rwm
    lxc.cgroup.devices.allow = c 4:1 rwm

    # /dev/urandom,/dev/random
    lxc.cgroup.devices.allow = c 1:9 rwm
    lxc.cgroup.devices.allow = c 1:8 rwm

    # /dev/pts/ - pts namespaces are "coming soon"
    lxc.cgroup.devices.allow = c 136:* rwm
    lxc.cgroup.devices.allow = c 5:2 rwm

    # tuntap
    lxc.cgroup.devices.allow = c 10:200 rwm

    # NOTICE: These mounts must be applied within the namespace

    #  WARNING: procfs is a known attack vector and should probably be disabled
    #           if your userspace allows it. eg. see http://blog.zx2c4.com/749
    lxc.mount.entry = proc @out@/rootfs/proc proc nosuid,nodev,noexec 0 0

    # WARNING: sysfs is a known attack vector and should probably be disabled
    # if your userspace allows it. eg. see http://bit.ly/T9CkqJ
    lxc.mount.entry = sysfs @out@/rootfs/sys sysfs nosuid,nodev,noexec 0 0

    lxc.mount.entry = devpts @out@/rootfs/dev/pts devpts newinstance,ptmxmode=0666,nosuid,noexec 0 0
    lxc.mount.entry = shm @out@/rootfs/dev/shm tmpfs size=65536k,nosuid,nodev,noexec 0 0
  '';
in
  stdenv.mkDerivation {
    name = "${name}-rootfs";
    exportReferencesGraph = pkgsDeps;
    buildCommand = ''
      mkdir -p $out/rootfs
      mkdir $out/rootfs/proc
      mkdir $out/rootfs/sys
      mkdir $out/rootfs/dev
      mkdir $out/rootfs/dev/pts
      mkdir $out/rootfs/dev/shm
      mkdir -p $out/lxc
      ${joinStrings "\n" (map (p: "printf \"%s\n\" \""+p+"\" >> pkgs") pkgs_)}
      cat pkgs ${joinStrings " " depFiles} | sort | uniq | grep '^[^0-9]' > dependencies

      for dir in $(cat dependencies); do
        if [ -d $dir ]; then
          mkdir -p $out/rootfs$dir
          printf "%s %s none ro,bind 0 0\n" $dir $out/rootfs$dir >> $out/lxc/fstab
        fi
      done

      sed -e "s|@out@|$out|g" ${configFile} > $out/lxc/config
    '';
  }
