#!/bin/bash
# Put the rebuilt driver in /usr/local/bin. indiserver starts drivers by name through PATH, and
# /usr/local/bin comes before /usr/bin, so KStars picks this one up and the packaged driver stays
# untouched. ./uninstall.sh brings the packaged one back.

set -euo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
WORK=${WORK:-$HERE/work}
SRC=$WORK/gphoto-root/usr/local/bin
NAMES="indi_canon_ccd indi_nikon_ccd indi_sony_ccd indi_pentax_ccd indi_fuji_ccd"

[ -x "$SRC/indi_gphoto_ccd" ] || { echo "Nothing built yet - run ./build.sh first." >&2; exit 1; }
if pgrep -x indi_gphoto_ccd > /dev/null || pgrep -x indi_canon_ccd > /dev/null; then
    echo "A gphoto driver is running - disconnect it in Ekos (or stop INDI) first." >&2
    exit 1
fi

sudo install -m 755 "$SRC/indi_gphoto_ccd" /usr/local/bin/indi_gphoto_ccd
for n in $NAMES; do
    sudo ln -sf indi_gphoto_ccd "/usr/local/bin/$n"
done
type -a indi_canon_ccd
