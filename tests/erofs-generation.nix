{ pkgs, ... }:
let
  contexts = "${pkgs.selinux-refpolicy}/etc/selinux/refpolicy/contexts/files";

  mkSubs = pkgs.callPackage ../pkgs/util/pkg-2-subs.nix { };
  mkContexts = pkgs.callPackage ../pkgs/util/sub-2-contexts.nix { };
  mkImage = pkgs.callPackage ../pkgs/util/context-2-erofs.nix { };
  merge = pkgs.callPackage ../pkgs/util/erofs-2-image.nix { };
  mkErofs = pkgs.callPackage ../pkgs/closure-2-erofs.nix { };

  contextsFor =
    path:
    mkContexts {
      context = "${contexts}/file_contexts";
      subs = mkSubs path;
    };

  imageFor =
    path:
    mkImage {
      inherit path;
      context = "${contextsFor path}/file_contexts";
    };

  # fake binary that looks basically like a binary which is in the refpolicy
  hostname = pkgs.runCommand "test-hostname" { } ''
    mkdir -p $out/bin
    printf '#!/bin/sh\n' > $out/bin/hostname
    chmod +x $out/bin/hostname
  '';

  consumer = pkgs.runCommand "test-consumer" { } ''
    mkdir -p $out/bin
    printf '#!/bin/sh\nexec ${hostname}/bin/hostname' > $out/bin/consumer
    chmod +x $out/bin/consumer
  '';

  other = pkgs.runCommand "test-other" { } ''
    mkdir -p $out/share
    echo dummy > $out/share/dummy.txt
  '';

  imgHostname = imageFor hostname;
  imgOther = imageFor other;
  merged = merge {
    images = [
      imgHostname
      imgOther
    ];
  };
  imgErofs = mkErofs {
    closure = pkgs.closureInfo { rootPaths = [ consumer ]; };
    inherit contexts;
  };
  imgHostname' = imgHostname.overrideAttrs (_: {
    name = "erofs-image-hostname-again";
  });
in
pkgs.runCommand "erofs-generation" { nativeBuildInputs = [ pkgs.erofs-utils ]; } ''
  nameH=$(basename ${hostname})
  nameO=$(basename ${other})
  nameC=$(basename ${consumer})

  # grep for the xattrs
  labels() {
    grep -aoE 'system_u:object_r:[A-Za-z0-9_]+' "$1" | sort -u
  }

  grep -qxF "${hostname}/bin /bin" ${mkSubs hostname}
  grep -qxF "${other}/share /usr/share" ${mkSubs other}

  # we have /usr/bin/hostname in the refpolicy (just double checking)
  expected=$(awk '$1 == "/usr/bin/hostname" { print $NF; exit }' ${contexts}/file_contexts)
  test -n "$expected"

  # All the generated erofs are valid
  fsck.erofs ${imgHostname}
  fsck.erofs ${imgOther}

  # We have the /bin/hostname and not /share/dummy.txt
  dump.erofs --ls --path=/nix/store ${imgHostname} | grep -F "$nameH"
  ! dump.erofs --ls --path=/nix/store ${imgHostname} | grep -qF "$nameO"
  grep -aqF "$expected" ${imgHostname}

  # We have the /share/dummy.txt and not /bin/hostname
  dump.erofs --ls --path=/nix/store ${imgOther} | grep -F "$nameO"
  ! dump.erofs --ls --path=/nix/store ${imgOther} | grep -qF "$nameH"
  ! grep -aqF "$expected" ${imgOther}

  fsck.erofs ${merged}

  # merged has both
  dump.erofs --ls --path=/nix/store ${merged} | grep -F "$nameH"
  dump.erofs --ls --path=/nix/store ${merged} | grep -F "$nameO"

  # both files are in their own distinct locations
  dump.erofs --ls --path=/nix/store/$nameH/bin ${merged} | grep -F hostname
  dump.erofs --ls --path=/nix/store/$nameO/share ${merged} | grep -F dummy.txt

  grep -aqF "$expected" ${merged}

  # get all the unique labels on the two images
  {
    labels ${imgHostname}
    labels ${imgOther}
  } | sort -u > union

  # all the labels on the unique images are the
  labels ${merged} > merged-labels
  test -z "$(comm -13 union merged-labels)"

  # we have the static uuid so that it doesn't create a new derivation output each time
  dump.erofs -s ${merged} | grep -i uuid | grep -F 00000000-0000-0000-0000-000000000000

  # combined via closure-2-erofs also works fine.
  fsck.erofs ${imgErofs}
  dump.erofs --ls --path=/nix/store ${imgErofs} | grep -F "$nameC"
  dump.erofs --ls --path=/nix/store ${imgErofs} | grep -F "$nameH"
  ! dump.erofs --ls --path=/nix/store ${imgErofs} | grep -F "$nameO"
  grep -aqF "$expected" ${imgErofs}

  # the modified hostnames are the same, not dependant over the pkg name
  cmp ${imgHostname} ${imgHostname'}

  touch $out
''
