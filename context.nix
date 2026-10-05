{
  config,
  lib,
  pkgs,
  ...
}: let
  inherit
    (lib)
    mkIf
    concatStringsSep
    literalExpression
    mkOption
    types
    ;

  cfg = config.security.selinux;

  context = types.either types.str (types.submodule {
    options = {
      user = mkOption {
        type = types.str;
        default = "system_u";
        description = "SELinux user component.";
        example = "system_u";
      };

      role = mkOption {
        type = types.str;
        default = "object_r";
        description = "SELinux role component.";
        example = "object_r";
      };

      type = mkOption {
        type = types.str;
        description = "SELinux object type.";
        example = "sshd_exec_t";
      };

      level = mkOption {
        type = types.str;
        default = "s0";
        description = "SELinux MLS/MCS level and category range.";
        example = "s0";
      };
    };
  });

  mkContext = value:
    if builtins.isString value
    then value
    else
      concatStringsSep ":" [
        value.user
        value.role
        value.type
        value.level
      ];

  fileContext = types.submodule {
    options = {
      pcre = mkOption {
        type = types.str;
        description = ''
          PCRE regular expression matching the filesystem path.
        '';
        example = literalExpression ''"${pkgs.openssh}/bin/sshd"'';
      };

      fileType = mkOption {
        type = types.enum [
          "--"
          "-b"
          "-c"
          "-d"
          "-p"
          "-l"
          "-s"
        ];
        default = "--";
        description = ''
          SELinux file-context object-type selector.

          "--" means that the rule is not restricted to a particular
          filesystem object type.
        '';
      };

      context = mkOption {
        type = context;
        description = ''
          SELinux security context to assign to matching paths.
        '';

        example = literalExpression ''
          {
            user = "system_u";
            role = "object_r";
            type = "sshd_exec_t";
            level = "s0";
          }
        '';
      };
    };
  };
in {
  options.security.selinux = {
    fileContexts = mkOption {
      type = types.attrsOf fileContext;
      default = {};
      description = ''
        SELinux filesystem context rules.
      '';
    };
  };

  config =
    mkIf cfg.enable {
    };
}
