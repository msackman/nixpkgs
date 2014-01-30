let
  lib = import <nixpkgs/lib>;

  inherit (builtins) toFile getAttr attrNames isFunction length head tail filter elem toPath;
  inherit (lib) fold foldl id;
  joinStrings = sep: fold (e: acc: e + sep + acc);
  hasPath = path:
    fold (e: acc: if acc then acc else e == path) false;
  sequence = list: init: foldl (acc: f: f acc) init list;
  listDelete = toDelete: filter (e: e != toDelete);

  lxcConfLib = rec {
    inherit sequence;

    setPath = name: value: config:
      assert ! (hasPath name config);
      appendPath name value config;

    appendPath = name: value: config:
      config ++ [{inherit name value;}];

    removePath = name:
      filter (e: e.name != name);

    replacePath = name: fun:
      map (e: if e.name == name then fun e else e);

    addMountEntry = entry:
      appendPath "mount.entry" entry;

    emptyConfig = [];

    addNetwork = network:
      # 'type' must come first. Yes, lxc.conf is retarded.
      sequence (fold (name: acc:
        [(removePath "network.${name}")
         (appendPath "network.${name}" (getAttr name network))] ++ acc
      ) [] (["type"] ++ (listDelete "type" (attrNames network))));

    configDefaults = sequence [
      (setPath "tty" 1)
      (setPath "console" "none")
      (setPath "pts" 1024)
      (setPath "pivotdir" "lxc_putold")
      (setPath "autodev" 1)
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

  loadConfig = expr:
    (if isFunction expr then expr else (import (expr + "/lxc"))) lxcConfLib;

  collectLXCPkgs = rec {
    g = worklist: f worklist [] [] [];
    f = worklist: seen: paths: sets:
      if length worklist == 0 then
        { inherit sets paths; }
      else
        let
          e = head worklist;
          t = tail worklist;
        in if elem e seen then
            f t seen paths sets
          else let
              seen1 = [e] ++ seen;
              e1 = loadConfig e;
              worklist1 = t ++ (if e1 ? lxcPkgs then e1.lxcPkgs else []);
              sets1 = sets ++ [e1];
              paths1 = if isFunction e then paths else paths ++ [e];
            in f worklist1 seen1 paths1 sets1;}.g;

  configToString = config:
    joinStrings "\n" "" (
      map (attrs: "lxc.${attrs.name} = ${toString attrs.value}") config);

in {
  buildLXCconf = pkgs: lxcDir:
    let
      sets = (collectLXCPkgs pkgs).sets;
      configFuns = map (p: p.conf) sets;
      config = sequence configFuns lxcConfLib.configDefaults;
    in
      configToString config;

  collectLXCpaths = pkgs:
    joinStrings " " "" (map toString (collectLXCPkgs pkgs).paths);

  exec = pkgs:
    let
      sets = (collectLXCPkgs pkgs).sets;
      execSets = filter (set: set ? exec) sets;
    in
      toPath (head execSets).exec;
}
