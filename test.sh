#!/bin/bash
# Take a few exposures through INDI without KStars, on a private indiserver port, and report which
# ones finished. Close KStars (or disconnect the camera in Ekos) first - only one program can own it.
#
#   ./test.sh                         installed driver (found through PATH, as KStars finds it), 10 35 35 s
#   ./test.sh 60                      installed driver, one 60 s exposure
#   ./test.sh work/gphoto-root/usr/local/bin/indi_gphoto_ccd 10 35 35     a build that is not installed yet
#
# Anything over 30 s is a BULB exposure on a Canon; up to 30 s the camera's own shutter speeds are used,
# which is why short exposures worked even with the broken driver.
#
# Environment: SENSOR="5184 3456 4.3" (width, height, pixel um - EOS 550D), PORT, OUT.

set -uo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
DRIVER=indi_canon_ccd
if [ $# -gt 0 ] && ! [[ $1 =~ ^[0-9.]+$ ]]; then   # first argument is a driver, not an exposure
    DRIVER=$1
    shift
fi
EXPOSURES=${*:-10 35 35}
PORT=${PORT:-7626}
OUT=${OUT:-$HERE/test-frames}
read -r W H PIX <<< "${SENSOR:-5184 3456 4.3}"

[ -d "$DRIVER" ] && { echo "$DRIVER is a directory" >&2; exit 1; }
case $DRIVER in */*) DRIVER=$(cd "$(dirname "$DRIVER")" && pwd)/$(basename "$DRIVER") ;; esac
mkdir -p "$OUT"
rm -f "$OUT"/frame_*

indiserver -p "$PORT" "$DRIVER" > "$OUT/server.log" 2>&1 < /dev/null &
SERVER=$!
trap 'kill $SERVER 2> /dev/null' EXIT
sleep 3

DEV=""
for _ in $(seq 1 10); do
    DEV=$(indi_getprop -p "$PORT" -1 "*.DRIVER_INFO.DRIVER_NAME" 2> /dev/null | head -1 | sed 's/\.DRIVER_INFO\..*//')
    [ -n "$DEV" ] && break
    sleep 1
done
[ -n "$DEV" ] || { echo "Driver did not come up:"; cat "$OUT/server.log"; exit 1; }
DPID=$(pgrep -P "$SERVER" | head -1)
echo "device '$DEV', running $(readlink "/proc/$DPID/exe" 2> /dev/null || echo "$DRIVER")"

sp() { indi_setprop -p "$PORT" "$@"; }
sp "$DEV.CONNECTION.CONNECT=On"
for _ in $(seq 1 30); do
    [ "$(indi_getprop -p "$PORT" -1 "$DEV.CONNECTION.CONNECT" 2> /dev/null)" = On ] && break
    sleep 1
done
sleep 3
# Ekos fills these in from its DSLR table; without them the driver refuses to expose.
sp "$DEV.CCD_INFO.CCD_MAX_X;CCD_MAX_Y;CCD_PIXEL_SIZE;CCD_PIXEL_SIZE_X;CCD_PIXEL_SIZE_Y;CCD_BITSPERPIXEL=$W;$H;$PIX;$PIX;$PIX;16"
sp "$DEV.UPLOAD_SETTINGS.UPLOAD_DIR;UPLOAD_PREFIX=$OUT;frame_XXX"
sp "$DEV.UPLOAD_MODE.UPLOAD_CLIENT;UPLOAD_LOCAL;UPLOAD_BOTH=Off;On;Off"
sleep 1

failed=0
for e in $EXPOSURES; do
    n0=$(ls "$OUT" | grep -c '^frame_')
    t0=$(date +%s)
    echo "$(date +%T) ${e} s exposure"
    sp "$DEV.CCD_EXPOSURE.CCD_EXPOSURE_VALUE=$e"
    done_=0
    while [ $(( $(date +%s) - t0 )) -lt $(( ${e%.*} + 60 )) ]; do
        sleep 1
        [ "$(ls "$OUT" | grep -c '^frame_')" -gt "$n0" ] && { done_=1; break; }
    done
    if [ $done_ = 1 ]; then
        echo "$(date +%T)   done after $(( $(date +%s) - t0 )) s: $(ls -t "$OUT" | grep '^frame_' | head -1)"
    else
        echo "$(date +%T)   HUNG - no image $(( ${e%.*} + 60 )) s after the start"
        failed=1
        break
    fi
    sleep 2
done

sp "$DEV.CONNECTION.DISCONNECT=On"
sleep 2
echo "frames in $OUT (each ~35 MB, delete when done)"
exit $failed
