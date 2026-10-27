# NOTE: Is this strictly something that we want in the long run? Do we want to be able to dynamically build within a system?
# To some extent it would be nicer if we didn't and just generated the erofs once.
{
  pkgs,
  self,
  ...
}: let
  testDerivation = ./test-derivation.nix;
in
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

      environment.etc."senix/test.nix".source = testDerivation;
    };

    # We can build a package in the nix store and then execute it (without selinux denying it)
    testScript = ''
      machine.start()

      machine.wait_for_unit("multi-user.target")

      machine.succeed("getenforce")

      with subtest("a derivation can be built offline"):
          out = machine.succeed("nix-build --no-out-link /etc/senix/test.nix").strip()
          assert out.startswith("/nix/store"), out

      with subtest("build is in the physical store and the overlay"):
          machine.succeed("test -x /.nix-store/" + out.removeprefix("/nix/store") + "/bin/test")
          machine.succeed(f"test -x {out}/bin/test")

      with subtest("the built output can be executed"):
          assert machine.succeed(f"{out}/bin/test") == "test"
    '';
  }
