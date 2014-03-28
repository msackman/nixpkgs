{ stdenv, tsp, coreutils, lib, pkgs }:

with lib;

# This component is just a collector for guest-systemd
# units. Eventually, we should grab the validators out of the nixos
# systemd and systemd-unit-options modules/expressions and integrate
# them here. For the time being, life is far too short.
tsp.container ({ global, configuration, containerLib }:
  let
    name = "tsp-systemd-units";

    escapeSystemdPath = s:
      replaceChars ["/" "-" " "] ["-" "\\x2d" "\\x20"] (substring 1 (stringLength s) s);

    makeJobScript = name: text:
      let x = pkgs.writeTextFile { name = "unit-script"; executable = true; destination = "/bin/${name}"; inherit text; };
      in "${x}/bin/${name}";


    toOption = x:
      if x == true then "true"
      else if x == false then "false"
      else toString x;

    attrsToSection = as:
      concatStrings (concatLists (mapAttrsToList (name: value:
        map (x: ''
            ${name}=${toOption x}
          '')
          (if isList value then value else [value]))
          as));

    ## All these defaults define the valid keys by which the various
    ## different types of units can be configured.
    unitDefaults = {
      enable = true;
      description = "";
      requires = [ "network.target" ];
      wants = [];
      after = [ "network.target" ];
      before = [];
      bindsTo = [];
      partOf = [];
      conflicts = [];
      requiredBy = [];
      wantedBy = [ "multi-user.target" ];
      unitConfig = {};
      restartTriggers = [];
    };
    serviceDefaults = unitDefaults // {
      environment = {};
      path = [];
      script = "";
      scriptArgs = "";
      preStart = "";
      postStart = "";
      preStop = "";
      postStop = "";
      startAt = "";
      serviceConfig = {};
    };
    socketDefaults = unitDefaults // {
      listenStreams = [];
      socketConfig = {};
    };
    timerDefaults = unitDefaults // {
      timerConfig = {};
    };
    mountDefaults = unitDefaults // {
      # "what" is mandatory
      # "where" is mandatory
      type = "";
      options = "";
      mountConfig = {};
    };
    automountDefaults = unitDefaults // {
      # "where" is mandatory
      automountConfig = {};
    };

    # The transform functions populate the "sub" attrsets of each
    # config (and other bits)
    transformUnit = name: config: recursiveUpdate {
        unitConfig = {
          Requires = concatStringsSep " " config.requires;
          Wants = concatStringsSep " " config.wants;
          After = concatStringsSep " " config.after;
          Before = concatStringsSep " " config.before;
          BindsTo = concatStringsSep " " config.bindsTo;
          PartOf = concatStringsSep " " config.partOf;
          Conflicts = concatStringsSep " " config.conflicts;
        } // optionalAttrs (config.description != "") {
          Description = config.description;
        };
      } config;

    transformService = name: config: recursiveUpdate (rec {
        path = [pkgs.systemd] ++ (if config ? path then config.path else []);
        environment.PATH = "${makeSearchPath "bin" path}:${makeSearchPath "sbin" path}";
        serviceConfig = listToAttrs (concatLists [
          (if config.preStart != serviceDefaults.preStart then
             [{name = "ExecStartPre"; value = makeJobScript "${name}-pre-start" ''
               #! ${stdenv.shell} -e
               ${config.preStart}
             '';}]
           else [])
          (if config.script != serviceDefaults.script then
             [{name = "ExecStart"; value = makeJobScript "${name}-start" ''
               #! ${stdenv.shell} -e
               ${config.script}
             '' + " " + config.scriptArgs;}]
           else [])
          (if config.postStart != serviceDefaults.postStart then
             [{name = "ExecStartPOst"; value = makeJobScript "${name}-post-start" ''
               #! ${stdenv.shell} -e
               ${config.postStart}
             '';}]
           else [])
          (if config.preStop != serviceDefaults.preStop then
             [{name = "ExecStop"; value = makeJobScript "${name}-pre-stop" ''
               #! ${stdenv.shell} -e
               ${config.preStop}
             '';}]
           else [])
          (if config.postStop != serviceDefaults.postStop then
             [{name = "ExecStopPost"; value = makeJobScript "${name}-post-stop" ''
               #! ${stdenv.shell} -e
               ${config.postStop}
             '';}]
           else [])
        ]);
      }) config;

    transformMount = name: config: recursiveUpdate {
        mountConfig = listToAttrs (concatLists [
          [{name = "What"; value = config.what;}]
          [{name = "Where"; value = config.where;}]
          (if config.type != mountDefaults.type then
             [{name = "Type"; value = config.type;}]
           else [])
          (if config.options != mountDefaults.options then
             [{name = "Options"; value = config.options;}]
           else [])
        ]);
      } config;

    transformAutomount = name: config: recursiveUpdate {
        automountConfig = { Where = config.where; };
      } config;

    targetToUnit = name: config:
      let def = transformUnit name (recursiveUpdate unitDefaults config); in
      { inherit (def) wantedBy requiredBy enable;
        text =
          ''
            [Unit]
            ${attrsToSection def.unitConfig}
          '';
      };

    serviceToUnit = name: config:
      let def = transformService name (transformUnit name (recursiveUpdate serviceDefaults config)); in
      { inherit (def) wantedBy requiredBy enable;
        text =
          ''
            [Unit]
            ${attrsToSection def.unitConfig}

            [Service]
            ${let env = def.environment;
              in concatMapStrings (n: "Environment=\"${n}=${getAttr n env}\"\n") (attrNames env)}
            ${attrsToSection def.serviceConfig}
          '';
      };

    socketToUnit = name: def:
      let def = transformUnit name (recursiveUpdate socketDefaults config); in
      { inherit (def) wantedBy requiredBy enable;
        text =
          ''
            [Unit]
            ${attrsToSection def.unitConfig}

            [Socket]
            ${attrsToSection def.socketConfig}
            ${concatStringsSep "\n" (map (s: "ListenStream=${s}") def.listenStreams)}
          '';
      };

    timerToUnit = name: config:
      let def = transformUnit name (recursiveUpdate timerDefaults config); in
      { inherit (def) wantedBy requiredBy enable;
        text =
          ''
            [Unit]
            ${attrsToSection def.unitConfig}

            [Timer]
            ${attrsToSection def.timerConfig}
          '';
      };

    mountToUnit = name: config:
      let def = transformMount name (transformUnit name (recursiveUpdate mountDefaults config)); in
      { inherit (def) wantedBy requiredBy enable;
        text =
          ''
            [Unit]
            ${attrsToSection def.unitConfig}

            [Mount]
            ${attrsToSection def.mountConfig}
          '';
      };

    automountToUnit = name: config:
      let def = transformAutomount name (transformUnit name (recursiveUpdate automountDefaults config)); in
      { inherit (def) wantedBy requiredBy enable;
        text =
          ''
            [Unit]
            ${attrsToSection def.unitConfig}

            [Automount]
            ${attrsToSection def.automountConfig}
          '';
      };

    rawUnitDefaults = {
      text = "";
      enable = true;
      requiredBy = [];
      wantedBy = [];
      linkTarget = null;
      extraConfig = {};
    };

    targetsList = containerLib.gatherPathsWithSuffix ["systemd_targets"] global;
    servicesList = containerLib.gatherPathsWithSuffix ["systemd_services"] global;
    socketsList = containerLib.gatherPathsWithSuffix ["systemd_sockets"] global;
    timersList = containerLib.gatherPathsWithSuffix ["systemd_timers"] global;
    mountsList = concatLists (containerLib.gatherPathsWithSuffix ["systemd_mounts"] global);
    automountsList = concatLists (containerLib.gatherPathsWithSuffix ["systemd_automounts"] global);

    targets = fold (attrSet: acc: acc // attrSet) {} targetsList;
    services = fold (attrSet: acc: acc // attrSet) {} servicesList;
    sockets = fold (attrSet: acc: acc // attrSet) {} socketsList;
    timers = fold (attrSet: acc: acc // attrSet) {} timersList;

    targetsAsUnits = mapAttrs' (n: v: nameValuePair "${n}.target"
                                 (recursiveUpdate rawUnitDefaults (targetToUnit n v))) targets;
    servicesAsUnits = mapAttrs' (n: v: nameValuePair "${n}.service"
                                 (recursiveUpdate rawUnitDefaults (serviceToUnit n v))) services;
    socketsAsUnits = mapAttrs' (n: v: nameValuePair "${n}.socket"
                                 (recursiveUpdate rawUnitDefaults (socketToUnit n v))) sockets;
    timersAsUnits = mapAttrs' (n: v: nameValuePair "${n}.timer"
                                 (recursiveUpdate rawUnitDefaults (timerToUnit n v))) timers;
    mountsAsUnits = listToAttrs (map (v: let n = escapeSystemdPath v.where; in
                                         nameValuePair "${n}.mount"
                                         (recursiveUpdate rawUnitDefaults (mountToUnit n v))) mountsList);
    automountsAsUnits = listToAttrs (map (v: let n = escapeSystemdPath v.where; in
                                         nameValuePair "${n}.automount"
                                         (recursiveUpdate rawUnitDefaults (automountToUnit n v))) automountsList);

    allUnits = targetsAsUnits // servicesAsUnits // socketsAsUnits //
               timersAsUnits // mountsAsUnits // automountsAsUnits;
  in
    {
      name = "${name}-lxc";
      options = {
        systemd_targets = containerLib.mkOption {
                  optional = true;
                  default  = {};
                };
        systemd_services = containerLib.mkOption {
                  optional = true;
                  default  = {};
                };
        systemd_sockets = containerLib.mkOption {
                  optional = true;
                  default  = {};
                };
        systemd_timers = containerLib.mkOption {
                  optional = true;
                  default  = {};
                };
        systemd_mounts = containerLib.mkOption {
                  optional = true;
                  default  = [];
                };
        systemd_automounts = containerLib.mkOption {
                  optional = true;
                  default  = [];
                };
        systemd_all_units = containerLib.mkOption {
                  optional = false;
                };
      };
      configuration = {
        systemd_all_units = allUnits;
      };
    })
