# Known issues and engineering notes

Working notes kept while porting Sailfish OS to the A51. The reasoning behind a
fix is usually more useful than the fix itself, so the wrong turns are recorded
here too — several verdicts in this file were confidently wrong before they were
right, and those corrections are left visible on purpose.

For what does and does not work in the shipped image, see
[HARDWARE.md](HARDWARE.md). This file is the *why*, plus what is still open.

**The headline open problem is telephony.** Samsung's `cbd` boots the modem to
`ONLINE` and `rild` runs, but rild never opens `/dev/umts_ipc0`, so ofono reports
no modems. Unresolved.

**If your A51 is board REV02** the audio routing here will not work — REV02 uses
a TI TAS2562 amp where REV01 has a Richtek RT5510. See *Board revision matters*
below.

Rebuilding after changing any of this:

    build_packages.sh --droid-hal      # only if the kernel changed
    build_packages.sh --mw=libhybris   # only if libhybris changed
    build_packages.sh --configs
    build_packages.sh --mic

## What landed in this build

| What | Where | Commit |
|---|---|---|
| Installer: gzip rootfs instead of bzip2 (TWRP has no bzip2, and busybox tar fails *silently*) | `hybris-boot/updater-unpack.sh`, `droid-configs-device/kickstart/pack_package-droid-updater` | `fcbfd18`, `24dbb71` |
| Installer: verify the extraction really produced a rootfs | `hybris-boot/updater-unpack.sh` | `fcbfd18` |
| `run_debug_session()` must not `reboot -f` when USB debug networking cannot come up — it is called on every normal boot, so this bootlooped the phone | `hybris-boot/init-script` | `ed28449` |
| `mkdir -p /system` before the bind mount — a clean rootfs has no `/system`, so the bind failed and the whole Android side was missing (device sat on the Samsung splash) | `droid-configs/sparse/usr/bin/droid/droid-dynparts.sh` | `0b0b493` |
| `pixel_ratio` 1.0 → 1.75 for the 405 ppi panel | `droid-configs/rpm/droid-config-a51.spec` | `933a1b4` |
| `defaultuser` added to the `privileged` group at boot — without it lipstick's screenshot D-Bus API rejects every caller. A boot service, not an install scriptlet: the user does not exist until the first-boot wizard has run | `droid-configs/sparse/usr/bin/droid/droid-user-groups.sh` + `.service` | this build |
| UI scale helper shipped as `droid-set-ui-scale.sh` — there is no Settings entry and the vendor dconf key is locked, so this is the only way to change it | `droid-configs/sparse/usr/bin/droid/droid-set-ui-scale.sh` | this build |
| `CONFIG_USER_NS` off — this is what the working kernel on the phone was actually built with (no `/proc/self/uid_map`), and Waydroid's LXC config uses no `lxc.idmap`, so it does not need them | `kernel/.../a51-aosp_defconfig` | this build |
| Installer: delete a stale zip before packing — `zip` *adds to* an existing archive, so the previous build's zip kept its old entries and the release came out at 1.08 GB with **two** rootfs archives inside (new gzip + previous bzip2) | `droid-configs-device/kickstart/pack_package-droid-updater` | `f35bba5` |

These are all in the published zip as of this build — `--droid-hal`,
`--configs` and `--mic` were all re-run, so nothing is hand-patched any more.
Note `--droid-hal` was genuinely required: the installer scripts and
`hybris-boot.img` are taken from the *built rootfs*, i.e. from the droid-hal
package, so a config-only rebuild would have shipped the old bzip2 installer
alongside a gzip rootfs.

## Still to do — NOT COMMITTED

- **`/init-debug` is removed by the installer as a workaround.** With
  `ed28449` in place (no reboot on missing USB) it should be safe to keep it,
  so the `rm -f` in `updater-unpack.sh` can probably be dropped — but that
  needs testing on a rebuilt image before trusting it.
- **App-grid icons** — root cause found: `theme_pixel_ratio` only rescales
  Silica's metrics. The launcher icons come from
  `/usr/share/themes/sailfish-default/silica/z<scale>/icons/`, which is shipped
  by `sailfish-content-graphics-{default,closed}-z<scale>`, and the image had
  only the **z1.0** packs installed. Installing the z1.75 packs and restarting
  lipstick fixed it live. No source change needed: the pattern already has
  `Requires: sailfish-content-graphics-z%{icon_res}` and `icon_res` derives from
  `pixel_ratio`, so the rebuild pulls the right pack on its own. Verify after
  the rebuild that `/usr/share/icons/hicolor` and the z1.75 icon dir are
  populated.

## AUDIO — SOLVED (headphones *and* speaker), committed

Both outputs confirmed working by ear: headphones and the phone's own speaker,
music through PulseAudio. Committed as `c761abd` (droid-configs) and `5dff0a6`
(droid-configs-device) — a rebuild picks it all up, no manual steps.

My earlier verdict, "32-bit HAL, structurally impossible", was **wrong**, and
worth recording why: I concluded "zero mixer controls" from `amixer` output when
`amixer` was not installed. There are **381 controls** and the RT5665 codec is
fully attached. The HAL's bitness was never the problem — the problem was that
*nothing was applying the mixer routing*, which on Android is the HAL's job.

Three real causes:

1. **No routing applied.** `/vendor/etc/mixer_paths.xml` holds the vendor's own
   values; with no HAL nothing walks it, so the card is routed nowhere with
   `DAC1 Playback Volume` at **0**. Note these are `cset`-only controls —
   `amixer sset` returns success on them while changing nothing.
2. **48 kHz only.** At 44.1 kHz `hw_ptr` does not advance at all (0 → 34 in
   three seconds, versus 90150 → 138268 at 48 kHz). PulseAudio defaults to 44.1.
3. **No PCM timestamps.** `tstamp` stays `0.000000000`, so PulseAudio's
   timer-based scheduling never advances and streams die with "Failed to drain
   stream: Timeout" while the DMA runs fine. `tsched=0` fixes it.

### Shipped in the image

- `/usr/bin/droid/droid-audio-route.sh` + `droid-audio-route.service`
  (enabled via `multi-user.target.wants`) — applies the routing at boot.
  Verified by knocking the mixer back to silence and re-running it.
- `/etc/pulse/daemon.conf.d/50-a51-48k.conf` — pins 48 kHz.
- `droid.pa` — `module-udev-detect tsched=0`.

### Board revision matters

This phone is A51 board **REV01**, which carries a **Richtek RT5510** amp. REV02
switched to a TI TAS2562. Samsung's DTBO holds one overlay per revision and only
the REV02 entry declares the TI part — verified by splitting the stock dtbo into
its four entries (REV00, REV00A, REV01, REV02). The RT5510 driver is already
enabled (`CONFIG_SND_SOC_RT5510=y`) and binds itself at i2c `7-0034`, so no
kernel change was needed. **A REV02 device will need the TAS2562 path instead** —
the routing script should ideally detect which amp is bound rather than assume.

### Known limitations

- **No route switching on jack plug/unplug.** Jack detection was the HAL's job;
  both paths are enabled simultaneously, so the speaker also plays while
  headphones are inserted. Proper handling needs a jack-detect watcher driving
  the two routes.
- **Earpiece works** (confirmed by ear). The vendor calls it **handset**, not
  receiver, which is why searching mixer_paths.xml for "receiver" found nothing.
  Its path is `DAC L2 Mux = IF1 DAC2` plus `Mono DAC MIXL DAC L2 Switch`,
  `Mono MIX DAC L2 Switch`, `Mono Playback Switch` and `RECEIVER Switch` —
  note it runs off **DAC L2**, not DAC1, so enabling the DAC1 chain leaves it
  silent however many mono switches you set. `Mono Playback Switch` is also
  distinct from `Mono Playback Volume`.
  Selectable with `droid-audio-route.sh handset`; off by default since it is a
  call path. In-call audio from the modem should land here naturally.
- The vendor drives the speaker from RDMA7 → SIFS1 → UAIF2; RDMA7 cannot be
  opened here (`-EIO` every time), so UAIF2 is fed from SIFS0. Worth revisiting
  if someone wants the vendor's exact topology.

## hw-features file — SOLVED

`ssu-sysinfo` globs `/usr/share/csd/settings.d/*hw-settings*.ini` and, per
feature, does:

    val = inifile_get(cfg, "features", hw_feature_to_csd_key(id), 0);
    supported = (strtol(val, 0, 0) != 0);

Two details are why several guesses failed:

1. **The keys are CSD names, not the `Feature_*` names ssu-sysinfo prints back.**
   Acceleration is `GSensor`, compass is `ECompass`, gyro is `Gyro`, proximity is
   `ProxSensor`, WLAN is `Wifi`. The full table is `hw_feature_csd_key_lut` in
   `lib/hw_feature.c`.
2. **The value goes through `strtol`.** `= true` therefore parses as **0** and
   disables the feature while looking entirely reasonable in the file.

The section name `[features]` was right all along; the earlier attempts failed on
those two points, and the release build has logging compiled out so
`SSUSYSINFO_LOG_LEVEL` produced nothing to go on. Reading the source settled it.

Shipped as `sparse/usr/share/csd/settings.d/99-a51-hw-settings.ini` (`d96f1f8`).
`ssu-sysinfo --hw-features` now reports 27 features instead of 2.

What it fixed:

- **The adaptive brightness toggle is back in Settings** — it is conditional on
  `Feature_LightSensor`.
- Sensor availability resolves through the stock config path instead of relying
  on the `[available]` override, which is now belt-and-braces rather than the
  only thing holding sensors up.
- **Bluetooth is declared absent on purpose**, so the UI stops offering hardware
  that panics this kernel. NFC, FM radio, fingerprint, proximity and the
  notification LED are absent or unsupported; GPS is untested, so unadvertised.

What it did **not** fix: raw `accelerometersensor`, `gyroscopesensor` and
`compasssensor` still return session -1 with *"not registered"*, re-tested with
the file in place. That is an adaptor-level failure against the Android HAL, and
`alssensor`/`orientationsensor` work from the same HAL, so the next step is the
HAL's sensor list — reachable via the Waydroid container's working logd.

## Android apps — Waydroid groundwork

Jolla's App Support is proprietary and licensed to Jolla hardware; it is not an
option here. Waydroid is the only legitimate route.

Kernel prerequisites are now in the defconfig (`CONFIG_VETH`, `CONFIG_BRIDGE`,
`CONFIG_USER_NS`) but **untested** — treat a boot test as mandatory, since on
this tree `CONFIG_BT=y` reset the device mid-boot and `CONFIG_RFKILL=m` silently
disabled Wi-Fi. Already present and working: binderfs (`binder-control` exists),
`ANDROID_BINDER_IPC`, `ASHMEM`, cgroups, namespaces.

Still needed after that, none of it done:

- LXC is not installed, and Waydroid is not packaged for 5.1.0.11 (Chum's newest
  target is 5.0.0.76). Either build from source or try the 5.0.0.76 packages.
- A Waydroid Android image (~700 MB) matching the Waydroid version.
- The hard part: Waydroid needs GPU access through gralloc/hwcomposer, and on a
  hybris port droid-hal-init already owns those HALs for lipstick. Contention
  here is the most likely reason for the whole thing to fail.
- Audio would still be silent regardless.

Honest odds: this is a multi-hour bring-up with a real chance of not working.

## Waydroid — progress and the kernel bug it exposed

Working so far (all on the live device):

- Built `python3-gbinder` for **Python 3.11**; Chum only ships a 3.8 build, which
  is why `zypper` called it "not installable" on 5.1.0.11. Its spec also needed
  `%{!?sailfishos_version: ...}` or rpmbuild cannot even parse the `%if`.
  Committed in `hybris/mw/gbinder-python` (`5c46552`).
- Installed the Chum 5.0.0.76 stack: `waydroid` 1.4.3, `waydroid-runner`,
  `waydroid-gbinder-config-hybris`, `lxc` 6.0.3, `python3-gobject`.
- **Kernel bug found:** this tree declares `struct binderfs_device` with
  `__u8 major/minor` where mainline and AOSP use `__u32`. sizeof is therefore
  258, not 264, so `BINDER_CTL_ADD` encodes a different ioctl number and *any*
  userspace built against the real UAPI header gets EINVAL when allocating a
  binder device. That is why `waydroid init` failed with
  `Binder node "binder" for waydroid not found`. It also truncates the major
  number, which is 510 here. Fixed to `__u32` in
  `include/uapi/linux/android/binderfs.h` (`ff7c1ea817c8`) — with that in place
  Waydroid needs no patching.
- Worked around it live by issuing the ioctl with the 258-byte struct, which
  created `puddlejumper` / `vndpuddlejumper` / `hwpuddlejumper`. Those are the
  dedicated nodes `waydroid-gbinder-config-hybris` expects, so Waydroid gets its
  own binder domains and does not fight droid-hal-init.
- `waydroid init` then proceeded and is downloading the LineageOS 20 VANILLA
  arm64 image (905 MB).

Still unknown: whether the container renders. Waydroid needs gralloc/hwcomposer
access that lipstick already holds, and that is the part most likely to fail.

Note Waydroid probes `/dev/<node>`, not `/dev/binderfs/<node>`, so the symlinks
into `/dev/` matter. Also `waydroid init` runs its binder probe *before* vendor
type detection, so it takes the MAINLINE path even though `ro.vndk.version` is
33 (which would give HALIUM_13).

## Android apps — the part I had structurally wrong

Waydroid runs, boots Android 13, and its apps appear as ordinary Sailfish
launcher icons. Getting **touch** to work took three wrong diagnoses, so the
mechanism is worth writing down exactly.

**On Sailfish, `waydroid-runner` must host the Android surface.** It is not a
convenience wrapper: it is a *nested Wayland compositor*
(`QWaylandQuickCompositor` + `libwayland-server`, in a Silica window). It
publishes its own Wayland socket, the container's hwcomposer connects to that
instead of lipstick's, and it forwards touch into the nested surface --
`/usr/share/waydroid-runner/qml/WindowContainer.qml`, `touchEventsEnabled = true`.

Running `waydroid show-full-ui` straight against lipstick's socket also puts
Android on screen, full size, looking completely correct — **and it accepts no
touch at all**, silently:

- The container's hwcomposer opens each `/dev/input/wl_*_events` pipe lazily, on
  the first event of that type. `wl_keyboard_events` therefore ends up open
  (compositors send keyboard focus/modifier events unprompted) while
  `wl_touch_events` is never opened, because lipstick never sends touch to that
  foreign surface.
- Android's side is meanwhile perfect: `dumpsys input` shows a `wayland_touch`
  device, `Classes: TOUCH_MT`, `Enabled: true`, reading the right pipe. It is
  listening to a pipe nobody writes to.
- Nothing logs an error anywhere.

Two further traps found on the way, both real:

- **Launcher entries need `X-Nemo-Application-Type=no-invoker` and
  `[X-Sailjail] Sandboxing=Disabled`** (copy `waydroid-runner.desktop`). Without
  the first, lipstick launches the entry through the Sailfish invoker booster,
  which expects a Qt binary; a shell script never maps a window, so the spinner
  just stops and the icon disappears. Omitting the Sailjail *section* does not
  mean "unsandboxed" — the `Sandboxing=Disabled` line is what does that, and a
  sandboxed wrapper cannot reach the session socket under `/run/display`.
- **An app started before the Android display exists gets no input channel.**
  WindowManager reports `mCurrentFocus` set while InputDispatcher's
  `FocusedWindows` list is empty; the app draws and ignores touch. So the host
  goes up first, and the app is requested afterwards.

`waydroid-container` is only a *manager* service: the LXC container itself does
not run until a user session attaches, so "container active, no Android
processes" is the normal idle state rather than a fault. Closing the Waydroid
window kills the runner but leaves the session bound to a socket that died with
it — such a session accepts intents and shows nothing, so it must be stopped
before a new runner can host anything. `waydroid-app-launch.sh` handles both.

### Not in the image, and cannot be

Waydroid itself is **not** shipped: it needs the Chum packages, a rebuilt
`python3-gbinder` for Python 3.11, and a ~900 MB LineageOS image download. The
image ships the kernel fix (`binderfs` `__u32`), the binder-node prep service,
the launcher-entry generator and the launch wrapper — the parts that cannot be
installed afterwards. Android app support therefore stays a documented
post-install step, not something that works out of the box.

## Audio: the boot-time race that made a fresh install silent

Worth recording because everything reported success. `droid-audio-route.service`
ran at 16:24:25 and its log showed every control applied; the jack watcher
correctly chose the speaker route; and the phone was mute, with
`DAC1 Playback Volume` back at **0**.

The ABOX DSP downloads its firmware the first time the card is opened, and that
resets every codec register. `/proc/asound/card0` appears seconds into boot — so
the route script's wait was satisfied long before the card was really up — and
PulseAudio opened the card at 16:24:27, two seconds after the routing had been
applied. Neither PulseAudio restarts nor playback reset the mixer afterwards, so
this is a one-shot event early in boot, which is exactly why it never showed up
while testing by hand.

Fixed by making `droid-jack-watch.py` guard the routing as well as watch the
jack: it waits on the input device with a timeout instead of blocking, and
re-applies the route whenever `DAC1 Playback Volume` reads zero. Verified by
zeroing the mixer by hand — repaired within six seconds. Committed as `93cdd20`.

## Sensors — all working, and a wrong verdict corrected

All seven hand out sessions: accelerometer, gyroscope, compass, magnetometer,
rotation, ALS and orientation.

I had recorded accelerometer/gyroscope/compass as broken at the adaptor level,
citing sensorfwd's *"requested sensor id not registered"*. That was a **test
artifact**: sensorfw loads sensor plugins on demand, so `requestSensor` before
`loadPlugin` fails by design. Call `loadPlugin` first and every sensor works —
which is what real clients (Qt's sensor plugin) do anyway, so apps were never
affected.

What settled it was sensorfwd's own debug log, which has to be read from the
journal rather than stdout (`sensorfwd -c=/etc/sensorfw/primaryuse.conf
--log-level=debug`, then `journalctl`):

    HYBRIS CTL getDelay(1=ACCELEROMETER) -> 160000
    HYBRIS CTL setDelay(1=ACCELEROMETER, 100000) -> success

The adaptor was talking to the HAL and setting rates the whole time. Two lessons
worth keeping: sensorfwd logs to the journal, not to a file or stdout; and the
sensor plugins load lazily, so probing them in the wrong order reports failures
that do not exist.

Note the hybris adaptors reach the HAL over **binder** (`libgbinder`), not
libhardware, and Samsung's `sensors.sensorhub.so` sub-HAL serves accel, gyro,
magnetometer and light.

## The installer bug that a real flash found, and the trap behind it

A flash of the finished image failed like this:

    mount: Failed to mount /dev/block/by-name/userdata at /data: Device or resource busy
    Copying filesystem archive ...
    tar: /data/sailfishos-rootfs.tar.gz: No such file or directory
    extraction produced no rootfs in /data/.stowaways/sailfishos
    script aborted: Failed to extract filesystem!

(The mount line is harmless — TWRP already has `/data` mounted.)

Switching the rootfs to gzip changed `updater-unpack.sh` to read
`/data/sailfishos-rootfs.tar.gz` but left `updater-script` copying the archive to
`/data/sailfishos-rootfs.tar.bz2`. Two halves of the same change, one updated.
Fixed in `898f1a8`.

**Worse: the failure was destructive.** `updater-unpack.sh` did `rm -rf` on the
destination *before* checking the archive existed, so a wrong filename wiped a
working installation. That is exactly what happened — the phone's rootfs, Waydroid
setup and all, was deleted by a failed install. The archive check now comes first,
so a failed install leaves the previous system alone.

The extraction check added earlier did earn its keep: the installer aborted
*before* writing `hybris-boot.img`, so the boot partition still pointed at a
system that could be restored rather than a kernel over an empty rootfs.

### The trap: `out/` staging, not the source repo

Fixing the source and rebuilding **did nothing**, twice. `droid-hal-a51-img-boot`
packages the *staged* copies at
`out/target/product/$DEVICE/hybris-updater-{script,unpack.sh}`, and the staging
step substitutes `%DEVICE%`, `%BOOT_PART%`, `%DATA_PART%` and the device assert —
so the files cannot simply be copied by hand either. Editing
`hybris/hybris-boot/*` requires re-running the Android make inside the HABUILD
chroot before `--droid-hal` sees it:

    ubu-chroot -r /parentroot/srv/sailfishos/sdks/ubuntu -- bash -c \
      'source ~/.hadk.env; cd $ANDROID_ROOT; source build/envsetup.sh; \
       breakfast $DEVICE; make hybris-updater-script hybris-updater-unpack'

Note the module names carry **no extension**: `hybris-updater-unpack`, not
`hybris-updater-unpack.sh` — ninja rejects the latter outright.

This is the same class of mistake as "tar_git builds from git HEAD, so
uncommitted edits are ignored": what the build reads is not where you edited.

## Bluetooth: Samsung gutted the HCI socket layer

The long-standing verdict here was "Samsung never compiled `net/bluetooth` in this
tree, and it panics in `bt_sock_create`". Half of that was wrong, and the truth is
more actionable.

Reproduced deliberately: load `bluetooth.ko` (which loads cleanly and registers
L2CAP/SCO/HCI in `/proc/net/protocols`), then open a single AF_BLUETOOTH socket:

    python3 -c "import socket; socket.socket(31, socket.SOCK_RAW, 1)"

The phone resets instantly. `pstore` captured it — note the panic writes no
`dmesg-ramoops`, so read `console-ramoops-0` instead:

    kernel BUG at net/bluetooth/af_bluetooth.c:71!
    PC is at bt_sock_create+0x194/0x1a0 [bluetooth]

Line 71 is `BUG_ON(!sk)` inside `bt_sock_reclassify_lock`. It fires because the
protocol's `create()` returned **success while leaving `sock->sk` NULL** — and the
reason is that Samsung **commented out the body** of the HCI socket functions and
left `return 0;` behind:

    static int hci_sock_create(struct net *net, struct socket *sock, ...)
    {
        /*
    	struct sock *sk;
    	... the entire real implementation ...
        */
    	return 0;
    }

Five functions in `net/bluetooth/hci_sock.c` are gutted this way — `create`,
`bind`, `ioctl`, `getname`, `release` — i.e. exactly the HCI socket interface
BlueZ needs. The gutting is deliberate and careful: inner `/* */` comments were
rewritten as `//` so the outer block comment would not terminate early. Samsung
ships its own Bluetooth stack through the HAL, so the kernel socket layer was
surplus to them.

Everything else in `net/bluetooth` is intact. Functions elsewhere that look
stubbed (`l2cap_check_efs` returning true, `l2cap_resegment` returning 0,
`hci_leds_init`, `hci_free_dev`) are genuine upstream code with doc comments.

**Fix**: uncomment the five bodies. For `ioctl`, `bind` and `getname` the real
body already ends in `return err;`, so the leftover stub `return 0;` has to go as
well; for `create` and `release` the trailing `return 0;` *is* the original
ending. Braces and comment markers balance afterwards (174/174, 44/44).

**Status: WORKING.** Note `CONFIG_LOCALVERSION_BRANCH_SHA=y` puts the
git SHA in the version string, so committing the fix changes the module vermagic
and the rebuilt `bluetooth.ko` will not load into a kernel built from the previous
commit — the boot image has to be flashed together with the modules.

### Bluetooth: confirmed working end to end

After restoring `hci_sock.c` (`e3db1870ca10`) and flashing the rebuilt kernel:

- an AF_BLUETOOTH socket opens and closes cleanly — no reset
- `bluebinder` bridges `android.hardware.bluetooth@1.0-service` onto `/dev/vhci`
  ("Successfully initialized vhci bluetooth")
- BlueZ reads the controller's real address, **XX:XX:XX:XX:XX:XX** — one digit off
  the Wi-Fi MAC, as the SCSC combo chip allocates
- A2DP, AVRCP and HFP profile UUIDs register
- a scan finds real devices with names, SDP UUIDs and RSSI, including the
  development PC by name

Three traps worth recording:

1. **`rfkill` soft-blocks the adapter**, so `Powered=true` fails with
   `org.bluez.Error.Blocked` until `/sys/class/rfkill/rfkillN/soft` is cleared for
   the `bluetooth` type. This is normal — the UI toggle handles it — but it looks
   like a driver failure from the command line.
2. **Discovery is owned by the calling D-Bus client.** `dbus-send` exits the
   instant it returns, so BlueZ immediately tears the scan down:
   `discovery_disconnect() owner :1.226` followed by Stop Discovery. `Discovering`
   reads `false` and scans look broken while the stack is perfectly fine. Use
   `bluetoothctl` (or any client that stays connected).
3. Panics here write no `dmesg-ramoops` — read `console-ramoops-0`.

Also needed in the image, and none of it was there: `bluebinder`, `bluez5`,
`bluez5-tools`. The port had been *masking* `bluebinder.service` while the package
was absent. Committed with `Feature_Bluetooth = 1` in `8f8b23f`.

## The startup wizard hang — self-inflicted, and how it was found

Symptom: on a fresh install the setup wizard would stick, most visibly on the
Jolla account page — the UI stayed responsive but Next/Skip did nothing, and only
"sometimes".

Cause: advertising `Feature_Bluetooth = 1` made the UI and PulseAudio start
reaching for `org.bluez`, but `bluetooth` and `hci_vhci` are **modules** in this
kernel and nothing loaded them at boot. Without `/dev/vhci`, bluebinder exits
immediately:

    bluebinder: Failed to open /dev/vhci device — Error: 19 (No such device)
    dbus-daemon: Failed to activate service 'org.bluez': timed out (25000ms)
    pulseaudio: bluez5-util.c: GetManagedObjects() failed: NoReply

So every D-Bus caller touching `org.bluez` blocked for the full 25 s activation
timeout. That is exactly a dead button that later works, and "sometimes" because
it depended on which page happened to touch Bluetooth. Fixed by
`/etc/modules-load.d/50-a51-bluetooth.conf`; a clean install now reports **zero**
`org.bluez` activation timeouts.

This is the third instance of the same mistake in this port — the others being
`alsa-utils` and `ofono-binder-plugin`. In each case a feature was validated on a
phone where the missing piece had been installed or loaded **by hand while
debugging**, and the image was never checked. Testing a clean install is the only
thing that catches it.

### Persistent logging earned its place

The first report of this bug had **no logs at all**: the port ships
`Storage=volatile`, so the journal died with the reboot that followed the hang.
Switching to `Storage=persistent` (60 MB cap) turned an unreproducible complaint
into a one-pass diagnosis, and it is now shipped.

### RemainAfterExit silently defeats a timer

`droid-user-groups.service` exists because the first-boot wizard rewrites group
membership after the boot-time run, so a timer re-applies it. With
`Type=oneshot` **plus `RemainAfterExit=yes`** the unit stays `active (exited)`
forever, and starting an already-active unit is a no-op — the timer fired exactly
on schedule and did nothing. Verified on a clean install: timer ran at +4 min, the
service logged nothing, the group was still missing. `RemainAfterExit` removed.

Note also that `systemctl daemon-reload` does not reset a unit's active state, so
after changing this you must `stop` then `start` for the new definition to run.

### Two cosmetic findings

- The developer page does not populate the WLAN address until something triggers a
  refresh — a screen off/on is enough. It is a UI refresh quirk, not a networking
  or connman fault (I initially blamed connman's ofono timeout; wrong).
- `connmand: [ofonoext] ERROR! Timeout was reached` appears on every boot. That is
  connman waiting on the modem that never completes its handshake; it delays
  network-related pages rather than blocking them, and it will go away with the
  telephony fix.
