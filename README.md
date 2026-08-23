# Sailfish OS for the Samsung Galaxy A51 (SM-A515F)

An unofficial Sailfish OS 5.1.0.11 port for the Galaxy A51 (`a51`, Exynos 9611,
Mali-G72 MP3), built with the HADK against the stock Android 13 vendor blobs.

Almost all the hardware works, including two things usually written off on this
device: **Bluetooth** (Samsung shipped a deliberately gutted kernel HCI socket
layer — restored here) and **`logcat`** (droid-hal-init never sets up cgroups —
implemented here).

> **Alpha.** Telephony does not work. Read [docs/HARDWARE.md](docs/HARDWARE.md)
> before installing, and do not put this on a phone you depend on.

**[Download the latest release](https://github.com/IlyaKotomin/sailfishos-a51/releases/latest)**
— image, TWRP and checksums. Installation steps are in
[docs/INSTALL.md](docs/INSTALL.md).

## Status at a glance

| Works | Does not work |
|---|---|
| Boot, display, touch, brightness | **Telephony** — rild never opens the modem IPC channels |
| Wi-Fi | Fingerprint reader |
| **Bluetooth** — scan, pair, SDP, A2DP/HFP profiles | USB networking — the gadget panics this kernel |
| **NFC** — reads tags (MIFARE Classic verified) | |
| **`logcat` / Android logging** | |
| **Audio** — speaker, earpiece, headphones, automatic jack switching | |
| **All 7 sensors** — accelerometer, gyroscope, compass, magnetometer, rotation, ambient light, orientation | |
| Auto-rotation, adaptive brightness (with a working toggle) | |
| Cameras, both rear and front | |
| Battery reporting and charging, vibration, hardware keys | |
| GPS stack (geoclue + Samsung GNSS HAL) — *a fix was never confirmed* | |
| Android apps via Waydroid (post-install, see [docs/ANDROID-APPS.md](docs/ANDROID-APPS.md)) | |

Untested rather than known-broken: calls and SMS (blocked by the modem),
microphone recording, camera flash and video recording, an actual GPS fix, the
SD card slot, and MTP.

## Documentation

| | |
|---|---|
| [docs/INSTALL.md](docs/INSTALL.md) | Flashing the image onto a phone |
| [docs/HARDWARE.md](docs/HARDWARE.md) | Detailed hardware status and how each item was verified |
| [docs/BUILDING.md](docs/BUILDING.md) | Rebuilding the image from these sources |
| [docs/PORTING-NOTES.md](docs/PORTING-NOTES.md) | The technical findings — most of the value in this repo |
| [docs/ANDROID-APPS.md](docs/ANDROID-APPS.md) | Waydroid setup, and Firefox for Android |
| [docs/TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md) | Symptoms, causes and fixes |
| [docs/KNOWN-ISSUES.md](docs/KNOWN-ISSUES.md) | Open problems, and the engineering notes behind each fix |

## What is in here

```
droid-configs/     the device configuration package — the heart of the port
patches/kernel/    8 kernel patches, including the Bluetooth and binderfs fixes
patches/hybris-boot/          installer and init-script fixes
patches/droid-configs-device/ kickstart and updater packaging fixes
scripts/           helper scripts used while building and debugging
docs/              everything above
```

`droid-configs/` is a full copy of the device configuration tree: the RPM spec,
the `patterns/` files that decide what goes into the image, and the `sparse/`
tree that is laid over the rootfs (systemd units, the `droid-*` helper scripts,
audio routing, the CSD hardware-feature file, and so on).

`droid-configs/droid-configs-device/` is vendored from
[mer-hybris/droid-hal-configs](https://github.com/mer-hybris/droid-hal-configs)
at commit `a9b3995`, with the four changes in `patches/droid-configs-device/`
applied. Upstream it is a submodule; it is checked in here so this repository is
a complete snapshot of the sources that built the released image. See
[LICENSE](LICENSE).

## The parts worth stealing for other ports

Several fixes here are not device-specific and may help anyone on a recent
Samsung/Exynos base — the details are in
[docs/PORTING-NOTES.md](docs/PORTING-NOTES.md):

- **Bluetooth panics on the first AF_BLUETOOTH socket.** Samsung commented out
  the bodies of `hci_sock.c`'s socket functions and left `return 0;`, so
  `hci_sock_create()` reports success with `sock->sk == NULL` and the kernel hits
  `BUG_ON(!sk)`. Restoring the file from upstream fixes Bluetooth completely.
- **`logcat` never works, and dozens of Android services abort.** droid-hal-init
  does not run `CgroupSetup()`, so `/dev/cgroup_info/cgroup.rc` is missing.
  Writing that file (and creating the cgroups) fixes logging — and libbase reads
  `task_profiles.json` with `O_NOFOLLOW`, so it must be a **copy**, never a
  symlink.
- **A device with no audio HAL can still have working audio.** The mixer routing
  and jack detection are done by two small services instead.
- **The CSD hardware-features file** decides what Settings shows. It is keyed by
  CSD names (`GSensor`, `ECompass`) and parsed with `strtol`, so `= true` reads
  as *disabled*.

## Credits

Built with the Sailfish OS HADK. Thanks to mer-hybris for libhybris and
`qt5-qpa-hwcomposer-plugin`, to Jolla for Sailfish OS and its open components,
and to the LineageOS `a51` device tree maintainers.
