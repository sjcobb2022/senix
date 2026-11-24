{
  lib,
  runCommand,
}:
path:
let
  # TODO: Make this configurable? Probably not since there is not much change
  # in this structure. Unless we want to reduce the amount of labelling done?
  dirMap = {
    # .subs_dist aliases below to /usr/* in the default refpolicy
    bin = "/bin";
    sbin = "/sbin";
    lib = "/lib";
    lib64 = "/lib64";
    # below do not have equivilant matches in the sub_dists so we should map explicitly
    share = "/usr/share";
    libexec = "/usr/libexec";
    include = "/usr/include";
  };

  base = builtins.unsafeDiscardStringContext (baseNameOf path);
  arms = lib.concatStringsSep "\n" (lib.mapAttrsToList (n: to: "${n}) to=${to} ;;") dirMap);
in
runCommand "pkgs-2-subs-${base}" { } ''
  for d in ${path}/*; do # We only really need to look at the top level structure
    [ -e "$d" ] || [ -L "$d" ] || continue
    n=$(basename "$d")
    case "$n" in
      ${arms}
      *) to="/$n" ;;
    esac
    echo "$d $to"
  done > $out
''
