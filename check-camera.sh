#!/bin/bash
# Show the camera's remote-release choices, the list whose order changed under the old driver.
#
#   ./check-camera.sh               list the choices
#   ./check-camera.sh --reproduce   run the old driver's BULB sequence with plain gphoto2:
#                                   press index 2, wait 8 s, "release" index 4, wait 15 s - then the
#                                   real Release, so the camera is not left exposing.
#
# With libgphoto2 >= 2.5.33 index 4 is "Press Full MF": the camera's BulbExposureTime keeps counting
# through the second wait and the image only arrives after "Release". That is the hang.
# Needs the camera in M mode and nothing else (KStars/INDI) connected to it. Takes one frame.

set -euo pipefail

gphoto2 --get-config eosremoterelease

if [ "${1:-}" = "--reproduce" ]; then
    echo
    echo "old driver sequence: press 2, release 4, then real Release ($(gphoto2 --version | head -1))"
    stdbuf -oL gphoto2 --set-config shutterspeed=bulb \
        --set-config-index eosremoterelease=2 --wait-event=8s \
        --set-config-index eosremoterelease=4 --wait-event=15s \
        --set-config-index eosremoterelease=7 --wait-event=15s 2>&1 \
        | grep --line-buffered -E "BulbExposureTime|FILEADDED|Waiting" \
        | while IFS= read -r l; do echo "$(date +%T) $l"; done
fi
