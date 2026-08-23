# Troubleshooting

Symptoms seen during development, and what they actually were. Most were *not*
what they looked like.

## Boot and install

**Phone sits on the Samsung splash after installing.**
The rootfs was never extracted, or `/system` was not bind-mounted. Historically
two causes: TWRP's busybox `tar -j` needing an external `bzip2` it does not have
(and exiting 0 anyway), and a clean rootfs having no `/system` directory to bind
onto. Both are fixed in current images; if you see it, check
`/data/.stowaways/sailfishos` from TWRP — if it is empty or tiny, the extraction
failed.

**Bootloop.** `run_debug_session()` used to `reboot -f` when the USB debug
interface could not be brought up — and on this device it never can, because the
gadget panics the kernel. Fixed; a current image never reboots for that reason.

**The install failed and now nothing boots.** Older installers removed the
destination *before* checking the archive, so a failed install wiped a working
system. Current ones check first. Recovery is just reflashing the zip.

## Networking and access

**No WLAN address on the developer page.** Turn the screen off and on. The page
does not repaint by itself; the address lookup is fine.

**The USB address does not work.** It never will — the port refuses to bring up
the USB gadget because writing the configfs gadget panics the kernel through
Samsung's `conn_gadget_cleanup`. `192.168.2.15` on that page is a hardcoded label.
Use Wi-Fi.

**SSH refuses your password after reinstalling or re-running the wizard.** The
developer-mode password is not carried over. Set it again under Settings →
Developer tools.

**The phone seems unreachable.** It does not answer ping at all, and its Wi-Fi is
slow to wake — a sleeping screen can drop the association far enough that even a
TCP handshake times out. Use generous timeouts and wake the screen before
concluding anything.

## Audio

**Total silence, but every service reports success.** Check that `amixer` exists:

```bash
which amixer || zypper install alsa-utils
grep FAIL /var/log/audio-route.log
```

Both audio services shell out to `amixer`. Without it every mixer command fails
while the script still exits 0.

**Silence only after a fresh boot.** The ABOX DSP resets the mixer when the card
is first opened, wiping a route applied earlier in boot. The jack watcher
re-applies it when `DAC1 Playback Volume` reads zero — check it is running:

```bash
systemctl status droid-jack-watch
journalctl -u droid-jack-watch -b | tail
```

**Re-apply the routing by hand:**

```bash
/usr/bin/droid/droid-audio-route.sh speaker      # or headphones / handset / all
```

**Volumes seem to change on their own.** Sailfish keeps a separate volume per
media role (ringtone, notification, media, keyboard feedback, alarm). The same
sound played through a different role is a different volume — by design.

## Bluetooth

**`Powered=true` fails with `org.bluez.Error.Blocked`.** rfkill soft-block:

```bash
for r in /sys/class/rfkill/rfkill*; do
    [ "$(cat $r/type)" = bluetooth ] && echo 0 > $r/soft
done
```

**Scanning finds nothing / `Discovering` stays false.** Discovery is owned by the
calling D-Bus client, and `dbus-send` exits the moment it returns, so BlueZ tears
the scan straight back down. Use `bluetoothctl` and keep it open.

**No adapter at all.** `bluebinder` needs `/dev/vhci`, which only exists once
`hci_vhci` is loaded:

```bash
lsmod | grep -E 'bluetooth|hci_vhci'
systemctl status bluebinder      # "Failed to open /dev/vhci device" = modules missing
```

## The UI stalls for ~25 seconds at a time

Something is waiting on a D-Bus service that never activates. The classic case
here was `org.bluez`: with `Feature_Bluetooth` advertised but the Bluetooth
modules not loaded, every caller touching `org.bluez` blocked for the full
activation timeout — which presented as a setup wizard whose *Next* button did
nothing, intermittently.

```bash
journalctl -b | grep 'Failed to activate service'
```

## Sensors

**A sensor "does not exist".** Load the plugin before requesting it —
`requestSensor` before `loadPlugin` fails by design:

```bash
D="dbus-send --system --print-reply --dest=com.nokia.SensorService /SensorManager"
$D local.SensorManager.loadPlugin string:accelerometersensor
$D local.SensorManager.requestSensor string:accelerometersensor int64:1234
```

A session id ≥ 0 means it works. sensorfwd's own diagnostics go to the
**journal**, not stdout.

## Logging

**`logcat` returns nothing / `logd` crash-loops.** The cgroup setup is missing:

```bash
ls -l /dev/cgroup_info/cgroup.rc          # should be 400 bytes
systemctl status droid-cgroup-setup
ls -l /etc/task_profiles.json             # must be a real file, NOT a symlink
```

A symlink there cannot be read by libbase (`O_NOFOLLOW`), which makes every
Android service that sets a scheduling policy abort.

**Journald is volatile by default**, so a crash leaves nothing after the reboot.
Current images set `Storage=persistent` with a 60 MB cap.

**Kernel panics write no `dmesg-ramoops`** — read
`/sys/fs/pstore/console-ramoops-0` for the previous boot's console instead.

## Screenshots

The lipstick D-Bus screenshot API may refuse with *"PID N is not in privileged
group"* even when the caller genuinely is. For anything Android-side, use the
container's own capture, which needs no privileges:

```bash
lxc-attach -P /var/lib/waydroid/lxc -n waydroid -- /system/bin/screencap -p /data/local/tmp/s.png
```

Otherwise take screenshots from the UI with the hardware keys.

## Telephony

Not working, and not a configuration problem you can fix from userspace. For the
record, what a healthy-looking-but-broken modem looks like here:

```bash
cat /sys/devices/platform/10000.mif_pdata/modem_state   # ONLINE
dmesg | grep rild_ready                                 # umts_ipc0.opened=0, forever
dbus-send --system --print-reply --dest=org.ofono / org.ofono.Manager.GetModems
logcat -d | grep RILD                                   # Run(): nlmsg_type = 16
```

`ofono-binder-plugin` must be installed or ofono reports zero modems regardless —
but installing it does not fix the underlying handshake.
