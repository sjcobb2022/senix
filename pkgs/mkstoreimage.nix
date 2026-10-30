{stdenvNoCC}:
stdenvNoCC.mkDerivation {
  pname = "nix-closure-erofs";
  version = "0.1.0";

  nativeBuildInputs = [];
}
# Something along the lines of
# tar \
#    --create \
#    --file=- \
#    --directory="$SRC" \
#    --format=pax \
#    . |
# mkfs.erofs --tar=i \
#    --file-contexts="${contexts}" \
#    "$out" -
# Maybe?

