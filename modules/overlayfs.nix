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

    # Need to find a way to add our own metdata that would make things a lot easier.
    fileSystems."/nix/store" = {
      overlay = {
        lowerdir = [
          "/nix/.selinux-metadata:"
        ];
      };
    };

    virtualisation.fileSystems."/nix/store" = {
      overlay = {
        # Make it before so it get's concatenated correctly...
        # This is the most braindead hack imaginable and is awful and I would never reccomend this, butttt.....
        lowerdir = lib.mkBefore [
          "/nix/.selinux-metadata:"
        ];
      };
    };

    # Mount with metacopy (double colon)

    # Because we are handling the lowerdir manually, that does mean that I think initrd will not work.
    # Or at least, we will not have selinux in initrd. Since we are not doing stuff in respect to that
    # And the nix store probably won't be mounted. And we would have to also label everything in
    # config.system.path or something.
    # Ideally since it is kinda a /sysroot overlay thing anyway, we would just kinda inject it in there somehow.

    system.build.selinuxStoreImage = cfg.image;
  };
}
