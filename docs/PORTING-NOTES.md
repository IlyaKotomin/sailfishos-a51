# Porting notes

Findings from bringing this port up. Several are not device-specific and may help
anyone on a recent Samsung/Exynos base or a modern Android vendor.

Each entry is **symptom → cause → fix**, because the symptoms here were
consistently misleading: the most expensive mistakes came from believing a
component that reported success.

---

## Bluetooth panics the kernel on the first socket

**Symptom.** `bluetooth.ko` loads cleanly and registers L2CAP/SCO/HCI in
`/proc/net/protocols`. Opening a single AF_BLUETOOTH socket resets the phone
instantly:

```python
python3 -c "import socket; socket.socket(31, socket.SOCK_RAW, 1)"
```

**Cause.** Not "Samsung never compiled it" — they *gutted* it. The bodies of the
HCI socket functions in `net/bluetooth/hci_sock.c` are commented out with a bare
`return 0;` left behind:

```c
static int hci_sock_create(struct net *net, struct socket *sock, ...)
{
    /*
	struct sock *sk;
	... the entire real implementation ...
    */
	return 0;
}
```

Five functions are hollowed out this way — `create`, `bind`, `ioctl`, `getname`,
`release` — plus the helpers they call (`hci_sock_gen_cookie`,
`hci_sock_free_cookie`, `hci_sock_bound_ioctl`,
`create_monitor_ctrl_open`/`close`). It is deliberate and careful work: the inner
`/* */` comments were rewritten as `//` so the outer block comment would not
terminate early. Samsung ships Bluetooth through the Android HAL, so the kernel
socket layer was surplus to them.

So `hci_sock_create()` returns **success while leaving `sock->sk` NULL**, and
`bt_sock_reclassify_lock()` hits `BUG_ON(!sk)`:

```
kernel BUG at net/bluetooth/af_bluetooth.c:71!
PC is at bt_sock_create+0x194/0x1a0 [bluetooth]
```

**Fix.** Restore the file from upstream v4.14.150 verbatim
(`patches/kernel/0008-*`). Diffing Samsung's against upstream shows *only*
comment markers, `//`-rewritten inner comments and the stub returns — nothing
device-specific. `hci_sec_filter` is upstream BlueZ code, not a Samsung addition.

**Then, in userspace:** `bluebinder` bridges the Android HAL onto `/dev/vhci`,
and `bluetooth`/`hci_vhci` are **modules** — load them at boot or bluebinder
exits with errno 19 and `bluetoothd` never activates.

Two traps while testing:

- **rfkill soft-blocks the adapter**, so `Powered=true` fails with
  `org.bluez.Error.Blocked` until `/sys/class/rfkill/rfkillN/soft` is cleared.
  The UI toggle does this; from a shell it looks like a driver fault.
- **Discovery is owned by the calling D-Bus client.** `dbus-send` exits the
  instant it returns, so BlueZ tears the scan down immediately
  (`discovery_disconnect() owner :1.226`). `Discovering` reads `false` and scans
  look broken while the stack is perfectly healthy. Use `bluetoothctl`.

**Reading the panic:** these resets write **no `dmesg-ramoops`**. The trace is in
`/sys/fs/pstore/console-ramoops-0`.

---

## `logcat` never works, and dozens of Android services abort

**Symptom.** `logd` crash-loops every five seconds, `logcat` returns nothing, and
a single boot produces ~90 SIGABRTs:

```
logd: failed to set background scheduling policy: No such file or directory
libprocessgroup: Failed to read task profiles from /etc/task_profiles.json
open() failed for /dev/cgroup_info/cgroup.rc: No such file or directory
```

**Cause, part one.** Android's init calls `CgroupSetup()` during early boot:
it mounts each controller where `/etc/cgroups.json` says, creates the groups
`/etc/task_profiles.json` references, and writes a binary map to
`/dev/cgroup_info/cgroup.rc`. **droid-hal-init skips all of it**, so
libprocessgroup cannot find any controller, and every service that sets a
scheduling policy aborts.

**Cause, part two — and this one was self-inflicted.** The obvious fix is to make
`/etc/cgroups.json` and `/etc/task_profiles.json` available, since on Android
`/etc` *is* `/system/etc`. Symlinking them **does not work**: libbase's
`ReadFileToString()` opens with `O_NOFOLLOW` unless explicitly told otherwise.

```c
int flags = O_RDONLY | O_CLOEXEC | O_BINARY | (follow_symlinks ? 0 : O_NOFOLLOW);
```

A symlink therefore reads as missing. They must be **copies**.

**Fix.** `droid-cgroup-setup.py` does the setup droid-hal-init skips:

- bind-mounts each controller from where systemd put it onto the Android path
  (`/dev/cpuctl`, `/dev/cpuset`, `/dev/memcg`, `/dev/blkio`, `/acct`,
  `/dev/freezer`) — a v1 controller can only live in one hierarchy, so binding is
  the only option
- creates the ~126 group directories the task profiles reference
- writes `cgroup.rc` in the format from
  `system/core/libprocessgroup/cgrouprc_format`: an 8-byte header
  (`version=1`, `controller_count`) followed by one 56-byte record per
  controller (`uint32 version`, `uint32 flags`, `char name[16]`,
  `char path[32]`), matching `WriteRcFile()`

and `droid-dynparts.sh` **copies** the two JSON files instead of linking them.

The payoff is larger than logging: those ~90 aborts stop, and rild's own output
becomes visible, which is the only way to make progress on the modem.

---

## Audio on a device with no usable audio HAL

Samsung's `audio.primary.exynos9611.so` is 32-bit only, so 64-bit PulseAudio can
only dlopen the AOSP stub. Nothing walks `/vendor/etc/mixer_paths.xml`, so the
card comes up routed nowhere with `DAC1 Playback Volume` at **0** — which looks
exactly like "this device has no audio support" until you read the mixer. It has
**381 controls** and a fully attached Realtek RT5665 codec.

Three separate causes had to be fixed:

1. **Nothing applies the routing.** `droid-audio-route.sh` walks the vendor's own
   values from `mixer_paths.xml`. Note these are `cset`-only controls —
   **`amixer sset` returns success on them while changing nothing**.
2. **48 kHz only.** At 44.1 kHz `hw_ptr` does not advance at all (0 → 34 in three
   seconds, versus 90150 → 138268 at 48 kHz). PulseAudio defaults to 44.1, so it
   must be pinned.
3. **No PCM timestamps.** `tstamp` stays `0.000000000`, so PulseAudio's
   timer-based scheduling never advances and streams die with "Failed to drain
   stream: Timeout" while the DMA runs fine. `tsched=0` fixes it.

**The ABOX DSP resets the mixer.** `/proc/asound/card0` appears seconds into
boot, so a route applied at boot is wiped when the DSP downloads its firmware on
the card's first open. The jack watcher therefore doubles as a guard: it waits on
the jack input device with a timeout and re-applies the route whenever
`DAC1 Playback Volume` reads zero.

**`alsa-utils` must be in the image.** Both scripts shell out to `amixer`.
Without it every mixer command fails *while the script still exits 0 and its
service reports success* — a silent, fully "successful" mute.

**Jack detection** was the HAL's job too. The kernel exposes the jack twice: as
`/sys/class/switch/h2w/state` and as an input device reporting `EV_SW`. Watch the
input device (so it blocks instead of polling) but read the switch node once at
startup, or a phone booted with headphones inserted comes up on the speaker.

**Board revision matters.** This is board **REV01** with a **Richtek RT5510**
amp; REV02 switched to a TI TAS2562, and only the REV02 DTBO overlay declares the
TI part. The routing script detects which amp's controls exist.

**The earpiece is called `handset`**, not `receiver`, and runs off **DAC L2**
(fed from `IF1 DAC2`) — not DAC1, so enabling the DAC1 chain leaves it silent
however many mono switches you set.

---

## The CSD hardware-features file decides what Settings shows

**Symptom.** Every sensor disabled in sensorfw; no adaptive-brightness toggle in
Settings; `ssu-sysinfo --hw-features` reports only `Feature_Suspend` and
`Feature_Reboot`.

**Cause.** `/usr/share/csd/settings.d/*hw-settings*.ini` does not exist, so every
feature lookup falls back to unsupported.

**Fix, and the two things that make it resist guessing.** ssu-sysinfo does:

```c
val = inifile_get(cfg, "features", hw_feature_to_csd_key(id), 0);
supported = (strtol(val, 0, 0) != 0);
```

1. The keys are **CSD names, not the `Feature_*` names ssu-sysinfo prints back**.
   Acceleration is `GSensor`, compass is `ECompass`, gyro is `Gyro`, proximity is
   `ProxSensor`, WLAN is `Wifi`. The full table is `hw_feature_csd_key_lut` in
   `lib/hw_feature.c`.
2. The value goes through **`strtol`**, so the obvious `= true` parses as **0**
   and disables the feature while looking entirely reasonable.

The section name `[features]` was right all along. Getting this file correct took
`ssu-sysinfo` from 2 advertised features to 30, and it is also how you *hide*
hardware — declaring `Bluetooth = 0` kept the UI from offering a radio that used
to panic the kernel.

---

## sensorfw plugins load lazily

`requestSensor` before `loadPlugin` fails with *"requested sensor id ... not
registered"* — by design. Probing in the wrong order reports broken sensors that
work perfectly for real clients (Qt's sensor plugin loads then requests). Call
`loadPlugin` first.

Also: sensorfwd logs to the **journal**, not stdout or a file, and it is started
with `-c=/etc/sensorfw/primaryuse.conf` — not just the `conf.d` files. Its debug
output is where the truth is:

```
HYBRIS CTL setDelay(1=ACCELEROMETER, 100000) -> success
```

---

## The `binderfs` UAPI bug

This tree declares `struct binderfs_device` with `__u8 major/minor` where
mainline and AOSP use `__u32`. `sizeof` is therefore 258, not 264, so
`BINDER_CTL_ADD` encodes a *different ioctl number* and any userspace built
against the real UAPI header gets `EINVAL` when allocating a binder device. It
also truncates the major number, which is 510 here.

This is why `waydroid init` failed with `Binder node "binder" for waydroid not
found`. Fixed in `patches/kernel/0006-*`; with it, Waydroid needs no patching and
correctly detects `HALIUM_13` instead of falling back to the mainline path.

---

## Installer traps (hybris-boot)

Four separate bugs, each of which produced a phone that would not boot:

1. **TWRP has no `bzip2`.** Busybox `tar -j` forks an external bzip2 and many
   TWRP builds do not ship it — and it **exits 0 anyway**, so the installer
   flashes the kernel over a rootfs that was never extracted. Ship the rootfs as
   **gzip**, and verify the extraction actually produced a rootfs before writing
   the boot image.
2. **`run_debug_session()` must not `reboot -f`.** It is called on every normal
   boot from the post-`switch_root` path, and on this device the USB gadget
   deliberately cannot come up, so rebooting "because there is no debug channel"
   bootloops the phone forever.
3. **Copy the rootfs to the name the unpacker reads.** Switching to gzip changed
   the unpacker to read `.tar.gz` while the updater-script still copied to
   `.tar.bz2`. Two halves of one change; only one updated.
4. **A failed install must not be destructive.** The unpacker did `rm -rf` on the
   destination *before* checking the archive existed, so a wrong filename wiped a
   working installation.

Plus one packaging trap: **`zip` adds to an existing archive** rather than
replacing it, so a zip left over from a previous build keeps its old entries — one
release came out at 1.08 GB containing *two* rootfs archives.

**And the trap behind all of them:** `droid-hal-*-img-boot` packages the **staged
copies** at `out/target/product/$DEVICE/hybris-updater-{script,unpack.sh}`, and
staging substitutes `%DEVICE%`, `%BOOT_PART%`, `%DATA_PART%` and the device
assert — so editing `hybris/hybris-boot/*` does nothing until the Android make
re-stages it, and the files cannot be hand-copied either:

```bash
ubu-chroot -r /parentroot/srv/sailfishos/sdks/ubuntu -- bash -c \
  'source ~/.hadk.env; cd $ANDROID_ROOT; source build/envsetup.sh; \
   breakfast $DEVICE; make hybris-updater-script hybris-updater-unpack'
```

Note the module names carry **no extension** — `hybris-updater-unpack`, not
`...unpack.sh`; ninja rejects the latter outright.

---

## Dynamic partitions and the modem

The device uses Android dynamic partitions (dm-linear inside `super`). Before any
of the Android side works you need, all in `droid-dynparts.sh`:

- **`/dev/block/by-name/*` links.** Build them from each block device's
  `uevent` `PARTNAME`, which is available before udev settles:
  ```sh
  for _sys in /sys/class/block/*/; do
      [ -f "${_sys}partition" ] || continue
      _pname=$(sed -n 's/^PARTNAME=//p' "${_sys}uevent")
      ln -sf "/dev/$(basename "$_sys")" "/dev/block/by-name/$_pname"
  done
  ```
- **ueventd ownership.** The nodes need the owners `ueventd.rc` specifies —
  `radio:system` and friends — or `cbd` and `rild` cannot open them.
- **`/dev/block/param`**, which the modem loader expects.
- **`mkdir -p /system` before the bind mount.** A clean rootfs has no `/system`,
  so the bind silently fails and the entire Android side is missing — the device
  sits on the Samsung splash with no clue why.

With those in place the modem *hardware* comes up: `cbd` boots it to `ONLINE` and
`/mnt/vendor/efs` mounts with real calibration data. What still does not work is
rild completing the handshake — see [HARDWARE.md](HARDWARE.md).

---

## Waydroid on Sailfish

**The Android surface must be hosted by `waydroid-runner`.** It is not a
convenience launcher: it is a nested Wayland compositor
(`QWaylandQuickCompositor` + `libwayland-server` in a Silica window) that
publishes its own socket, has the container's hwcomposer connect to *that*, and
forwards touch into the nested surface (`WindowContainer.qml`:
`touchEventsEnabled = true`).

Run `waydroid show-full-ui` against lipstick's socket instead and Android appears
at full resolution, correctly oriented, redrawing smoothly — **and ignores every
touch**. The container's hwcomposer opens each `/dev/input/wl_*_events` pipe
lazily, on the first event of that type; compositors send keyboard focus events
unprompted so `wl_keyboard_events` ends up open, while `wl_touch_events` never
does. `dumpsys input` meanwhile shows a perfectly healthy `wayland_touch` device
reading a pipe with no writer. Nothing logs an error.

Also:

- **Launcher entries that run a shell script need
  `X-Nemo-Application-Type=no-invoker`**, or lipstick starts them through the
  Sailfish invoker booster, which expects a Qt binary — the script never maps a
  window, the spinner stops and the icon vanishes. They also need
  `[X-Sailjail] Sandboxing=Disabled`; *omitting* the Sailjail section does not
  mean unsandboxed.
- **An activity started before the display exists gets no input channel.**
  WindowManager reports `mCurrentFocus` set while `dumpsys input`'s
  `FocusedWindows` is empty, and the app ignores touch. Bring the host up first.
- **`CONFIG_NETFILTER_XT_TARGET_CHECKSUM`** is required: Waydroid's network
  script adds an iptables CHECKSUM rule and **aborts the whole network setup**
  when the target is missing, so the session never starts.
- `waydroid-container` is only a *manager* service — the LXC container does not
  run until a user session attaches, so "service active, no Android processes" is
  the normal idle state.

---

## systemd and packaging lessons

- **`RemainAfterExit=yes` silently defeats a timer.** A `Type=oneshot` unit stays
  `active (exited)` forever, and starting an already-active unit is a no-op — so
  the timer fires exactly on schedule and does nothing.
- **`systemctl daemon-reload` does not reset a unit's active state.** After
  changing such a unit you must `stop` then `start`.
- **Ship scripts executable.** A `0644` script fails with `status=203/EXEC`, and
  testing it as `python3 script.py` never exercises the execute bit.
- **journald is `Storage=volatile` by default**, so anything that goes wrong
  before a reboot leaves nothing to read. For a port under development that is
  the wrong trade.
- **tar_git builds from git HEAD** — uncommitted edits are silently ignored.
- **The first-boot wizard rewrites group membership**, discarding anything added
  earlier in boot.

---

## SELinux

The stock firmware's policy has to be compiled on-device: `secilc` links against
the bootstrap linker so it runs before APEX activation, and the resulting image
must be loaded in a **single `write()`** — `cat` splits it into chunks and the
kernel rejects it. Permissive is fine; the point is to give the checks a policy
to consult. Once `/etc/selinux/config` exists, D-Bus needs a `dbus_contexts`
file or it will not start.

---

## Unresolved

- **Telephony.** rild runs, maps `libsec-ril.so`, has 19 threads, and never opens
  `/dev/umts_ipc0`. With logcat working it is visibly looping on
  `Run(): nlmsg_type = 16` (netlink `RTM_NEWLINK`) at the same ~5 s cadence as the
  modem's `CP_START` retries.
- **The lipstick screenshot API** refuses callers with *"PID N is not in
  privileged group"* even when the calling process genuinely has gid 995 and
  lipstick has been restarted. Android's own `screencap` inside the Waydroid
  container works and needs no privileges — use that for anything Android-side.
- **Waydroid audio quality.** Raising AudioFlinger's standby delay from 3 s to
  300 s stopped the PulseAudio stream being destroyed after every brief silence
  (churn went from every ~5 s to twice in 30 s), but playback is still poor and
  pitched high. Every declared parameter agrees end to end — 48 kHz, 2 ch,
  `S16_LE`, `Resample method: n/a`, zero underruns — so something feeds data at a
  rate it does not declare. A tone of known frequency through the container would
  identify the ratio.
