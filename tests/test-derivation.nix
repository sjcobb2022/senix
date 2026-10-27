{pkgs ? import <nixpkgs> {}}:
pkgs.runCommand "senix-test" {} ''
  mkdir -p "$out/bin"
  cat > "$out/bin/test" <<'EOF'
  #!${pkgs.runtimeShell}
  echo test
  EOF
  chmod +x "$out/bin/test"
''
