{
  lib,
  pkgs,
  callPackage,
  ...
}:
{
  closure,
  contexts ? "${pkgs.selinux-refpolicy}/etc/selinux/refpolicy/contexts/files",
}:
let
  mkSubs = callPackage ../pkgs/util/pkg-2-subs.nix { };
  mkContexts = callPackage ../pkgs/util/sub-2-contexts.nix { };
  mkImage = callPackage ../pkgs/util/context-2-erofs.nix { };
  merge = callPackage ../pkgs/util/erofs-2-image.nix { };

  paths = lib.filter (p: p != "") (lib.splitString "\n" (builtins.readFile "${closure}/store-paths"));

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
      context = "${contextFor path}/file_contexts";
    };
in
merge { images = map imageFor paths; }
