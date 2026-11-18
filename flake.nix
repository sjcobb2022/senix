{
  description = "SELinux support for NixOS";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    flake-compat = {
      url = "github:NixOS/flake-compat";
      flake = false;
    };
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

      forEachPkgs = f: forEachSystem (sys: f nixpkgs.legacyPackages.${sys});

      tests = {
        selinux = ./tests/selinux.nix;
        remote-deployment = ./tests/remote-deployment.nix;
        build-in-vm = ./tests/build-image-in-vm.nix;
      };
    in
    {
      overlays.senix = import ./overlay.nix;
      overlays.default = self.overlays.senix;

      nixosModules.senix = import ./modules/selinux.nix;
      nixosModules.overlayfs = import ./modules/overlayfs.nix;
      nixosModules.default = self.nixosModules.senix;

      # WARNING: THESE TESTS ARE NOT WORKING AND ARE UNDER DEVELOPMENT
      checks = forEachPkgs (pkgs: lib.mapAttrs (_: path: import path { inherit pkgs self; }) tests);

      formatter = forEachPkgs (pkgs: pkgs.nixfmt-tree);
    };
}
