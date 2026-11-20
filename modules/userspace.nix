{
  config,
  lib,
  pkgs,
  ...
}: let
  inherit (lib) mkOption types mkIf mkDefault;

  cfg = config.security.selinux.userspace;
in {
  options = {
    options.security.selinux.userspace = {
      enable = mkOption {
        type = types.bool;
        default = true;
        description = "Whether to enable userspace packages";
      };
    };
  };
  config = mkIf cfg.enable {
    systemd.package = mkDefault (pkgs.systemd.override {withSelinx = true;});

    services.openssh.package = mkDefault (pkgs.openssh.override {withSelinux = true;});

    services.dbus.dbusPackage = mkDefault (pkgs.dbus.overrideAttrs (old: {
      buildInputs = (old.buildInputs or []) ++ [pkgs.libselinux];
      mesonFlags = (old.mesonFlags or []) ++ [(lib.mesonEnable "selinux" true)];
    }));

    security.pam.package = mkDefault (pkgs.linux-pam.overrideAttrs (old: {
      buildInputs = (old.buildInputs or []) ++ [pkgs.libselinux];
      mesonFlags = (old.mesonFlags or []) ++ [(lib.mesonEnable "selinux" true)];
    }));

    environment.systemPackages = [
      (lib.hiPrio (pkgs.coreutils-full.override {selinuxSupport = true;}))
    ];
  };
}
