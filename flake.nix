{
  description = "SELinux support for NixOS";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    flake-compat = {
      url = "github:NixOS/flake-compat";
      flake = false;
    };
  };

  nixConfig = {
    extra-substituters = [ "https://senix.cachix.org" ];
    extra-trusted-public-keys = [
      "senix.cachix.org-1:2N3Djfr0yy4tZfhKm5BCWmXhVd3V29IH0W1CG9q3XQo="
    ];
  };

  outputs =
    {
      self,
      nixpkgs,
      ...
    }:
    let
      inherit (nixpkgs) lib;
      forEachSystem = nixpkgs.lib.genAttrs [
        "x86_64-linux"
        "aarch64-darwin"
      ];

      # Apply overlay to our custom packages to make things easier, might roll this back and make it specific again at some point.
      forEachPkgs =
        f:
        forEachSystem (
          sys:
          let
            pkgs = nixpkgs.legacyPackages.${sys}.extend self.overlays.default;
          in
          f pkgs
        );

      tests = {
        selinux = ./tests/selinux.nix;
        remote-deployment = ./tests/remote-deployment.nix;
        # build-in-vm = ./tests/build-image-in-vm.nix;
        erofs-generation = ./tests/erofs-generation.nix;
      };
    in
    {
      overlays.default = import ./overlay.nix;

      nixosModules.senix = import ./modules/selinux.nix;
      nixosModules.overlayfs = import ./modules/overlayfs.nix;
      nixosModules.userspace = import ./modules/userspace.nix;
      nixosModules.default = {
        imports = [
          self.nixosModules.senix
          self.nixosModules.overlayfs
          self.nixosModules.userspace
        ];
      };

      # WARNING: THESE TESTS ARE ONLY PARTIALLY WORKING AND ARE UNDER DEVELOPMENT
      checks = forEachPkgs (pkgs: lib.mapAttrs (_: path: import path { inherit pkgs self; }) tests);

      formatter = forEachPkgs (pkgs: pkgs.nixfmt-tree);
    };
}
