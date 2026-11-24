final: prev: {
  selinux-refpolicy = prev.selinux-refpolicy.overrideAttrs (old: {
    pname = "selinux-refpolicy";

    # build monolithic so that we have file_contexts super file
    makeFlags = old.makeFlags ++ [
      "MONOLITHIC=y"
      "SETFILES=${final.lib.getExe' final.policycoreutils "setfiles"}"
    ];
  });

  # Get tests working: ref https://github.com/NixOS/nixpkgs/issues/570146
  swtpm = prev.swtpm.overrideAttrs {
    doCheck = false;
  };

  erofs-utils = prev.erofs-utils.override { selinuxSupport = true; };
}
