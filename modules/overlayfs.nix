{
  config,
  lib,
  pkgs,
  extendModules,
  options,
  utils,
  ...
}:
let
  inherit (lib) mkOption types literalExpression;

  cfg = config.security.selinux.store;

  # Create a base version of this config with this module disabled so we avoid getting infinite recursions.
  base = extendModules {
    modules = [ { security.selinux.store.enable = lib.mkForce false; } ];
  };

  closureInfo = pkgs.closureInfo {
    rootPaths = cfg.closure;
  };

  erofsImage = pkgs.callPackage ../pkgs/closure-2-erofs.nix {
    closure = closureInfo;
    contexts = "${pkgs.selinux-refpolicy}/etc/selinux/refpolicy/contexts/files";
  };

  hasVmFs = options.virtualisation ? fileSystems;
  withFs = defs: if hasVmFs then { virtualisation.fileSystems = defs; } else { fileSystems = defs; };

  baseFileSystems =
    if hasVmFs then base.config.virtualisation.fileSystems else base.config.fileSystems;

  hasStoreMount = baseFileSystems ? "/nix/store";

  realStoreDir = toString cfg.realStoreDir;
  metadataDir = toString cfg.metadataDir;

  sysroot = "/sysroot";
  inSysroot = p: "${sysroot}${p}";

  imagePath = inSysroot "${realStoreDir}/${builtins.baseNameOf erofsImage}";

  mountUnit = p: "${utils.escapeSystemdPath (inSysroot p)}.mount";
  sysrootMountUnit = "${utils.escapeSystemdPath sysroot}.mount";
in
{
  options.security.selinux.store = {
    enable = mkOption {
      type = types.bool;
      default = config.security.selinux.enable;
      description = "A hidden enable state used for disabling this module to prevent infinite filesystem";
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
    contextsDir = mkOption { };

    # The system paths.
    closure = mkOption {
      type = types.listOf types.package; # Either a derivation or a store path. Which is what we want.
      default = [ base.config.system.build.toplevel ]; # This should be more than enough for most cases.
      defaultText = literalExpression "[ config_without_senix_module.system.build.toplevel ]";
      description = ''
        A list of closures to be described by the nixos system
      '';
    };
  };

  config = lib.mkIf cfg.enable (
    lib.mkMerge [
      # Assertions
      (
        let
          asPath = p: /. + p;

          isNormalised = p: lib.hasPrefix "/" p && toString (asPath p) == p;

          components = p: lib.path.subpath.components (lib.path.splitRoot (asPath p)).subpath;

          isRootLevel = p: isNormalised p && lib.length (components p) == 1;

          existingMountPoints = lib.mapAttrsToList (_: fs: fs.mountPoint) baseFileSystems;

          dirAssertions = name: p: {
            assertions = [
              {
                assertion = isRootLevel p;
                message = ''
                  security.selinux.store.${name} must be a normalised root level path such as
                  "/.nix-store", but it is set to "${p}".
                '';
              }
              {
                assertion = !(lib.elem p existingMountPoints);
                message = ''
                  security.selinux.store.${name} ("${p}") is already used as the mount point
                  of another file system.
                '';
              }
            ];
          };
        in
        lib.mkMerge [
          (dirAssertions "realStoreDir" realStoreDir)
          (dirAssertions "metadataDir" metadataDir)
          {
            assertions = [
              {
                assertion = realStoreDir != metadataDir;
                message = ''
                  security.selinux.store.realStoreDir and security.selinux.store.metadataDir
                  must be different paths, but both are set to "${realStoreDir}".
                '';
              }
              {
                assertion = config.security.selinux.enable;
                message = "security.selinux.store.enable requires security.selinux.enable.";
              }
            ];
          }
        ]
      )

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
        boot.initrd.supportedFilesystems = [ "erofs" ];
        boot.initrd.kernelModules = [
          "loop"
          "erofs"
          "overlay"
        ];

        # Make sure the image is in the closure since we only reference by string
        system.extraDependencies = [ erofsImage ];
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
          depends = [ realStoreDir ];
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
        "/nix/store" = {
          mountPoint = cfg.realStoreDir;
          # We need the contents from the store at boot time.
          neededForBoot = true;
        };
      }))

      # If we need a bind unit, then we have to bind the real store using a initrd service because
      # we can't do it through nix modules because of ordering issues. Because of various other
      # fuckery we can't depend on the fileSystem module.
      (lib.mkIf (!hasStoreMount) {
        boot.initrd.systemd.services.bind-real-store = {
          wantedBy = [ "initrd-root-fs.target" ];
          requires = [ sysrootMountUnit ];
          after = [ sysrootMountUnit ];
          before = [
            "initrd-root-fs.target"
            (mountUnit metadataDir)
            (mountUnit "/nix/store")
          ];
          unitConfig.DefaultDependencies = false;
          serviceConfig = {
            Type = "oneshot";
            RemainAfterExit = true;
          };
          script = ''
            mkdir -p ${inSysroot "/nix/store"} ${inSysroot realStoreDir}
            mount --bind ${inSysroot "/nix/store"} ${inSysroot realStoreDir}
            mount --make-private ${inSysroot realStoreDir}
          '';
        };
      })

      # TODO: Investigate a initrd mount instead of a service? We may have to bind elsewhere i.e. /nix instead of /nix/store directly
      # Something like this, but i am not sure if I like binding to /nix at the top level... maybe it's ok?
      # Might mess with /nix/var which messes with other things... Might be ok since I think var is written by the daemon tho not sure.
      # (lib.mkIf (!hasStoreMount) {
      #   boot.initrd.systemd.mounts = [
      #     {
      #       what = inSysroot "/nix";
      #       where = inSysroot realStoreDir;
      #       type = "none";
      #       options = "bind,private";
      #       wantedBy = [ "initrd-root-fs.target" ];
      #       requires = [ sysrootMountUnit ];
      #       after = [ sysrootMountUnit ];
      #       before = [
      #         "initrd-root-fs.target"
      #         (mountUnit metadataDir)
      #         (mountUnit "/nix/store")
      #       ];
      #       unitConfig.DefaultDependencies = false;
      #     }
      #   ];
      # })
    ]
  );
}
