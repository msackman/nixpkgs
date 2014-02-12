let
  lib = import <nixpkgs/lib>;

  inherit (builtins) toFile getAttr attrNames isFunction length head tail filter elem toPath concatLists;
  inherit (lib) fold foldl id;
  joinStrings = sep: fold (e: acc: e + sep + acc);
  hasPath = path:
    fold (e: acc: if acc then acc else e == path) false;
  sequence = list: init: foldl (acc: f: f acc) init list;

  lxcConfLib = rec {
    inherit sequence, lib;

    setPath = name: value: config:
      assert ! (hasPath name config);
      appendPath name value config;

    appendPath = name: value: config:
      config ++ [{inherit name value;}];

    removePath = name:
      filter (e: e.name != name);

    replacePath = name: fun:
      map (e: if e.name == name then fun e else e);

    ensurePath = name: value: config:
      if elem {inherit name value;} config then
        config
      else
        appendPath name value config;

    addMountEntry = entry:
      appendPath "mount.entry" entry;

    ensureMountEntry = entry:
      ensurePath "mount.entry" entry;

    emptyConfig = [];


    configDefaults = sequence [
      (setPath "tty" 1)
      (setPath "console" "none")
      (setPath "pts" 1024)
      (setPath "pivotdir" "lxc_putold")
      (setPath "network.type" "empty")
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
  };

  loadConfig = dir: expr:
    (if isFunction expr then expr else (import (expr + "/lxc"))) lxcConfLib (toString dir);

  collectLXCPkgs = let
    g = dir: worklist:
      let
        f = worklist: seen: sets:
          if length worklist == 0 then
            sets
          else
            let
              e = head worklist;
              t = tail worklist;
            in if elem e seen then
                f t seen sets
              else let
                  seen1 = [e] ++ seen;
                  e1 = loadConfig dir e;
                  worklist1 = t ++ (if e1 ? lxcPkgs then e1.lxcPkgs else []);
                  sets1 = sets ++ [e1];
                in f worklist1 seen1 sets1;
      in f worklist [] [];
    in g;

  configToString = config:
    joinStrings "\n" "" (
      map (attrs: "lxc.${attrs.name} = ${toString attrs.value}") config);

in {
  buildLXCconf = pkgs: lxcDir:
    let
      sets = collectLXCPkgs lxcDir pkgs;
      configFuns = map (p: if p ? conf then p.conf else id) sets;
      config = sequence configFuns lxcConfLib.configDefaults;
    in
      configToString config;

  onCreate = pkgs: lxcDir:
    let
      sets = collectLXCPkgs lxcDir pkgs;
      onCreateSets = filter (set: set ? onCreate) sets;
    in
      joinStrings " " "" (concatLists (map (set: (map toString set.onCreate)) onCreateSets));

  exec = pkgs: lxcDir:
    let
      sets = collectLXCPkgs lxcDir pkgs;
      execSets = filter (set: set ? exec) sets;
    in
      toPath (head execSets).exec;
}
