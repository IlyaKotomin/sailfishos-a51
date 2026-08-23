# Building the image

This assumes a working Sailfish OS HADK setup. It is not a HADK tutorial — read
Jolla's HADK PDF first. What follows is what is specific to this device, and the
traps that cost real time.

## Layout

The HADK tree (`$ANDROID_ROOT`, e.g. `~/hadk`) needs:

| Path | From |
|---|---|
| `hybris/droid-configs` | `droid-configs/` in this repo |
| `kernel/samsung/universal9611` | Samsung/LineageOS `a51` kernel + `patches/kernel/` |
| `hybris/hybris-boot` | mer-hybris/hybris-boot + `patches/hybris-boot/` |
| `hybris/droid-configs/droid-configs-device` | the submodule + `patches/droid-configs-device/` |

Apply the patches with `git am`:

```bash
cd $ANDROID_ROOT/kernel/samsung/universal9611
git am /path/to/this/repo/patches/kernel/*.patch
```

## Build order

```bash
# in the Platform SDK
cd $ANDROID_ROOT
rpm/dhd/helpers/build_packages.sh --droid-hal    # only if the kernel changed
rpm/dhd/helpers/build_packages.sh --configs
rpm/dhd/helpers/build_packages.sh --mic          # produces the flashable zip
```

`--mic` writes both the rootfs tarball and the TWRP-flashable zip into
`$ANDROID_ROOT/SailfishOScommunity-release-*/`.

## Traps, in the order they will bite you

**`--droid-hal` is required more often than you think.** The installer scripts and
`hybris-boot.img` inside the zip are taken from the **built rootfs**, i.e. from
the droid-hal package. A config-only rebuild will happily ship yesterday's
installer against today's rootfs.

**Editing `hybris/hybris-boot/*` does nothing on its own.** Those files are
packaged from *staged copies* under
`out/target/product/$DEVICE/hybris-updater-{script,unpack.sh}`, and staging
substitutes `%DEVICE%`, `%BOOT_PART%`, `%DATA_PART%` and the device assert — so
they cannot be hand-copied either. Re-stage inside the HABUILD chroot first:

```bash
ubu-chroot -r /parentroot/srv/sailfishos/sdks/ubuntu -- bash -c \
  'source ~/.hadk.env; cd $ANDROID_ROOT; source build/envsetup.sh; \
   breakfast $DEVICE; make hybris-updater-script hybris-updater-unpack'
```

The module names carry **no extension** — ninja rejects `hybris-updater-unpack.sh`.

**tar_git builds from git HEAD.** Uncommitted working-tree edits are silently
ignored. Commit before building; a "fix" that never made it into a commit is the
most common reason a rebuild changes nothing.

**Check the built artefact, not the source.** Three separate bugs in this port
shipped because the source was correct and the image was not. Cheap checks:

```bash
Z=.../sailfishos-a51-release-*.zip
# only one rootfs, and the installer matches it
unzip -l "$Z" | grep -c 'tar\.'
unzip -p "$Z" updater-unpack.sh | grep FS_ARC
unzip -p "$Z" META-INF/com/google/android/updater-script | grep rootfs
# packages you added actually made it in
grep -E '^(alsa-utils|bluez5|nfcd|ofono-binder-plugin)' \
     .../Jolla-*-aarch64.packages
# scripts are executable
unzip -p "$Z" sailfishos-*.tar.gz | tar -tvz | grep usr/bin/droid/
```

**Do not trust `/proc/config.gz` on this kernel** — it is truncated (1874 of
~5900 lines). Test functionally instead: `ip link add ... type veth` beats reading
the config for `CONFIG_VETH`.

**The Platform SDK is 32-bit** (`uname -m` → `i686`). That is fine for the port,
but it means you cannot build a browser engine there: Gecko needs Rust ≥ 1.82
(the 5.1.0.11 target has 1.75) and linking `libxul` needs a 64-bit host.

## Kernel configuration notes

Several options interact badly on this tree:

| Option | Note |
|---|---|
| `CONFIG_BT=y` | **resets the device mid-boot.** Build Bluetooth as modules |
| `CONFIG_RFKILL=m` | **silently kills Wi-Fi** — it demotes `CFG80211` and `SCSC_WLAN` to modules. Must be `=y` |
| `CONFIG_USER_NS` | left **off**; Waydroid's LXC config declares no `lxc.idmap`, so it does not need them |
| `CONFIG_VETH`, `CONFIG_BRIDGE` | `=y`, needed for Waydroid's network |
| `CONFIG_NETFILTER_XT_TARGET_CHECKSUM` | needed by Waydroid's network script, which **aborts entirely** without it |
| `CONFIG_LOCALVERSION_BRANCH_SHA=y` | puts the git SHA in the version string, so committing changes the module vermagic — the boot image and modules must be flashed together |

## Publishing a release

```bash
sha256sum sailfishos-a51-release-*.zip > SHA256SUMS
unzip -t sailfishos-a51-release-*.zip        # verify the archive
```

Ship the Python 3.11 build of `python3-gbinder` alongside the image if you want
Waydroid to be installable — Chum's is built for 3.8 and blocks the whole install
(see [ANDROID-APPS.md](ANDROID-APPS.md)).
