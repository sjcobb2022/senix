{
  description = "SELinux support for NixOS";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    flake-compat = {
      url = "github:NixOS/flake-compat";
      flake = false;
    };
  };

  outputs = {
    self,
    nixpkgs,
    ...
  }: let
    forEachSystem = nixpkgs.lib.genAttrs [
      "x86_64-linux"
      "aarch64-darwin"
    ];

    forEachPkgs = f: forEachSystem (sys: f nixpkgs.legacyPackages.${sys});

    mkTest = path:
      forEachPkgs (pkgs:
        import path {
          inherit pkgs;
          inherit self;
        });
  in {
    overlays.senix = import ./overlay.nix;
    overlays.default = self.overlays.senix;

    nixosModules.senix = import ./module.nix;
    nixosModules.default = self.nixosModules.senix;

    # WARNING: THIS MODULE IS NOT WORKING AND SO TESTS WILL NOT WORK
    nixosTests = {
      selinux = mkTest ./tests/selinux.nix;
      remote-deployment = mkTest ./tests/remote-deployment.nix;
      build-in-vm = mkTest ./tests/build-image-in-vm.nix;
    };
  };
}
