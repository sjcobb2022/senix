{
  pkgs,
  self,
  ...
}: let
  inherit
    (import (pkgs.path + "/nixos/tests/ssh-keys.nix") pkgs)
    snakeOilPrivateKey
    snakeOilPublicKey
    ;

  deployable = {
    services.openssh.enable = true;
    users.users.root.openssh.authorizedKeys.keys = [snakeOilPublicKey];
  };
in
  pkgs.testers.nixosTest {
    name = "remote-deployment";

    nodes = {
      machine1 = {nodes, ...}: {
        nix.settings.experimental-features = ["nix-command"];
        virtualisation.additionalPaths = [
          nodes.target.system.build.toplevel
        ];
      };

      machine2 = {
        imports = [deployable];
      };

      target = {
        lib,
        nodes,
        ...
      }: {
        imports = [
          deployable
          self.nixosModules.default
        ];

        nixpkgs.overlays = [
          self.overlays.default
        ];

        security.selinux.enable = true;
        security.selinux.mode = "enforcing";

        networking.hostName = lib.mkForce "machine2";
        networking.interfaces.eth1.ipv4.addresses =
          lib.mkForce nodes.machine2.networking.interfaces.eth1.ipv4.addresses;
      };
    };

    testScript = {nodes, ...}: let
      toplevel = nodes.target.system.build.toplevel;
    in ''
      machine1.start()
      machine2.start()

      machine1.wait_for_unit("multi-user.target")
      machine2.wait_for_unit("sshd.service")
      machine2.wait_for_open_port(22)

      with subtest("exchange key material"):
        machine1.succeed(
            "mkdir -m 700 -p /root/.ssh/",
            "install -m 600 ${snakeOilPrivateKey} /root/.ssh/id_ecdsa",
            "ssh -o StricHostKeyChecking=accept-new root@machine2 true",
        )

      with subtest("deploy SELinux system from machine1 to machine2"):
        machine1.succeed("nix copy --to ssh://root@machine2 ${toplevel}")
        machine1.succeed(
            "ssh root@machine2 "
            "'nix-env -p /nix/var/profiles/system --set ${toplevel} && ${toplevel}/bin/swith-to-configuration boot'"
        )

      with subtest("reboot into deployed system"):
          machine2.shutdown()
          machine2.start()
          machine2.wait_for_unit("multi-user.target")
          assert machine2.succeed("readlink -f /run/current-system").strip() == "${toplevel}"

      with subtest("new system has SELinux enabled"):
          assert machine2.succeed("getenforce").strip() == "Enforcing"
          assert machine2.succeed("findmnt -no FSTYPE /nix/store").strip() == "overlay"
          machine2.wait_for_open_port(22)
          assert machine1.succeed("ssh root@machine2 getenforce").strip() == "Enforcing"
    '';
  }
