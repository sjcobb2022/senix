{
  lib,
  runCommand,
  erofs-utils,
}: {
  path,
  context,
}:
runCommand "context-2-erofs"
{
  nativeBuildInputs = [(erofs-utils.override {selinuxSupport = true;})];
  meta.platforms = lib.platforms.linux;
}
''
  root="$TMPDIR/root"
  mkdir -p "$root"
  cp -r --no-dereference --attributes-only --preserve=mode \
    ${path} "$root"

  mkfs.erofs -zlz4 -T 0 \
    --force-uid=0 --force-gid=0 \
    -U 00000000-0000-0000-0000-000000000000 \
    --file-contexts=${context} \
    "$out" "$root"
''
