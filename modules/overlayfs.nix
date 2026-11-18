{
  config,
  lib,
  pkgs,
  extendModules,
  options,
  utils,
  ...
}: let
  inherit (lib) mkOption types literalExpression;

  cfg = config.security.selinux.store;

  # Create a base version of this config with this module disabled so we avoid getting infinite recursions.
  base = extendModules {
    modules = [{security.selinux.store.enable = lib.mkForce false;}];
  };

  closureInfo = pkgs.closureInfo {
    rootPaths = cfg.closure;
  };

  hasVmFs = options.virtualisation ? fileSystems;
  withFs = defs:
    if hasVmFs
    then {virtualisation.fileSystems = defs;}
    else {fileSystems = defs;};

  baseFileSystems =
    if hasVmFs
    then base.config.virtualisation.fileSystems
    else base.config.fileSystems;

  hasStoreMount = baseFileSystems ? "/nix/store";

  realStoreDir = toString cfg.realStoreDir;
  metadataDir = toString cfg.metadataDir;

  originalStoreFs = lib.mkMerge [
    baseFileSystems."/nix/store"
    {
      mountPoint = realStoreDir;
    }
  ];

  erofsImage = pkgs.callPackage ../pkgs/mk-store-image.nix {
    closure = closureInfo;
    contexts = null;
  };

  imagePath = "/sysroot${realStoreDir}/${builtins.baseNameOf erofsImage}";

  mountUnit = p: "${utils.escapeSystemdPath "/sysroot${p}"}.mount";
in {
  options.security.selinux.store = {
    enable = mkOption {
      type = types.bool;
      default = true;
      internal = true;
    };

    realStoreDir = mkOption {
      type = types.path;
      default = "/.nix-store";
      description = "The actual location of the nix store.";
    };

    metadataDir = mkOption {
      type = types.path;
      default = "/.selinux-metadata";
      description = "Where the erofs image holding the SELinux metadata is mounted.";
    };

    # The location of the stored contexts.
    contextsDir = mkOption {};

    # The system paths.
    closure = mkOption {
      type = types.listOf types.package; # Either a derivation or a store path. Which is what we want.
      default = [base.config.system.build.toplevel]; # This should be more than enough for most cases.
      defaultText = literalExpression "[ config_without_senix_module.system.build.toplevel ]";
      description = ''
        A list of closures to be described by the nixos system
      '';
    };
  };

  config = lib.mkIf cfg.enable (
    lib.mkMerge [
      # # Assertions
      # {
      # }

      # Common store and settings
      {
        # Point it to the right store. For builders etc.
        # For local interactions, we need to know where the actual store is.
        # works with:
        #   - local store
        #   - experimental local overlay store
        #   - experimental mounted ssh store
        #   - local daemon store
        nix.settings.store = "auto?real=${realStoreDir}";

        # Need erofs loop and overlay for the stores
        boot.initrd.supportedFilesystems = ["erofs"];
        boot.initrd.kernelModules = [
          "loop"
          "erofs"
          "overlay"
        ];

        # Make sure the image is in the closure since we only reference by string
        system.extraDependencies = [erofsImage];
      }

      # Setup absolute filesystem stuff
      (withFs {
        ${cfg.metadataDir} = {
          device = imagePath;
          fsType = "erofs";
          options = [
            "loop"
            "ro"
          ];
          neededForBoot = true;
          depends = [realStoreDir];
        };

        "/nix/store-selinux" = {
          mountPoint = "/nix/store";
          device = "overlay";
          fsType = "overlay";
          neededForBoot = true;
          options = [
            "metacopy=on"
            "redirect_dir=on"
          ];
          depends = [
            metadataDir
            realStoreDir
          ];
          overlay.lowerdir = [
            metadataDir
            realStoreDir
          ];
        };
      })

      # Move mountPoint of nix store if already present.
      (lib.mkIf hasStoreMount (withFs {
        "/nix/store".mountPoint = cfg.realStoreDir;
      }))

      (lib.mkIf (!hasStoreMount) (withFs {
        ${realStoreDir} = {
          device = "/nix//store";
          fsType = "none";
          options = [
            "bind"
            "private"
            "x-mount.mkdir"
            "x-systemd.after=sysroot.mount"
            "x-systemd.before=${mountUnit metadataDir}"
            "x-systemd.before=${mountUnit "/nix/store"}"
          ];
          neededForBoot = true;
        };
      }))

      # No nix store defined, therefore we create our own bind mounted one at specified location.
      # (lib.mkIf (!hasStoreMount) (withFs {
      #   ${realStoreDir} = {
      #     device = "/nix/store";
      #     fsType = "none";
      #     options = ["bind"];
      #     neededForBoot = true;
      #   };
      # }))
      #
      # # If we need a bind unit, then we have to bind the real store using a initrd service because
      # # we can't do it through nix modules because of ordering issues. Because of various other
      # # fuckery we can't depend on the fileSystem module.
      # (lib.mkIf (!hasStoreMount) {
      #   boot.initrd.systemd.services.bind-real-store = {
      #     wantedBy = ["initrd-root-fs.target"];
      #     requires = ["sysroot.mount"];
      #     after = ["sysroot.mount"];
      #     before = [
      #       "initrd-root-fs.target"
      #       (mountUnit metadataDir)
      #       (mountUnit "/nix/store")
      #     ];
      #     unitConfig.DefaultDependencies = false;
      #     serviceConfig = {
      #       Type = "oneshot";
      #       RemainAfterExit = true;
      #     };
      #     script = ''
      #       mkdir -p /sysroot/nix/store /sysroot${realStoreDir}
      #       mount --bind /sysroot/nix/store /sysroot${realStoreDir}
      #       mount --make-private /sysroot${realStoreDir}
      #     '';
      #   };
      # })
    ]
  );
}
