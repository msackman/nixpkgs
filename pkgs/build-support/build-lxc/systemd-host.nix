{ tsp, lib }:

tsp.container ({ global, configuration, containerLib }:
  let
    inherit (lib) fold getAttr attrNames attrValues;
    inherit (builtins) listToAttrs isList;
    analysed =
      fold (configName: {importsAttrSetList, configAttrSetList}:
        let
          configValue = getAttr configName configuration;
          analysed = fold (value: {importsAttrSetList, acc}:
                       if containerLib.isLxcPkg value then
                         {importsAttrSetList = [{name = value.name; value = value.module;}] ++ importsAttrSetList;
                          acc = ["${value.name}.service"] ++ acc;}
                       else
                         {inherit importsAttrSetList; acc = [value] ++ acc;}
                     ) {importsAttrSetList = []; acc = [];} configValue;
        in
          if isList configValue then
            {importsAttrSetList = analysed.importsAttrSetList ++ importsAttrSetList;
             configAttrSetList = [{name = configName; value = analysed.acc;}] ++ configAttrSetList;}
          else
            {inherit importsAttrSetList;
             configAttrSetList = [{name = configName; value = configValue;}] ++ configAttrSetList;}
      ) {importsAttrSetList = []; configAttrSetList = [];} (attrNames configuration);
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
    configuration = nameyConfig;
    module =
      pkg: { config, pkgs, ... }:
        with pkgs.lib;
        let
          name = pkg.name;
          dir = if configuration.dir == null then "/var/lib/lxc/${name}" else configuration.dir;
        in
          {
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
