{
  lib,
  stdenvNoCC,
  erofs-utils,
  coreutils,
}:
{
  path,
  context,
}:
let
  base = builtins.unsafeDiscardStringContext (baseNameOf path);
in
stdenvNoCC.mkDerivation (finalAttrs: {
  pname = "erofs-image-${base}";
  version = "0.1.0";

  nativeBuildInputs = [
    (erofs-utils.overrideAttrs { selinuxSupport = true; })
    coreutils
  ];

  dontUnpack = true;
  dontConfigure = true;
  dontBuild = true;

  installPhase = ''
    runHook preInstall


    root="$TMPDIR/root"
    mkdir -p "$root/nix/store"
    cp -r --no-dereference --attributes-only --preserve=mode \
      ${path} "$root/nix/store/"

    mkfs.erofs -zlz4 -T 0 \
      --force-uid=0 --force-gid=0 \
      -U 00000000-0000-0000-0000-000000000000 \
      --file-contexts=${context} \
      "$out" "$root"

    runHook postInstall
  '';

  meta = {
    platforms = lib.platforms.linux;
  };
})
