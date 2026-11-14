{
  lib,
  stdenvNoCC,
  erofs-utils,
  coreutils,
  findutils,
  closure,
  contexts,
}:
stdenvNoCC.mkDerivation (finalAttrs: {
  pname = "nix-closure-erofs";
  version = "0.1.0";

  nativeBuildInputs = [
    erofs-utils
    coreutils
    findutils
  ];
  dontUnpack = true;
  dontConfigure = true;
  dontBuild = true;

  installPhase = ''
    runHook preInstall

    root="$TMPDIR/root"
    mkdir -p "$root/nix/store"

    xargs -d '\n' -a ${closure}/store-paths \
      cp -r --no-dereference --attributes-only --preserve=mode \
         -t "$root/nix/store"

    mkfs.erofs -zlz4 -T 0 \
      --force-uid=0 --force-gid=0 \
      -U 00000000-0000-0000-0000-000000000000 \
      "$out" "$root"

    runHook postInstall
  '';

  # --file-contexts=${contexts} \

  meta = {
    description = "Reproducible EROFS image containing a Nix closure";
    platforms = lib.platforms.linux;
  };
})
