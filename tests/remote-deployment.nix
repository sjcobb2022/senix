{
  pkgs,
  self,
  ...
}:
pkgs.testers.nixosTest {
  name = "remote-deployment";

  nodes = {
    machine1 = {pkgs, ...}: {
      environment.systemPackages = [
        pkgs.nix
        pkgs.openssh
      ];
    };

    machine2 = {pkgs, ...}: {
      imports = [
        self.nixosModules.default
      ];

      nixpkgs.overlays = [
        self.overlays.default
      ];

      services.openssh.enable = true;
    };
  };

  testScript = ''
    machine1.start()
    machine2.start()

    machine1.wait_for_unit("multi-user.target")
    machine2.wait_for_unit("sshd.service")

    # TODO: Exchange key material

    # TODO: Deploy SELinux image from machine1

    # TODO: Reboot machine2


    # Remote deployed should be enforced.
    machine2.succeed("getenforce")
  '';
}
