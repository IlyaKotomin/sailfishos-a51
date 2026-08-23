# Installing

> **This replaces Android.** Sailfish lives in `/data/.stowaways/sailfishos` and
> takes over the boot partition. Your Android user data stays on `/data` but
> becomes inaccessible from Sailfish. Back up anything you care about first.

## Requirements

- **SM-A515F specifically.** Other A51 variants are untested and may differ.
- **Stock Android 13 firmware `A515FXXU8HWI1`** installed and booted once. This
  port ships no Android system of its own: it mounts the stock `system`,
  `vendor`, `product` and `odm` partitions for the HALs and blobs. A different
  firmware may work but is untested — the SELinux policy is compiled from
  whatever CIL the installed firmware provides.
- **Unlocked bootloader** (Samsung's OEM unlock, which wipes the device).
- **TWRP 3.7.1_12-0 for `a51`.**
- A Linux PC with `heimdall` (Odin on Windows also works) for flashing TWRP.

## Download

Everything you need is attached to the [latest release](https://github.com/IlyaKotomin/sailfishos-a51/releases/latest):

| File | What it is |
|---|---|
| `sailfishos-a51-release-5.1.0.11-a51-12.zip` | The Sailfish OS image, flashed from TWRP |
| `twrp-3.7.1_12-0-a51.img` | The official [TWRP](https://twrp.me/samsung/samsunggalaxya51.html) 3.7.1_12-0 build for `a51`, mirrored here so the versions are known to match |
| `python3-gbinder-*.aarch64.rpm` | Only needed for Waydroid — see [ANDROID-APPS.md](ANDROID-APPS.md) |
| `SHA256SUMS` | Checksums for all of the above |

Verify the download before flashing anything — a truncated zip is exactly the
kind of thing that produces a phone that will not boot:

```bash
sha256sum -c SHA256SUMS
```

## Steps

**1. Install stock Android 13 (`A515FXXU8HWI1`) and boot it once.**

**2. Unlock the bootloader**
- Settings → About phone → Software information → tap *Build number* seven times
- Settings → Developer options → enable *OEM unlocking*
- Power off, then hold **Volume Up + Volume Down** while plugging in USB to enter
  download mode, and follow the on-screen unlock prompt (this wipes the device)

**3. Flash TWRP** to the recovery partition:

```bash
heimdall flash --RECOVERY twrp-3.7.1_12-0-a51.img --no-reboot
```

**4. Boot into TWRP** — hold **Volume Up + Power** (release Power when the logo
appears). Let it mount `/data` when asked.

**5. Copy the zip to the phone.** From TWRP, with the phone connected:

```bash
adb push sailfishos-a51-release-5.1.0.11-a51-12.zip /sdcard/
```

Verify it arrived intact — a truncated zip is exactly the kind of thing that
produces a phone that will not boot:

```bash
adb shell sha256sum /sdcard/sailfishos-a51-release-5.1.0.11-a51-12.zip
```

**6. Install** → select the zip → swipe to confirm.

No wipe is needed. The installer extracts the rootfs into
`/data/.stowaways/sailfishos` and writes the boot partition itself. It checks
that the extraction actually produced a rootfs before touching the kernel, so a
failed install leaves the previous system bootable.

**7. Reboot.** First boot takes a few minutes: the SELinux policy is compiled on
the device, the cgroup hierarchy is built, and first-boot defaults are seeded.

**8. Complete the setup wizard.** The Jolla account is optional — skip it if you
like; it only gates the Jolla Store.

## After installing

**Wi-Fi first.** USB networking does not work on this device (see
[HARDWARE.md](HARDWARE.md)), so Wi-Fi is the only way in.

**SSH is enabled from first boot**, which is a deliberate departure from stock
Sailfish — there, `sshd` stays off until you enable *Remote connection*, and
until it runs the developer page shows no address at all, which reads as broken
Wi-Fi debugging when nothing is wrong.

Set a real password under **Settings → Developer tools**: an SSH server is
listening on every interface that has an address. The username is `defaultuser`.
To return to stock behaviour:

```bash
systemctl disable --now sshd.socket
```

If the developer page shows no WLAN address, turn the screen off and on — the
page does not repaint on its own.

**Community software.** Chum is the community repository; its signing key is not
in the device trust store, so add it with signature checking scoped off:

```ini
# /etc/zypp/repos.d/chum.repo
[chum]
enabled=1
autorefresh=0
baseurl=https://repo.sailfishos.org/obs/sailfishos:/chum/5.0.0.76_aarch64/
gpgcheck=0
repo_gpgcheck=0
pkg_gpgcheck=0
```

Chum has no target for 5.1.0.11 yet; the 5.0.0.76 packages work.

**Android apps** are a post-install step — see [ANDROID-APPS.md](ANDROID-APPS.md).

## If it does not boot

Hold **Volume Up + Power** to reach TWRP; the phone is not bricked. From there
you can reflash the zip, or return to Android with stock firmware via Odin or
heimdall. `docs/TROUBLESHOOTING.md` covers the failure modes seen during
development.
