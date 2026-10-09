{
  pkgs,
  self,
  ...
}:
pkgs.testers.nixosTest {
  name = "selinux";

  nodes.machine = {
    imports = [
      self.nixosModules.default
    ];

    nixpkgs.overlays = [
      self.overlays.default
    ];

    security.selinux.enable = true;
    security.selinux.mode = "enforcing";
  };

  # We can build a package in the nix store and then execute it (without selinux denying it)
  testScript = ''
    machine.start()

    machine.wait_for_unit("multi-user.target")

    machine.succeed("getenforce")

    machine.succeed("nix build nixpkgs#hello --no-link --print-out-paths > /tmp/hello-path")
    machine.succeed("$(cat /tmp/hello-path)/bin/hello")
  '';
}
