# indi-canon-bulb-fix

Canon EOS 550D on a Raspberry Pi 5 (Ubuntu 24.04, arm64) with KStars/Ekos: every exposure longer than
30 s started and never ended. This repository rebuilds the INDI gphoto driver with the upstream fix
against the INDI that is already installed, and installs it next to the packaged one.

## What was wrong

Up to 30 s a Canon uses its own shutter speeds. Longer exposures are BULB: the driver "presses" the
shutter through libgphoto2's `eosremoterelease` setting, waits, and "releases" it. The packaged
driver (indi-gphoto 3.4, built 2025-10-03) picks those buttons by fixed index:

| index | driver meant | libgphoto2 2.5.33 has |
|------:|--------------|-----------------------|
| 2     | Press Full   | Press Full AF         |
| 4     | Release Full | **Press Full MF**     |
| 7     | -            | Release               |

libgphoto2 2.5.33 reordered the list, so the "release" became a second press. The shutter stayed
open, the camera never produced an image, and Ekos reported `Exposure timeout` until it restarted
the driver. `./check-camera.sh --reproduce` shows it with plain gphoto2: after index 4 the camera's
`BulbExposureTime` keeps counting, and the file only arrives after index 7.

INDI fixed it upstream in indi-3rdparty
[d899e76](https://github.com/indilib/indi-3rdparty/commit/d899e76) (2026-06-12): the indices are
now looked up by name. [9d8aff3](https://github.com/indilib/indi-3rdparty/commit/9d8aff3)
(2026-09-23) also drops stale camera events between a preset and a BULB exposure and fixes a crash
on disconnect. The mutlaqja PPA no longer publishes noble arm64 builds, so apt cannot bring them.

## How

The driver must match the installed libindi exactly, and no `libindi-dev` of that version exists
for the Pi. So `build.sh`:

1. reads the installed INDI version (`libindi1`, here 2.1.6);
2. builds INDI core of that version only for its headers and link libraries - nothing of it is
   installed;
3. builds the whole `indi-gphoto/` directory from `GPHOTO_REF` (default 9d8aff3) on top of
   indi-3rdparty of the same version - no other driver is built. The two fixes alone do not apply to
   2.1.6 (later commits changed the same file), so the driver comes as one piece and also carries
   upstream's other gphoto changes since 2025-10: Sony A7 III / A7R IV exposure fixes, manual focus
   fix, subframing when the RAW size differs, Nikon short-exposure / BULB switching. Only the Canon
   path (preset and BULB exposures, download, FITS) was tested here;
4. checks that the result links the system's `libindidriver.so.2` and contains the fix.

`install.sh` puts it in `/usr/local/bin`. `indiserver` starts drivers by name through `PATH`,
where `/usr/local/bin` comes before `/usr/bin`, so KStars uses it with no profile changes, and the
packaged driver stays where it was.

## Use

On the Pi, with the camera on USB in M mode and KStars closed:

```sh
./build.sh --deps        # first time: apt build dependencies; ~25 min on a Pi 5 (INDI core)
./test.sh work/gphoto-root/usr/local/bin/indi_gphoto_ccd    # 10, 35, 35 s before installing
./install.sh
./test.sh                # same, through the installed driver, as KStars will start it
```

Or install the ready-made package instead of `install.sh` - arm64, INDI 2.1.x only (apt refuses it
on another INDI; then rebuild and run `./make-deb.sh`):

```sh
./uninstall.sh                      # if install.sh was used before
sudo apt install ./dist/indi-gphoto-canon-fix_2.1.6+git9d8aff3_arm64.deb
sudo apt remove indi-gphoto-canon-fix                                    # to undo
```

`test.sh` runs its own `indiserver` on port 7626 and saves frames to `test-frames/` (~35 MB each).
It has to set the sensor size itself (`SENSOR`, default 5184 3456 4.3 for the 550D) - Ekos does that
from its DSLR table, and the driver will not expose without it.

Verified 2026-10-11: 10 s, 35 s, 35 s back to back and 35 s through `indi_canon_ccd`, all full
5184x3456 16-bit FITS; a 35 s frame took 41-44 s from start to file (mirror lock, download, FITS).

## When to remove it

The rebuilt driver fits one libindi version. After INDI itself is upgraded, or once a packaged
indi-gphoto newer than 2026-06-12 is installed, run `./uninstall.sh` (and rebuild if still needed).
An `apt upgrade` of indi-gphoto alone does not replace it - `/usr/local/bin` keeps winning. With the
package installed, `apt upgrade` keeps INDI back, and `apt full-upgrade` upgrades INDI by removing
the package - the packaged driver (with the bug) is then back.

## Notes

- Ekos's mirror lock setting (1 s here) is added to every exposure.
- If the driver reports "Could not claim the USB device", another program holds the camera: a
  second INDI server, a hung driver from an earlier session, or the desktop's gvfs automounter.
