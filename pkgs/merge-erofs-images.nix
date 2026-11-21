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
    (erofs-utils.overrideAttrs { selinuxSupport = true; })
    coreutils
  ];

  dontUnpack = true;
  dontConfigure = true;
  dontBuild = true;

  installPhase = ''
    runHook preInstall

    # REBUILD MODE: use clean-data (https://man.archlinux.org/man/extra/erofs-utils/mkfs.erofs.1.en#REBUILD)
    mkfs.erofs --clean=data -zlz4 -T 0 \
      -U 00000000-0000-0000-0000-000000000000 \
      "$out" ${lib.escapeShellArgs (lib.sort (a: b: a < b) (map toString images))}

    runHook postInstall
  '';

  meta = {
    platforms = lib.platforms.linux;
  };
})
