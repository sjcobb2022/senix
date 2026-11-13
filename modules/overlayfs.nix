{
  config,
  lib,
  pkgs,
  extendModules,
  options,
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

  erofsImage = pkgs.callPackage ../pkgs/mk-store-image.nix {
    closure = closureInfo;
    contexts = null;
  };

  hasVmFs = options.virtualisation ? fileSystems;
  withFs = defs:
    if hasVmFs
    then {virtualisation.fileSystems = defs;}
    else {fileSystems = defs;};

  hasStoreMount = base.config.fileSystems ? "/nix/store";
in {
  options.security.selinux.store = {
    enable = mkOption {
      type = types.bool;
      default = false;
      internal = true;
    };

    # The actual location of the nix store
    realStoreDir = mkOption {
      type = types.str;
      default = "/.nix-store";
    };

    metadataDir = mkOption {
      type = types.str;
      default = "/.selinux-metadata";
    };

    # The location of the stored contexts.
    contextsDir = mkOption {};

    # The system paths.
    closure = mkOption {
      type = types.listOf types.package; # Either a derivation or a store path. Which is what we want.
      default = [base.config.system.build.toplevel]; # This should be more than enough for most cases.
      defaultText = literalExpression "[ config.system.build.toplevel ]";
    };
  };

  config = lib.mkIf cfg.enable (lib.mkMerge [
    {
      # Point it to the right store. For builders etc.
      # For local interactions, we need to know where the actual store is.
      # works with:
      #   - local store
      #   - experimental local overlay store
      #   - experimental mounted ssh store
      #   - local daemon store
      nix.settings.store = "auto?real=${cfg.realStoreDir}";

      # Need erofs loop and overlay for the stores
      boot.initrd.supportedFilesystems = ["erofs"];
      boot.initrd.kernelModules = ["loop" "erofs" "overlay"];
    }

    (withFs
      {
        ${cfg.metadataDir} = {
          device = "${erofsImage}";
          fsType = "erofs";
          options = ["loop" "ro"];
          neededForBoot = true;
        };

        "/nix/store-selinux" = {
          mountPoint = "/nix/store";
          device = "overlay";
          fsType = "overlay";
          neededForBoot = true;
          options = ["metacopy=on" "redirect_dir=on"];
          depends = [cfg.metadataDir cfg.realStoreDir];
          # realstoreDir should be dataonly
          overlay.lowerdir = ["${cfg.metadataDir}:" cfg.realStoreDir];
        };
      })

    (withFs
      # If the configuration defines /nix/store, then we can change the mountpoint.
      (lib.mkIf hasStoreMount {
        "/nix/store".mountPoint = cfg.realStoreDir;
      }))

    (withFs
      (lib.mkIf (!hasStoreMount) {
        # expose it as realStoreDir
        ${cfg.realStoreDir} = {
          device = "/nix/store";
          options = ["bind"];
          neededForBoot = true;
        };
      }))

    {
      # TODO: Remove this testing stuff
      # virtualisation.fileSystems."/nix/store".mountPoint = lib.mkDefault cfg.realStoreDir;

      # fileSystems."/nix/store" = lib.mkIf (base.config.fileSystems ? "/nix/store") {
      #   mountPoint = cfg.realStoreDir;
      # };

      # EMPTY FOR TESTING

      # virtualisation.fileSystems.${cfg.metadataDir} = {
      #   device = "${erofsImage}";
      #   fsType = "erofs";
      #   options = ["loop" "ro"];
      #   neededForBoot = true;
      # };

      # fileSystems.${cfg.metadataDir} = {
      #   device = "${erofsImage}";
      #   fsType = "erofs";
      #   options = ["loop" "ro"];
      #   neededForBoot = true;
      # };

      # virtualisation.fileSystems."/nix/store-selinux" = {
      #   mountPoint = "/nix/store";
      #   device = "overlay";
      #   fsType = "overlay";
      #   neededForBoot = true;
      #   options = [
      #     "metacopy=on"
      #     "redirect_dir=on"
      #   ];
      #   # need: overlayfs,
      #   depends = [cfg.realStoreDir cfg.metadataDir];
      #   overlay.lowerdir = [
      #     "${cfg.metadataDir}:"
      #     cfg.realStoreDir
      #   ];
      # };

      # We can just change the mount point of the configured nix store to point to a new location.
      # e.g. fileSystems."/nix/store".mountPoint = "/.nix-store";
      #      fileSystems."/nix/selinux-store".mountPoint = "/nix/store";

      # We have 2 solutions here. Implement our own store, or perhaps
      # use the experimental-local-overlay-store.
      #
      # Leaning towards the experimental-overlay-store here.
      # Just need to make sure that it is mounted properly.
      #
      # If /nix/store is already an overlayfs... what should we do.
      #
      # One solution could be to use an overlay over the config,
      # and provide which the overlay moves the /nix/store
      # config to a new path, and sets the stuff for the module.

      # system.build.selinuxStoreImage = cfg.image;
    }
  ]);
}
