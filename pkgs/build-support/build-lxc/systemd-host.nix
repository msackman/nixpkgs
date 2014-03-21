{ tsp, lib }:

tsp.container ({ global, configuration, containerLib }:
  let
    inherit (lib) fold getAttr attrNames attrValues;
    inherit (builtins) listToAttrs isList;
    analysed =
      fold (configName: {includesAttrSetList, configAttrSetList}:
        let
          configValue = getAttr configName configuration;
          analysed = fold (value: {includesAttrSetList, acc}:
                       if containerLib.isLxcPkg value then
                         {includesAttrSetList = [{name = value.name; value = value.module;}] ++ includesAttrSetList;
                          acc = ["${value.name}.service"] ++ acc;}
                       else
                         {inherit includesAttrSetList; acc = [value] ++ acc;}
                     ) {includesAttrSetList = []; acc = [];} configValue;
        in
          if isList configValue then
            {includesAttrSetList = analysed.includesAttrSetList ++ includesAttrSetList;
             configAttrSetList = [{name = configName; value = analysed.acc;}] ++ configAttrSetList;}
          else
            {inherit includesAttrSetList;
             configAttrSetList = [{name = configName; value = configValue;}] ++ configAttrSetList;}
      ) {includesAttrSetList = []; configAttrSetList = [];} (attrNames configuration);
    imports = attrValues (listToAttrs analysed.includesAttrSetList);
    nameyConfig = listToAttrs analysed.configAttrSetList;
  in
  {
    name = "systemd-host-lxc";
    options = {
      after      = containerLib.mkOption { optional = true; default = [ "network.target" ]; };
      before     = containerLib.mkOption { optional = true; default = []; };
      bindsTo    = containerLib.mkOption { optional = true; default = []; };
      conflicts  = containerLib.mkOption { optional = true; default = []; };
      partOf     = containerLib.mkOption { optional = true; default = []; };
      requiredBy = containerLib.mkOption { optional = true; default = []; };
      requires   = containerLib.mkOption { optional = true; default = []; };
      wantedBy   = containerLib.mkOption { optional = true; default = [ "multi-user.target" ]; };
      wants      = containerLib.mkOption { optional = true; default = []; };
      enabled    = containerLib.mkOption { optional = true; default = false; };
      dir        = containerLib.mkOption { optional = true; default = null; };
    };
    module =
      pkg: { config, pkgs, ... }:
        with pkgs.lib;
        let
          name = pkg.name;
          dir = if configuration.dir == null then "/var/lib/lxc/${name}" else configuration.dir;
        in
          {
            inherit imports;

            config = mkIf configuration.enabled {
              environment.systemPackages = [pkgs.libvirt];
              systemd.services = builtins.listToAttrs [{
                inherit name;
                value = {
                  description = "LXC container: ${name}";
                  inherit (nameyConfig)
                    before bindsTo conflicts partOf requiredBy wantedBy wants;
                  requires = ["libvirtd.service"] ++ nameyConfig.requires;
                  after = ["libvirtd.service"] ++ nameyConfig.after;
                  preStart = ''
                    if [ ! -f "${dir}/creator" ]; then
                      ${pkg.create}
                    else
                      ${pkg.upgrade}
                    fi
                  '';
                  serviceConfig = {
                    ExecStart       = "${pkg.start}";
                    ExecStop        = "${pkg.stop}";
                    Type            = "oneshot";
                    Restart         = "always";
                    RemainAfterExit = true;
                  };
                  unitConfig.RequiresMountsFor = dir;
                };
              }];
            };
          };
  })
