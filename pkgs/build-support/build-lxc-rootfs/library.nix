{lib}:
let

  inherit (builtins) toFile getAttr attrNames;
  inherit (lib) filter fold foldl id;
  joinStrings = sep: fold (e: acc: e + sep + acc);
  hasPath = path:
    fold (e: acc: if acc then acc else e == path) false
  sequence = list: init: foldl id init list;

in rec {
  setPath = name: value: config:
    assert ! (hasPath name config);
    appendPath path rootfs config;

  appendPath = name: value: config:
    config ++ [{inherit name value}];

  removePath = name:
    filter (e: e.name != name);

  replacePath = name: fun:
    map (e: if e.name == name then fun e else e);

  emptyConfig = [];

  addNetwork = network:
    sequence (fold (name: acc:
      [(removePath "network.${name}")
       (appendPath "network.${name}" (getAttr name network))] ++ acc
    ) [] (attrNames network))

  configDefaults = sequence [
    (setPath "tty" 1)
    (setPath "console" "none")
    (setPath "pts" 1024)
    (setPath "pivotdir" "lxc_putold")
    (setPath "autodev" 1)
    (appendPath "cgroup.devices.deny" "a")          # no implicit access to devices
    (appendPath "cgroup.devices.allow" "c 1:3 rwm"   ) # /dev/null and zero
    (appendPath "cgroup.devices.allow" "c 1:5 rwm"   )
    (appendPath "cgroup.devices.allow" "c 5:1 rwm"   ) # consoles
    (appendPath "cgroup.devices.allow" "c 5:0 rwm"   )
    (appendPath "cgroup.devices.allow" "c 4:0 rwm"   )
    (appendPath "cgroup.devices.allow" "c 4:1 rwm"   )
    (appendPath "cgroup.devices.allow" "c 1:9 rwm"   ) # /dev/urandom,/dev/random
    (appendPath "cgroup.devices.allow" "c 1:8 rwm"   )
    (appendPath "cgroup.devices.allow" "c 136:* rwm" ) # /dev/pts/ - pts namespaces are "coming soon"
    (appendPath "cgroup.devices.allow" "c 5:2 rwm"   )
    (appendPath "cgroup.devices.allow" "c 10:200 rwm") # tuntap
    (setPath "cap.drop"
      (joinStrings " " ""
        ["setpcap" "sys_module" "sys_rawio" "sys_pacct" "sys_admin"
         "sys_nice" "sys_resource" "sys_time" "sys_tty_config" "mknod"
         "audit_write" "audit_control" "mac_override mac_admin"]))
    ] emptyConfig;

    {"network.type" = "empty";}           # network is disabled by default

    {mount = "@lxcDir@/lib/fstab";}
    #  WARNING: procfs is a known attack vector and should probably be disabled
    #           if your userspace allows it. eg. see http://blog.zx2c4.com/749
    {"mount.entry" =
       "proc @lxcDir@/rootfs/proc proc nosuid,nodev,noexec 0 0";}
    # WARNING: sysfs is a known attack vector and should probably be disabled
    # if your userspace allows it. eg. see http://bit.ly/T9CkqJ
    {"mount.entry" =
       "sysfs @lxcDir@/rootfs/sys sysfs nosuid,nodev,noexec 0 0";}

    {rootfs = "@lxcDir@/rootfs";}
  ];

  writeConfig = file: config:
    toFile file
    (joinStrings "\n" "" (
      map (attrs: fold (
        name: acc: "lxc."+name+ " = "+(toString (getAttr name attrs))
        ) "" (attrNames attrs)) config
    ));
}