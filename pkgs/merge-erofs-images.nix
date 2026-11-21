{
  lib,
  stdenvNoCC,
  erofs-utils,
  coreutils,
}:
{ images }:
stdenvNoCC.mkDerivation (finalAttrs: {
  pname = "erofs-image-merged";
  version = "0.1.0";

  nativeBuildInputs = [
    (erofs-utils.override { selinuxSupport = true; })
    coreutils
  ];

  dontUnpack = true;
  dontConfigure = true;
  dontBuild = true;

  installPhase = ''
    runHook preInstall

    # REBUILD MODE: use --clean=data so we have a copy (https://man.archlinux.org/man/extra/erofs-utils/mkfs.erofs.1.en#REBUILD)
    # Perhaps consider blob referencing them? Not sure if that would speed things up.
    mkfs.erofs --clean=data -zlz4 -T 0 \
      -U 00000000-0000-0000-0000-000000000000 \
      "$out" ${lib.escapeShellArgs (lib.sort (a: b: a < b) (map toString images))}

    runHook postInstall
  '';

  meta = {
    platforms = lib.platforms.linux;
  };
})
