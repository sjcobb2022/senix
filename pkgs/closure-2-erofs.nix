{
  lib,
  callPackage,
  ...
}:
{
  closure,
  contexts,
}:
let
  mkSubs = callPackage ../pkgs/util/pkg-2-subs.nix { };
  mkContexts = callPackage ../pkgs/util/sub-2-contexts.nix { };
  mkImage = callPackage ../pkgs/util/context-2-erofs.nix { };
  merge = callPackage ../pkgs/util/erofs-2-image.nix { };

  storePaths = lib.filter (p: p != "") (
    lib.splitString "\n" builtins.readFile "${closure}/store-paths"
  );

  # Ensure that all the paths are store paths.
  paths = map builtins.storePath storePaths;

  contextFor =
    path:
    mkContexts {
      context = "${contexts}/file_contexts";
      subs = mkSubs path;
    };

  imageFor =
    path:
    mkImage {
      inherit path;
      context = "${contextFor path}/fileContexts";
    };
in
merge { images = map imageFor paths; }
