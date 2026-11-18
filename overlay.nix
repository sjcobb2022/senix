final: prev: {
  systemd = prev.systemd.override {
    withSelinux = true;
  };

  swtpm = prev.swtpm.overrideAttrs (old: {
    doCheck = false;
  });
}
