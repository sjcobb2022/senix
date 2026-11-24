{
  lib,
  runCommand,
  erofs-utils,
  coreutils,
}: {images}:
runCommand "erofs-2-image"
{
  nativeBuildInputs = [
    (erofs-utils.override {selinuxSupport = true;})
    coreutils
  ];

  meta.platforms = lib.platforms.linux;
}
''
  runHook preInstall

  # REBUILD MODE: use --clean=data so we have a copy
  # https://man.archlinux.org/man/extra/erofs-utils/mkfs.erofs.1.en#REBUILD
  # Perhaps consider blob referencing them? Not sure if that would speed things up.
  mkfs.erofs --clean=data -zlz4 -T 0 \
    -U 00000000-0000-0000-0000-000000000000 \
    "$out" ${lib.escapeShellArgs (lib.sort (a: b: a < b) (map toString images))}

  runHook postInstall
''
