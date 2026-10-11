#!/bin/bash
# Rebuild indi_gphoto_ccd with the Canon EOS BULB fix, against the INDI that is already installed.
#
# The packaged driver cannot simply be swapped for a newer one: it has to match the installed libindi
# exactly, and no libindi-dev of that version is available. So INDI core of the same version is built
# only to get its headers and link libraries, and is never installed - the driver runs on the system's
# own libindidriver.so.2.
#
#   ./build.sh            fetch sources, build; the result lands in work/gphoto-root/usr/local/bin
#   ./build.sh --deps     install the build dependencies with apt first (asks for sudo)
#
# Environment: INDI_VERSION (default: the installed libindi1), GPHOTO_REF, WORK, JOBS.

set -euo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
WORK=${WORK:-$HERE/work}
JOBS=${JOBS:-$(nproc)}
# indi-3rdparty commit whose indi-gphoto/ directory is built: d899e76 (2026-06-12) fixed the
# eosremoterelease lookup, 9d8aff3 (2026-09-23) the stale event between preset and BULB exposures
# and a crash on disconnect.
GPHOTO_REF=${GPHOTO_REF:-9d8aff3}
INDI_VERSION=${INDI_VERSION:-$(dpkg-query -W -f='${Version}' libindi1 2>/dev/null | grep -oE '^[0-9]+\.[0-9]+\.[0-9]+' || true)}

DEPS="git cmake build-essential pkg-config libgphoto2-dev libcfitsio-dev libraw-dev libjpeg-dev
      libusb-1.0-0-dev libnova-dev libfftw3-dev libgsl-dev libcurl4-openssl-dev libev-dev
      libtheora-dev zlib1g-dev"

if [ "${1:-}" = "--deps" ]; then
    # shellcheck disable=SC2086
    sudo apt-get install -y $DEPS
fi

if [ -z "$INDI_VERSION" ]; then
    echo "Cannot tell which INDI is installed (no libindi1 package). Set INDI_VERSION=x.y.z." >&2
    exit 1
fi
echo "INDI $INDI_VERSION, indi-gphoto from $GPHOTO_REF, work dir $WORK"
mkdir -p "$WORK"
cd "$WORK"

# --- sources -----------------------------------------------------------------------------------
if [ ! -d indi ]; then
    git -c advice.detachedHead=false clone -q --depth 1 --branch "v$INDI_VERSION" https://github.com/indilib/indi.git
fi
if [ ! -d indi-3rdparty ]; then
    git -c advice.detachedHead=false clone -q --filter=blob:none --branch "v$INDI_VERSION" https://github.com/indilib/indi-3rdparty.git
fi
# Only the driver directory moves forward; everything else stays at the installed version.
git -C indi-3rdparty fetch -q origin master
git -C indi-3rdparty checkout -q "$GPHOTO_REF" -- indi-gphoto

# --- INDI core: headers and link libraries only -----------------------------------------------
# Drivers have to be on: that is what builds libindidriver. The client library is needed by the
# alignment library. DESTDIR keeps the udev rules (absolute /lib paths) out of the system.
STAGE=$WORK/indi-root/stage
if [ ! -e "$STAGE/lib/libindidriver.so" ]; then
    mkdir -p build-indi
    cmake -S indi -B build-indi -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX=/stage \
        -DINDI_BUILD_SERVER=OFF -DINDI_BUILD_DRIVERS=ON -DINDI_BUILD_CLIENT=ON \
        -DINDI_BUILD_STATIC=OFF -DINDI_BUILD_XISF=OFF -DINDI_BUILD_EXAMPLES=OFF > build-indi.log
    nice make -C build-indi -j"$JOBS" >> build-indi.log 2>&1 || { tail -20 build-indi.log; exit 1; }
    make -C build-indi install DESTDIR="$WORK/indi-root" >> build-indi.log 2>&1
fi

# --- the driver ---------------------------------------------------------------------------------
rm -rf build-gphoto gphoto-root
cmake -S indi-3rdparty/indi-gphoto -B build-gphoto -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_PREFIX_PATH="$STAGE" -DCMAKE_INSTALL_PREFIX=/usr/local > build-gphoto.log
nice make -C build-gphoto -j"$JOBS" >> build-gphoto.log 2>&1 || { tail -20 build-gphoto.log; exit 1; }
# Installing drops the build RPATH, so the binary loads the system's libindidriver, not the stage.
make -C build-gphoto install DESTDIR="$WORK/gphoto-root" >> build-gphoto.log 2>&1

BIN=$WORK/gphoto-root/usr/local/bin/indi_gphoto_ccd
# grep -c, not -q: with pipefail, -q quitting early makes the writer die of SIGPIPE and the test fail.
if [ "$(ldd "$BIN" | grep -c "$WORK")" != 0 ]; then
    echo "$BIN still links against the build stage:" >&2
    ldd "$BIN" | grep "$WORK" >&2
    exit 1
fi
if [ "$(strings "$BIN" | grep -c "eosremoterelease: Press Full index")" = 0 ]; then
    echo "$BIN does not contain the eosremoterelease fix - check GPHOTO_REF" >&2
    exit 1
fi
echo "Built $BIN"
echo "Next: ./test.sh $BIN   then   ./install.sh"
