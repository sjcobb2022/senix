{
  config,
  lib,
  pkgs,
  ...
}: let
  inherit
    (lib)
    mkOption
    mkIf
    types
    mkDefault
    ;

  cfg = config.security.selinux.userspace;
in {
  options.security.selinux.userspace = {
    enable = mkOption {
      type = types.bool;
      example = false;
      default = config.security.selinux.enable;
      description = "Whether to enable SELinux userspace.";
    };
  };

  config = mkIf cfg.enable {
    systemd.package = mkDefault (pkgs.systemd.override {withSelinux = true;});

    services.openssh.package = mkDefault (pkgs.openssh.override {withSelinux = true;});

    # TODO: Open nixpkgs issue to make this configurable
    services.dbus.dbusPackage = mkDefault (
      pkgs.dbus.overrideAttrs (old: {
        buildInputs = (old.buildInputs or []) ++ [pkgs.libselinux];
        mesonFlags = (old.mesonFlags or []) ++ [(lib.mesonEnable "selinux" true)];
      })
    );

    # TODO: Open a nixpkgs issue to make this configurable.
    security.pam.package = mkDefault (
      pkgs.linux-pam.overrideAttrs (old: {
        buildInputs = (old.buildInputs or []) ++ [pkgs.libselinux];
        mesonFlags = (old.mesonFlags or []) ++ [(lib.mesonEnable "selinux" true)];

        postPatch =
          (old.postPatch or "")
          # bash
          + ''
            substituteInPlace modules/module-meson.build \
              --replace-fail "  install_emptydir(
                sepermit_lockdir,
                install_tag: 'config',
              )
            " ""
          '';
      })
    );

    systemd.tmpfiles.rules = ["d /run/sepermit 0755 root root -"];

    # Disable check because the sandbox that we have at least does not have selinux enable so it can't run the necessary tests.
    environment.systemPackages = [
      (lib.hiPrio ((pkgs.coreutils-full.override {selinuxSupport = true;}).overrideAttrs {doCheck = false;}))
    ];
  };
}
