# Android apps (Waydroid)

Jolla's App Support is proprietary and licensed to Jolla hardware, so it is not
available here. **Waydroid works**: Android 13 (LineageOS 20) on the phone's real
GPU, through its own gralloc and hwcomposer.

This is a post-install step and cannot be otherwise — Waydroid downloads a
~900 MB Android image of its own, and its packages come from Chum. What the image
*does* ship is the part you could not add afterwards: the kernel `binderfs` fix,
the binder-node preparation service, the launcher-entry generator and the launch
wrapper.

## Setup

**1. Add Chum** (see [INSTALL.md](INSTALL.md) — its signing key is not in the
device trust store, so scope signature checking off for that repo).

**2. Install the Python 3.11 build of `python3-gbinder` first.**

Chum's `python3-gbinder` requires `python(abi) = 3.8` and this device has 3.11, so
zypper refuses the entire Waydroid install with:

```
nothing provides 'python(abi) = 3.8' needed by python3-gbinder
```

A 3.11 build is published alongside the image. Its spec also needs
`%{!?sailfishos_version: ...}` or rpmbuild cannot even parse the `%if`.

```bash
zypper install --allow-unsigned-rpm python3-gbinder-*.aarch64.rpm
```

**3. Install Waydroid:**

```bash
zypper install waydroid waydroid-runner waydroid-gbinder-config-hybris lxc python3-gobject
```

**4. Initialise** (downloads ~900 MB):

```bash
waydroid init -s VANILLA
```

This should detect `HALIUM_13` on its own. If it fails with
`Binder node "binder" for waydroid not found`, the kernel is missing the
`binderfs` `__u32` fix — see [PORTING-NOTES.md](PORTING-NOTES.md).

**5. Work around the missing CHECKSUM target.** Waydroid's network script adds an
iptables rule needing `CONFIG_NETFILTER_XT_TARGET_CHECKSUM` and **aborts the
whole network setup** without it, so the session never starts:

```
RuntimeError: Command failed: /usr/lib/waydroid/data/scripts/waydroid-net.sh start
Warning: Extension CHECKSUM revision 0 not supported, missing kernel module?
```

Either build the kernel with that option, or make the two rules non-fatal by
appending `|| true` to the `-j CHECKSUM --checksum-fill` lines in
`/usr/lib/waydroid/data/scripts/waydroid-net.sh`.

**6. Start it** and generate launcher icons:

```bash
systemctl start waydroid-container
waydroid session start &                 # as your user, with XDG_RUNTIME_DIR=/run/display
/usr/bin/droid/droid-waydroid-desktop.py # as root, writes one .desktop per app
```

## Installing an APK

```bash
waydroid app install /path/to/app.apk
/usr/bin/droid/droid-waydroid-desktop.py   # refresh the launcher entries
```

Firefox for Android is a good test — real ARM64 Gecko, far newer than the native
browser's ESR 91:

```bash
curl -LO https://archive.mozilla.org/pub/fenix/releases/154.0/android/\
fenix-154.0-android-arm64-v8a/fenix-154.0.multi.android-arm64-v8a.apk
waydroid app install fenix-154.0.multi.android-arm64-v8a.apk
```

## Launching apps

**Always launch through the Waydroid icon or an app icon.** Running
`waydroid show-full-ui` by hand puts Android on screen looking perfectly correct
— and it will not accept a single touch. `waydroid-runner` is a nested Wayland
compositor that forwards touch into the container; bypass it and the surface
belongs to lipstick, which never sends touch to it. Nothing in the stack reports
an error when this happens.

The shipped `waydroid-app-launch.sh` handles this: it reuses a running runner,
clears a session left behind by a closed one, and asks Android for the app only
after the display exists (an activity started earlier gets no input channel).

First launch of an app takes up to a minute — the container has to boot Android
before it will accept an intent, and `waydroid app launch` retries against
`waydroidplatform` while that happens.

## Known limitations

- **App icons are all the Waydroid logo.** Android icons live inside APKs and
  cannot be read out without unpacking them; the *names* are correct.
- **Audio is poor.** Sound crosses Android's mixer → PulseAudio → this port's
  HAL-less ALSA routing, and it is noticeably worse than native playback, with a
  pitch shift that is still unexplained (see
  [PORTING-NOTES.md](PORTING-NOTES.md)). Raising AudioFlinger's standby delay
  helps the worst of it:
  ```bash
  waydroid shell setprop ro.audio.flinger_standbytime_ms 300000
  ```
  The default of 3 s destroys the PulseAudio stream after every brief silence.
- **Volume keys reach both systems.** Android adjusts its own stream volume on
  top of Sailfish's, which makes the volume bar flicker between ringtone and
  media context. Pinning Android's `STREAM_MUSIC` to maximum makes Sailfish the
  only effective control.
- **Everything is lost on reflash.** The container and its Android image live in
  the rootfs that gets replaced, so this setup has to be repeated after an
  update.
