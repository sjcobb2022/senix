final: prev: {
  # systemd = prev.systemd.override {
  #   withSelinux = true;
  # };

  # Get tests working: ref https://github.com/NixOS/nixpkgs/issues/570146
  swtpm = prev.swtpm.overrideAttrs (old: {
    doCheck = false;
  });
}
