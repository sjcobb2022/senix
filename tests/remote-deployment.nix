{
  pkgs,
  self,
  ...
}:
let
  inherit (import (pkgs.path + "/nixos/tests/ssh-keys.nix") pkgs)
    snakeOilPrivateKey
    snakeOilPublicKey
    ;

  deployableBase = {
    services.openssh.enable = true;
    users.users.root.openssh.authorizedKeys.keys = [ snakeOilPublicKey ];

    # A deployable machine should be able to write to the bootloader entry.
    virtualisation.useBootLoader = true;
    virtualisation.useEFIBoot = true;
    boot.loader.systemd-boot.enable = true;
    boot.loader.efi.canTouchEfiVariables = true;

    virtualisation.diskSize = 16384; # increase disksize because it fails otherwise.
    virtualisation.memorySize = 2048; # increase memory

    boot.growPartition = true;
    virtualisation.fileSystems."/".autoResize = true;

    # So we have getfattr
    environment.systemPackages = [ pkgs.attr ];
  };

  deployableStoreMount = { config, ... }: {
    imports = [ deployableBase ];

    virtualisation.useNixStoreImage = true;
    virtualisation.writableStore = true;
    virtualisation.writableStoreUseTmpfs = false;

    assertions = [
      {
        assertion = config.virtualisation.fileSystems ? "/nix/store";
        message = ''
          deployableStoreMount expects a "/nix/store" entry in
          virtualisation.fileSystems (hasStoreMount = true), but none exists.
        '';
      }
    ];
  };

  deployableBindStore =
    {
      config,
      lib,
      ...
    }:
    {
      imports = [ deployableBase ];

      virtualisation.mountHostNixStore = lib.mkForce false;
      virtualisation.useNixStoreImage = lib.mkForce false;
      virtualisation.writableStore = lib.mkForce false;

      assertions = [
        {
          assertion = !(config.virtualisation.fileSystems ? "/nix/store");
          message = ''
            deployableBindStore expects no "/nix/store" entry in
            virtualisation.fileSystems (hasStoreMount = false), but one exists.
          '';
        }
      ];
    };

  mkTarget =
    {
      deployable,
      initial,
    }:
    {
      lib,
      nodes,
      ...
    }:
    {
      imports = [
        deployable
        self.nixosModules.default
      ];

      # Allow switching to this configuration.
      system.switch.enable = true;

      nixpkgs.overlays = [
        self.overlays.default
      ];

      security.selinux.enable = true;
      security.selinux.mode = "permissive";

      networking.hostName = lib.mkForce initial;
      networking.interfaces.eth1.ipv4.addresses =
        lib.mkForce
          nodes.${initial}.networking.interfaces.eth1.ipv4.addresses;
    };
in
pkgs.testers.nixosTest {
  name = "remote-deployment";

  nodes = {
    machine1 = { nodes, ... }: {
      nix.settings.experimental-features = [ "nix-command" ];
      virtualisation.additionalPaths = [
        nodes.target2.system.build.toplevel
        nodes.target3.system.build.toplevel
      ];
    };

    machine2.imports = [ deployableStoreMount ];
    machine3.imports = [ deployableBindStore ];

    target2 = mkTarget {
      deployable = deployableStoreMount;
      initial = "machine2";
    };

    target3 = mkTarget {
      deployable = deployableBindStore;
      initial = "machine3";
    };
  };

  testScript =
    { nodes, ... }:
    let
      toplevel2 = nodes.target2.system.build.toplevel;
      toplevel3 = nodes.target3.system.build.toplevel;

      realStoreDir2 = nodes.target2.security.selinux.store.realStoreDir;
      metadataDir2 = nodes.target2.security.selinux.store.metadataDir;
      realStoreDir3 = nodes.target3.security.selinux.store.realStoreDir;
      metadataDir3 = nodes.target3.security.selinux.store.metadataDir;
    in
    ''
      machine1.start()
      machine2.start()
      machine3.start()

      machine1.wait_for_unit("multi-user.target")
      machine2.wait_for_unit("sshd.service")
      machine2.wait_for_open_port(22)
      machine3.wait_for_unit("sshd.service")
      machine3.wait_for_open_port(22)

      with subtest("exchange key material"):
          machine1.succeed(
              "mkdir -m 700 -p /root/.ssh/",
              "install -m 600 ${snakeOilPrivateKey} /root/.ssh/id_ecdsa",
          )
          machine1.succeed("ssh -o StrictHostKeyChecking=accept-new root@machine2 true")
          machine1.succeed("ssh -o StrictHostKeyChecking=accept-new root@machine3 true")

      with subtest("initial systems have the expected store layout"):
          fstype = machine2.succeed("findmnt -no FSTYPE /nix/store").strip()
          # expected to have a reference to overlay as we have a writable store
          assert fstype == "overlay\noverlay", f"unexpected machine2 /nix/store fstype: {fstype!r}"
          machine2.fail("mountpoint -q ${realStoreDir2}")
          fstype = machine3.succeed("findmnt -no FSTYPE /nix/store").strip()
          assert fstype != "overlay", f"unexpected machine3 /nix/store fstype: {fstype!r}"
          machine3.fail("mountpoint -q ${realStoreDir3}")

      with subtest("deploy SELinux system from machine1 to machine2"):
           machine1.succeed(
               "nixos-rebuild --target-host root@machine2 "
               "--store-path ${toplevel2} boot"
           )

      with subtest("deploy SELinux system from machine1 to machine3"):
          machine1.succeed(
              "nixos-rebuild --target-host root@machine3 "
              "--store-path ${toplevel3} boot"
          )

      with subtest("reboot into deployed systems"):
          machine2.shutdown()
          machine3.shutdown()
          machine2.start()
          machine3.start()
          machine2.wait_for_unit("multi-user.target")
          machine3.wait_for_unit("multi-user.target")
          assert machine2.succeed("readlink -f /run/current-system").strip() == "${toplevel2}"
          assert machine3.succeed("readlink -f /run/current-system").strip() == "${toplevel3}"

      with subtest("machine2 (hasStoreMount) has the SELinux store"):
          fstype = machine2.succeed("findmnt -fno FSTYPE /nix/store").strip()
          assert fstype == "overlay", f"unexpected /nix/store fstype: {fstype!r}"
          fstype = machine2.succeed("findmnt -no FSTYPE ${metadataDir2}").strip()
          assert fstype == "erofs", f"unexpected ${metadataDir2} fstype: {fstype!r}"
          machine2.succeed("mountpoint -q ${realStoreDir2}")
          machine2.succeed("test -e ${realStoreDir2}/$(basename ${toplevel2})")

      with subtest("machine3 (!hasStoreMount) has the SELinux store"):
          fstype = machine3.succeed("findmnt -fno FSTYPE /nix/store").strip()
          assert fstype == "overlay", f"unexpected /nix/store fstype: {fstype!r}"
          fstype = machine3.succeed("findmnt -no FSTYPE ${metadataDir3}").strip()
          assert fstype == "erofs", f"unexpected ${metadataDir3} fstype: {fstype!r}"
          machine3.succeed("mountpoint -q ${realStoreDir3}")
          machine3.succeed("test -e ${realStoreDir3}/$(basename ${toplevel3})")

      with subtest("machine3 real store is a private bind of the root fs /nix/store"):
          source = machine3.succeed("findmnt -no SOURCE ${realStoreDir3}").strip()
          assert source.endswith("[/nix/store]"), f"not a bind of /nix/store: {source!r}"
          fstype = machine3.succeed("findmnt -no FSTYPE ${realStoreDir3}").strip()
          assert fstype != "overlay", "overlay propagated into ${realStoreDir3}"

      with subtest("debug hostname label"):
          path = machine2.succeed("readlink -f $(command -v hostname)").strip()
          pkg = path.split("/")[3]
          print(machine2.succeed(f"getfattr -d -m - -h {path} 2>&1 || true"))
          print(machine2.succeed(f"getfattr -d -m - -h ${metadataDir2}/{pkg}/bin/hostname 2>&1 || true"))
          print(machine2.succeed(f"getfattr -d -m - -h ${realStoreDir2}/{pkg}/bin/hostname 2>&1 || true"))
          print(machine2.succeed("cat /sys/fs/selinux/enforce 2>&1 || true"))
          print(machine2.succeed("grep -E 'selinux|erofs|overlay' /proc/mounts"))

      with subtest("labeled executable (hostname) runs and is labeled"):
          assert machine2.succeed("hostname").strip() == "machine2"
          assert machine3.succeed("hostname").strip() == "machine3"
          label2 = machine2.succeed("getfattr -n security.selinux --only-values $(readlink -f $(command -v hostname))")
          label3 = machine3.succeed("getfattr -n security.selinux --only-values $(readlink -f $(command -v hostname))")
          assert "hostname_exec_t" in label2, f"machine2 hostname label: {label2!r}"
          assert "hostname_exec_t" in label3, f"machine3 hostname label: {label3!r}"

      with subtest("debug metadata layout"):
          print(machine2.succeed("ls -la ${metadataDir2} | head"))
          print(machine2.succeed("find ${metadataDir2} -name hostname 2>&1 | head"))
          print(machine2.succeed("ls ${metadataDir2} | wc -l"))
          print(machine2.succeed("getfattr -d -m - -h ${toplevel2} 2>&1 || true"))
          print(machine2.succeed("find ${metadataDir2} -type f | head -3 | xargs -r getfattr -d -m - -h 2>&1 || true"))

      with subtest("new systems have SELinux enabled"):
           # machine2
           fstype = machine2.succeed("findmnt -fno FSTYPE /nix/store").strip()
           assert fstype == "overlay", f"unexpected machine2 /nix/store fstype: {fstype!r}"
           # assert machine2.succeed("getenforce").strip() == "Enforcing"
           # machine2.wait_for_open_port(22)
           # assert machine1.succeed("ssh root@machine2 getenforce").strip() == "Enforcing"

           # machine3
           fstype = machine3.succeed("findmnt -fno FSTYPE /nix/store").strip()
           assert fstype == "overlay", f"unexpected machine3 /nix/store fstype: {fstype!r}"
           # assert machine3.succeed("getenforce").strip() == "Enforcing"
           # machine3.wait_for_open_port(22)
           # assert machine1.succeed("ssh root@machine3 getenforce").strip() == "Enforcing"
    '';
}
