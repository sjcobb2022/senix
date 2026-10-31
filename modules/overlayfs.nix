{
  config,
  lib,
  pkgs,
  options,
  ...
}: let
  inherit (lib) mkOption types literalExpression;

  cfg = config.security.selinux.store;

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
    # The location of the stored contexts.
    contextsDir = mkOption {};

    # The system paths.
    closure = mkOption {
      type = types.listOf types.package; # Either a derivation or a store path. Which is what we want.
      default = [config.system.build.toplevel];
      defaultText = literalExpression "[ config.system.build.toplevel ]";
    };

    metadaDataDir = mkOption {};
  };

  config = {
    assertions = [
      # {
      #   assertion = options.fileSystems."/nix/store".definitions == [];
      #   message = "Cannot define /nix/store manually in filesystem. Use ${cfg.realStoreDir} instead.";
      # }
    ];

    # Point it to the right store. For builders etc.
    # For local interactions, we need to know where the actual store is.
    # works with:
    #   - local store
    #   - experimental local overlay store
    #   - experimental mounted ssh store
    #   - local daemon store
    nix.settings.store = "auto?real=${cfg.realStoreDir}";

    fileSystems."/nix/store" = {
      overlay = {
        lowerdir = [
          "/nix/.selinux-metadata:"
        ];
      };
    };

    # This... should help with getting sysroot etc prefixed where necessary.
    virtualisation.fileSystems."/nix/store" = {
      overlay = {
        # Make it before so it get's concatenated correctly...
        # This is the most braindead hack imaginable and is awful and I would never reccomend this, butttt.....
        lowerdir = lib.mkBefore [
          "/nix/.selinux-metadata:"
        ];
      };
    };

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
