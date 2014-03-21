{ stdenv, tsp, coreutils, findutils, gnugrep, gnused, systemd, lib, runCommand, writeTextFile }:

with lib;

# This component is the guest-systemd
tsp.container ({ global, configuration, containerLib }:
  let
    name = "tsp-systemd-guest";
    doInit = configuration.asInit;

    release = ./os-release.in;
    createIn = ./on-create.sh.in;
    steriliseIn = ./on-sterilise.sh.in;
    create = stdenv.mkDerivation {
      name = "${name}-oncreate";
      buildCommand = ''
        sed -e "s|@coreutils@|${coreutils}|g" \
            -e "s|@units@|${allUnitsDerivation}|g" \
            -e "s|@release@|${release}|g" \
            ${createIn} > $out
        chmod +x $out
      '';
    };
    sterilise = stdenv.mkDerivation {
      name = "${name}-onsterilise";
      buildCommand = ''
        sed -e "s|@coreutils@|${coreutils}|g" \
            ${steriliseIn} > $out
        chmod +x $out
      '';
    };

    allUnitsList = containerLib.gatherPathsWithSuffix ["systemd_all_units"] global;
    allUnits = fold (attrs: acc: acc // attrs) {} allUnitsList;

    makeUnit = name: unit:
      runCommand "unit" { preferLocalBuild = true; inherit (unit) text; }
        ((if !unit.enable then  ''
          mkdir -p $out
          ln -s /dev/null $out/${name}
        '' else if unit.linkTarget != null then ''
          mkdir -p $out
          ln -s ${unit.linkTarget} $out/${name}
        '' else if unit.text != null then ''
          mkdir -p $out
          echo -n "$text" > $out/${name}
        '' else "") + optionalString (unit.extraConfig != {}) ''
          mkdir -p $out/${name}.d
          ${concatStringsSep "\n" (mapAttrsToList (n: v: "echo -n \"${v}\" > $out/${name}.d/${n}") unit.extraConfig)}
        '');

    upstreamUnits =
      [ # Targets.
        "basic.target"
        "sysinit.target"
        "sockets.target"
        "graphical.target"
        "multi-user.target"
        "getty.target"
        "network.target"
        "network-online.target"
        "nss-lookup.target"
        "nss-user-lookup.target"
        "time-sync.target"
        #"cryptsetup.target"
        "sigpwr.target"
        "timers.target"
        "paths.target"

        # Rescue mode.
        "rescue.target"
        "rescue.service"

        # Udev.
        "systemd-udevd-control.socket"
        "systemd-udevd-kernel.socket"
        "systemd-udevd.service"
        "systemd-udev-settle.service"
        "systemd-udev-trigger.service"

        # Hardware (started by udev when a relevant device is plugged in).
        "sound.target"
        "bluetooth.target"
        "printer.target"
        "smartcard.target"

        # Login stuff.
        #"systemd-logind.service"
        #"autovt@.service"
        #"systemd-vconsole-setup.service"
        #"systemd-user-sessions.service"
        #"dbus-org.freedesktop.login1.service"
        #"user@.service"

        # Journal.
        "systemd-journald.socket"
        "systemd-journald.service"
        "systemd-journal-flush.service"
        "syslog.socket"

        # SysV init compatibility.
        "systemd-initctl.socket"
        "systemd-initctl.service"

        # Kernel module loading.
        #"systemd-modules-load.service"

        # Filesystems.
        "systemd-fsck@.service"
        "systemd-fsck-root.service"
        "systemd-remount-fs.service"
        "local-fs.target"
        "local-fs-pre.target"
        "remote-fs.target"
        "remote-fs-pre.target"
        "swap.target"
        "dev-hugepages.mount"
        "dev-mqueue.mount"
        "sys-fs-fuse-connections.mount"
        "sys-kernel-config.mount"
        "sys-kernel-debug.mount"

        # Hibernate / suspend.
        "hibernate.target"
        "suspend.target"
        "sleep.target"
        "hybrid-sleep.target"
        "systemd-hibernate.service"
        "systemd-suspend.service"
        "systemd-hybrid-sleep.service"
        "systemd-shutdownd.socket"
        "systemd-shutdownd.service"

        # Reboot stuff.
        "reboot.target"
        "systemd-reboot.service"
        "poweroff.target"
        "systemd-poweroff.service"
        "halt.target"
        "systemd-halt.service"
        "ctrl-alt-del.target"
        "shutdown.target"
        "umount.target"
        "final.target"
        "kexec.target"
        "systemd-kexec.service"

        # Password entry.
        "systemd-ask-password-console.path"
        "systemd-ask-password-console.service"
        "systemd-ask-password-wall.path"
        "systemd-ask-password-wall.service"
      ];

    upstreamWants =
      [ #"basic.target.wants"
        "sysinit.target.wants"
        "sockets.target.wants"
        "local-fs.target.wants"
        "multi-user.target.wants"
        "shutdown.target.wants"
        "timers.target.wants"
      ];

    units = defaultUnit: units:
      runCommand "units" { preferLocalBuild = true; }
      ''
        mkdir -p $out
        for i in ${toString upstreamUnits}; do
          fn=${systemd}/example/systemd/system/$i
          if ! [ -e $fn ]; then echo "missing $fn"; false; fi
          if [ -L $fn ]; then
            cp -pd $fn $out/
          else
            ln -s $fn $out/
          fi
        done

        for i in ${toString upstreamWants}; do
          fn=${systemd}/example/systemd/system/$i
          if ! [ -e $fn ]; then echo "missing $fn"; false; fi
          x=$out/$(basename $fn)
          mkdir $x
          for i in $fn/*; do
            y=$x/$(basename $i)
            cp -pd $i $y
            if ! [ -e $y ]; then rm -v $y; fi
          done
        done

        ## Bring in units defined elsewhere
        for i in ${toString (mapAttrsToList makeUnit units)}; do
          ln -fs $i/* $out/
        done

        ${concatStrings (mapAttrsToList (name: unit:
            concatMapStrings (name2: ''
              mkdir -p $out/'${name2}.wants'
              ln -sfn '../${name}' $out/'${name2}.wants'/
            '') unit.wantedBy) units)}

        ${concatStrings (mapAttrsToList (name: unit:
            concatMapStrings (name2: ''
              mkdir -p $out/'${name2}.requires'
              ln -sfn '../${name}' $out/'${name2}.requires'/
            '') unit.requiredBy) units)}

        ln -s ${defaultUnit} $out/default.target

        ln -s rescue.target $out/kbrequest.target

        mkdir -p $out/getty.target.wants/
        ln -s ../autovt@tty1.service $out/getty.target.wants/

        ln -s ../local-fs.target ../remote-fs.target ../network.target ../nss-lookup.target \
              ../nss-user-lookup.target ../swap.target $out/multi-user.target.wants/
      ''; # */ <- This is a hack to sort out syntax highlighting in emacs mode

    allUnitsDerivation = units "multi-user.target" allUnits;
  in
    {
      name = "${name}-lxc";
      storeMounts = {
                      inherit systemd release;
                      units = allUnitsDerivation;
                    } // (if doInit then { inherit (tsp) init; } else {});
      options = {
        asInit = containerLib.mkOption { optional = true; default = true; };
        allUnits = containerLib.mkOption { optional = true; default = allUnits; };
      };
      configuration = if doInit then
                        {
                          init.init = "${systemd}/lib/systemd/systemd";
                          init.args = [ "--log-target=journal" ];
                        }
                      else
                        {};
      onCreate = [ create ];
      onSterilise = [ sterilise ];
    })
