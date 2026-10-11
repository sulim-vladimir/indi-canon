#!/bin/bash
# Remove the rebuilt driver; the packaged one in /usr/bin takes over again.
# Do this when INDI itself is upgraded (the rebuilt driver matches one libindi version only) or a
# packaged indi-gphoto with the fix becomes available.

set -euo pipefail

for n in indi_gphoto_ccd indi_canon_ccd indi_nikon_ccd indi_sony_ccd indi_pentax_ccd indi_fuji_ccd; do
    if [ -e "/usr/local/bin/$n" ] || [ -L "/usr/local/bin/$n" ]; then
        sudo rm "/usr/local/bin/$n"
    fi
done
type -a indi_canon_ccd || true
