{ stdenv, tsp, coreutils, pkgs }:

# This component is just a collector for guest-systemd units
tsp.container ({ global, configuration, containerLib }:
  let
    # Thankfully, the nixos module for systemd units does not rely on
    # anything in config, which is mighty useful as we can just reuse
    # it here. Yes, slightly fragile, but it should then mean we can
    # reuse any existing systemd units.
    unitModule = (import <nixos>/modules/system/boot/systemd-unit-options.nix) { config = null; inherit pkgs; };
    name = "tsp-systemd-units";
  in
    {
      name = "${name}-lxc";
      options = {
        systemd_units = containerLib.mkOption {
                  optional = true;
                  default  = [];
                };
      };
    })
