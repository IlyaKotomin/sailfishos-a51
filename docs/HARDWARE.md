# Hardware status

Every row says **how** it was verified, because "should work" and "works" are
different claims. Anything not personally observed is marked untested rather than
assumed.

## Working

| Hardware | How it was verified |
|---|---|
| Boot to the Sailfish UI | Installed from the flashable zip and booted repeatedly |
| Display, 1080×2400 | In continuous use |
| Touchscreen, multitouch | In continuous use |
| Brightness control | `mcetool`, and the Settings slider |
| UI scaling | `theme_pixel_ratio = 1.75` with the matching `z1.75` icon pack |
| Wi-Fi | `wlan0` with an address; the port was developed over SSH on it |
| **Bluetooth** | Adapter `hci0` with the controller's real address; a scan returned real devices with names, SDP UUIDs and RSSI |
| **NFC** | Read a MIFARE Classic 1k card: serial `5C:3F:42:BB`, SAK `0x08`, ATQA `0x0004` |
| **`logcat`** | `logcat -d` returns log lines; `logd` stops crash-looping |
| **Audio — speaker** | By ear |
| **Audio — earpiece** | By ear |
| **Audio — headphones** | By ear |
| **Jack detection** | Insert → headphones on, speaker off; removal → speaker. Verified in the watcher's log both ways |
| Audio survives the DSP reset | Mixer zeroed by hand; the guard restored it within 6 s |
| **Sensors (all 7)** | `accelerometersensor`, `gyroscopesensor`, `compasssensor`, `magnetometersensor`, `rotationsensor`, `alssensor`, `orientationsensor` each granted a sensorfwd session |
| Auto-rotation | Rotating the device rotates the UI |
| Adaptive brightness toggle | Appears in Settings once `Feature_LightSensor` is advertised; off by default |
| Cameras, rear and front | Both produce images |
| Battery and charging | `/sys/class/power_supply/battery`: capacity, status, health |
| Vibration | `ngfd` active, vibrator nodes present |
| Power and volume keys | In use |
| SSH / developer mode | The whole port was developed over it |
| Android apps | Waydroid with Firefox 154 running — see [ANDROID-APPS.md](ANDROID-APPS.md) |

## Not working

| Hardware | Why |
|---|---|
| **Telephony** | Samsung's `cbd` boots the modem to `ONLINE` and `rild` runs with `libsec-ril.so` mapped, but rild never opens `/dev/umts_ipc0`, so the kernel loops `rild_ready: umts_ipc0.opened=0` and ofono's binder plugin gets `RADIO_NOT_AVAILABLE` on both slots. With `logcat` now working, rild is visibly spinning on `Run(): nlmsg_type = 16` (netlink `RTM_NEWLINK`). Unresolved |
| **Fingerprint reader** | In-display sensor, no Sailfish support for it on this device |
| **USB networking** | The port deliberately refuses to bring up the USB gadget: writing the configfs gadget panics the kernel through Samsung's `conn_gadget_cleanup`. The USB address shown on the developer page is a hardcoded label with nothing behind it — use Wi-Fi |

## Untested

- **Calls and SMS** — blocked by the modem above
- **Mobile data** — same
- **Microphone recording** — capture devices exist (`WDMA0`–`WDMA3`); no successful recording made
- **Camera flash / torch, video recording**
- **An actual GPS fix** — the stack is present and running (`geoclue-provider-hybris-binder`, Samsung's `gpsd` and `vendor.samsung.hardware.gnss@2.0-service`), and the feature is advertised so Settings shows Location, but no fix was ever confirmed under open sky
- **SD card slot** — no card was inserted during development
- **MTP / USB file transfer** — likely broken for the same reason as USB networking

## Quirks that are not faults

- **The phone does not answer ping**, and its Wi-Fi is slow to wake. A closed
  screen can drop the association far enough that even a TCP handshake times out.
  It is reachable; short probes lie.
- **The developer page shows no WLAN address until something refreshes it** — a
  screen off/on is enough. The address lookup is fine; the page just does not
  repaint.
- **Keyboard feedback has its own volume**, separate from ringtone and media, so
  the same click can sound different after a profile change. That is Sailfish's
  per-role volume model, not a bug.
- **`connmand: [ofonoext] ERROR! Timeout was reached`** appears every boot. It is
  connman waiting on the dead modem; it delays some network pages, nothing more.
- **Android's `gpu` service crash-loops** with a `libgpuwork.so` BpfMap abort. It
  needs eBPF maps droid-hal-init does not create. Nothing on Sailfish uses it.
