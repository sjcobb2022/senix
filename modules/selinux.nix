# Taken directly from https://github.com/NixOS/nixpkgs/pull/396177/commits/394ec3e8b8a6415f28190d3a4fca717ab77a4ce5
{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.security.selinux;
in {
  options.security.selinux = {
    enable = lib.mkEnableOption "SELinux";

    policy = lib.mkOption {
      type = lib.types.path;
      description = "The path to the SELinux policy.";
      default = "${pkgs.selinux-refpolicy.override {
        inherit (cfg) policyVersion;
      }}/share/selinux/refpolicy";
      defaultText = lib.literalExpression ''
        "''${pkgs.selinux-refpolicy.override {
          inherit (config.security.selinux) policyVersion;
        }}/share/selinux/refpolicy"
      '';
    };

    policyVersion = lib.mkOption {
      type = lib.types.nullOr lib.types.int;
      description = "The version of the SELinux policy.";
      default = null;
    };

    type = lib.mkOption {
      type = lib.types.str;
      description = "The SELinux policy type to load.";
      default = "refpolicy";
    };

    mode = lib.mkOption {
      type = lib.types.enum [
        "enforcing"
        "permissive"
        "disabled"
      ];
      description = "The SELinux enforcement mode.";
      default = "permissive";
    };
  };

  config = lib.mkIf cfg.enable {
    boot.kernelPatches = [
      {
        name = "selinux";
        structuredExtraConfig = with lib.kernel; {
          SECURITY_SELINUX = yes;
        };
        patch = null;
      }
    ];

    security.lsm = ["selinux"];

    environment.etc = {
      "selinux/config".text = ''
        SELINUX=${cfg.mode}
        SELINUXTYPE=${cfg.type}
      '';

      "selinux/semanage.conf".text =
        lib.optionalString (cfg.policyVersion != null) ''
          policy-version = ${toString cfg.policyVersion}
        ''
        + ''
          compiler-directory = ${pkgs.policycoreutils}/libexec/selinux/hll

          [load_policy]
          path = ${lib.getExe' pkgs.policycoreutils "load_policy"}
          [end]

          [setfiles]
          path = ${lib.getExe' pkgs.policycoreutils "setfiles"}
          args = -q -c $@ $<
          [end]

          [sefcontext_compile]
          path = ${lib.getExe' pkgs.libselinux "sefcontext_compile"}
          args = -r $@
          [end]
        '';
    };

    environment.systemPackages = [
      pkgs.libselinux
      pkgs.policycoreutils
    ];

    system.activationScripts.selinux = {
      deps = ["etc"];

      text = ''
        install -d -m0755 /var/lib/selinux

        cmd="${lib.getExe' pkgs.policycoreutils "semodule"} \
          -s ${lib.escapeShellArg cfg.type} \
          -i ${lib.escapeShellArg cfg.policy}/*.pp"

        skipSELinuxActivation=0

        if [ -f /var/lib/selinux/activate-check ]; then
          if [ "$(cat /var/lib/selinux/activate-check)" = "$cmd" ]; then
            skipSELinuxActivation=1
          fi
        fi

        if [ "$skipSELinuxActivation" -eq 0 ]; then
          eval "$cmd"
          echo "$cmd" > /var/lib/selinux/activate-check
        fi
      '';
    };
  };
}
