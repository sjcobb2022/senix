{
  lib,
  stdenvNoCC,
  erofs-utils,
  gnutar,
  closure,
  contexts,
}:
stdenvNoCC.mkDerivation (finalAttrs: {
  pname = "nix-closure-erofs";
  version = "0.1.0";

  nativeBuildInputs = [
    erofs-utils
    gnutar
  ];

  dontUnpack = true;
  dontConfigure = true;
  dontBuild = true;

  installPhase = ''
    runHook preinstall

    # Store paths relative to /nix/store, one per line
    sed 's,^/nix/store/,,' ${closure}/store-paths > store-paths.relative

    # Deterministic tar stream of the closure, piped straight into mkfs.erofs
    tar \
      --create \
      --file=- \
      --directory=/nix/store \
      --files-from=store-paths.relative \
      --format=pax \
      --sort=name \
      --mtime=@0 |
    mkfs.erofs \
      -zlz4 \
      -T 0 \
      --file-contexts=${contexts} \
      -U 00000000-0000-0000-0000-000000000000 \
      "$out" -

    runHook postInstall
  '';

  meta = {
    description = "Reproducible EROFS image containing a Nix closure";
    platforms = lib.platforms.linux;
  };
})
