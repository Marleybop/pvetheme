#!/usr/bin/env bash
# Builds dist/install.sh: one self-contained installer with the theme files inside it.
#   ./build.sh            build the installer
#   ./build.sh --dev      also build every theme into dist/dev/themes/ from dev/theme-proxmox-dark.css
#                         (a copy of the host's stock dark theme), for tools/shot.cjs --serve
set -euo pipefail
cd "$(dirname "$0")"

VERSION=$(tr -d ' \r\n' < VERSION)
stage=$(mktemp -d)
trap 'rm -rf "$stage"' EXIT

mkdir -p dist "$stage/fonts"
# text files go in with LF endings whatever the checkout did
for f in src/apply.sh src/palette.sed src/layer.css src/marleybop-theme.js LICENSE; do
    tr -d '\r' < "$f" > "$stage/$(basename "$f")"
done
cp src/fonts/*.woff2 src/fonts/*.txt "$stage/fonts/"
mkdir -p "$stage/themes"
for f in src/themes/*.theme src/themes/index; do
    tr -d '' < "$f" > "$stage/themes/$(basename "$f")"
done
printf '%s\n' "$VERSION" > "$stage/VERSION"

# reproducible archive: fixed order, owner and time
tar --sort=name --owner=0 --group=0 --numeric-owner --mtime='2026-01-01 00:00:00Z' \
    -C "$stage" -cf - . | gzip -n -9 > "$stage.tgz"
sum=$(sha256sum "$stage.tgz" | cut -d' ' -f1)

{
    tr -d '\r' < src/install.head.sh | sed "s/@MBVER@/$VERSION/g; s/@MBSUM@/$sum/g"
    base64 -w 76 "$stage.tgz"
    tr -d '\r' < src/install.tail.sh
} > dist/install.sh
rm -f "$stage.tgz"
bash -n dist/install.sh
bash -n src/apply.sh
echo "dist/install.sh  v$VERSION  $(wc -c < dist/install.sh) bytes  payload sha256 $sum"

if [ "${1:-}" = "--dev" ]; then
    stock=dev/theme-proxmox-dark.css
    [ -f "$stock" ] || { echo "missing $stock (copy it from the host: /usr/share/javascript/proxmox-widget-toolkit/themes/)"; exit 1; }
    rm -rf dist/dev
    MB_WT_DIR=dist/dev MB_STOCK=$stock MB_ETC_DIR=dist/dev/none MB_VERSION=$VERSION bash src/apply.sh build-dev
fi
