#!/usr/bin/env bash
# Builds dist/install.sh: one self-contained installer with the theme files inside it.
#   ./build.sh            build the installer
#   ./build.sh --dev      also build dist/dev/theme-marleybop.css from dev/theme-proxmox-dark.css
#                         (a copy of the host's stock dark theme) for tools/shot.cjs
set -euo pipefail
cd "$(dirname "$0")"

VERSION=$(tr -d ' \r\n' < VERSION)
stage=$(mktemp -d)
trap 'rm -rf "$stage"' EXIT

mkdir -p dist "$stage/fonts"
# text files go in with LF endings whatever the checkout did
for f in src/apply.sh src/palette.sed src/marleybop.css src/marleybop-theme.js LICENSE; do
    tr -d '\r' < "$f" > "$stage/$(basename "$f")"
done
cp src/fonts/*.woff2 src/fonts/*.txt "$stage/fonts/"
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
    mkdir -p dist/dev
    {
        printf '/*!Marleybop Dark*/\n'
        sed -f src/palette.sed "$stock"
        printf '\n'
        sed "s/@MBVER@/$VERSION/g" src/marleybop.css
    } | tr -d '\r' > dist/dev/theme-marleybop.css
    cp src/fonts/*.woff2 dist/dev/
    echo "dist/dev/theme-marleybop.css  $(wc -c < dist/dev/theme-marleybop.css) bytes"
fi
