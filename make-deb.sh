#!/bin/bash
# Package the driver built by ./build.sh as a .deb in dist/, so the next Pi does not need the build.
#
#   ./make-deb.sh
#   sudo apt install ./dist/indi-gphoto-canon-fix_*.deb      (sudo apt remove indi-gphoto-canon-fix to undo)
#
# The package installs into /usr/local/bin, like install.sh: indiserver finds drivers through PATH and
# /usr/local/bin wins over the packaged /usr/bin. It depends on the libindi it was built against
# (same x.y.z), so apt refuses it on another INDI instead of installing a driver that does not fit.

set -euo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
WORK=${WORK:-$HERE/work}
SRC=$WORK/gphoto-root/usr/local/bin
GPHOTO_REF=${GPHOTO_REF:-9d8aff3}
INDI_VERSION=${INDI_VERSION:-$(dpkg-query -W -f='${Version}' libindi1 2>/dev/null | grep -oE '^[0-9]+\.[0-9]+\.[0-9]+' || true)}
NAMES="indi_canon_ccd indi_nikon_ccd indi_sony_ccd indi_pentax_ccd indi_fuji_ccd"

[ -x "$SRC/indi_gphoto_ccd" ] || { echo "Nothing built yet - run ./build.sh first." >&2; exit 1; }
[ -n "$INDI_VERSION" ] || { echo "Cannot tell the INDI version; set INDI_VERSION=x.y.z." >&2; exit 1; }

PKG=indi-gphoto-canon-fix
ARCH=$(dpkg --print-architecture)
VERSION="$INDI_VERSION+git$GPHOTO_REF"
NEXT=$(echo "$INDI_VERSION" | awk -F. '{print $1 "." $2 "." $3 + 1}')
MAINT="$(git config user.name 2> /dev/null || echo local) <$(git config user.email 2> /dev/null || echo root@localhost)>"

ROOT=$(mktemp -d)
trap 'rm -rf "$ROOT"' EXIT
mkdir -p "$ROOT/DEBIAN" "$ROOT/usr/local/bin" "$ROOT/usr/share/doc/$PKG"
install -m 755 "$SRC/indi_gphoto_ccd" "$ROOT/usr/local/bin/indi_gphoto_ccd"
for n in $NAMES; do
    ln -s indi_gphoto_ccd "$ROOT/usr/local/bin/$n"
done
install -m 644 "$HERE/README.md" "$ROOT/usr/share/doc/$PKG/README.md"

# Each alternative pair: the Ubuntu 24.04 (t64) name and the INDI PPA's name of the same library.
cat > "$ROOT/DEBIAN/control" << EOF
Package: $PKG
Version: $VERSION
Architecture: $ARCH
Maintainer: $MAINT
Section: science
Priority: optional
Depends: libindi1 (>= $INDI_VERSION), libindi1 (<< $NEXT), libgphoto2-6 | libgphoto2-6t64,
 libgphoto2-port12 | libgphoto2-port12t64, libraw23 | libraw23t64, libcfitsio10 | libcfitsio10t64,
 libjpeg-turbo8, libstdc++6, libc6
Description: INDI gphoto driver with the Canon EOS BULB fix
 indi_gphoto_ccd (indi-3rdparty $GPHOTO_REF) rebuilt against INDI $INDI_VERSION, installed in
 /usr/local/bin where it shadows the packaged driver. With libgphoto2 2.5.33 the packaged driver
 ends a BULB exposure with "Press Full MF" instead of "Release", so exposures over 30 s never end.
 Remove this package after INDI is upgraded.
EOF

mkdir -p "$HERE/dist"
OUT=$HERE/dist/${PKG}_${VERSION}_$ARCH.deb
dpkg-deb --root-owner-group --build "$ROOT" "$OUT" > /dev/null
dpkg-deb --info "$OUT" | sed -n '/Package:/,/Description:/p'
dpkg-deb --contents "$OUT" | awk '{print $6, $7, $8}'
echo "$OUT"
