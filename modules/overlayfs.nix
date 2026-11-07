{
  config,
  lib,
  pkgs,
  options,
  ...
}: let
  inherit (lib) mkOption types literalExpression;

  cfg = config.security.selinux.store;

  realStoreDir = cfg.realStoreDir;

  closureInfo = pkgs.closureInfo {
    rootPaths = cfg.closure;
  };
in {
  options.security.selinux.store = {
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
      default = [config.system.build.toplevel]; # This should be more than enough for most cases.
      defaultText = literalExpression "[ config.system.build.toplevel ]";
    };
  };

  config = {
    # Probably need some good assertions here.
    assertions = [
    ];

    # Point it to the right store. For builders etc.
    # For local interactions, we need to know where the actual store is.
    # works with:
    #   - local store
    #   - experimental local overlay store
    #   - experimental mounted ssh store
    #   - local daemon store
    nix.settings.store = "auto?real=${cfg.realStoreDir}";

    # If the configuration defines /nix/store, then we can change the mountpoint.
    virtualisation.fileSystems."/nix/store" = lib.mkIf (config.virtualisation.fileSystems ? "/nix/store") {
      mountPoint = cfg.realStoreDir;
    };

    fileSystems."/nix/store" = lib.mkIf (config.fileSystems ? "/nix/store") {
      mountPoint = cfg.realStoreDir;
    };

    # EMPTY FOR TESTING
    # virtualisation.fileSystems.${cfg.metadataDir} = lib.mkIf config.virtualisation.useBootLoader {
    #   device = "none";
    #   fsType = "tmpfs";
    #   neededForBoot = true;
    #   options = ["mode=0755"];
    # };

    virtualisation.fileSystems."/nix/store-selinux" = {
      mountPoint = "/nix/store";
      device = "overlay";
      fsType = "overlay";
      neededForBoot = true;
      # need: overlayfs,
      depends = [cfg.realStoreDir cfg.metadataDir];
      overlay.lowerdir = [
        "${cfg.metadataDir}:"
        cfg.realStoreDir
      ];
    };

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

    system.build.selinuxStoreImage = cfg.image;
  };
}
