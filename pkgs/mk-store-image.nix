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
    (erofs-utils.overrideAttrs {selinuxSupport = true;})
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

  # QUICK IDEA SKETCH:
  # use mkfs.erofs to make a erofs for every package in a closure, and then use REBUILD MODE (https://man.archlinux.org/man/extra/erofs-utils/mkfs.erofs.1.en#REBUILD)
  # This would allow us to be really parallel since no package should be dependant on another, so we can just apply however we need.
  # In order to combine each one.

  # --file-contexts=${contexts} \

  # If this is the case, we should take the appropriate measures to see in terms of performance, whether making an additional erofs for each package is suitable. I mean realistically, those would be built and cached as appropraite on the build server andd then they can be made nicer, however obviously also has the cost of additional storage wherever they are. Though I don't think a bunch of empty files with xattrs should be terrible.

  meta = {
    description = "Reproducible EROFS image containing a Nix closure";
    platforms = lib.platforms.linux;
  };
})
