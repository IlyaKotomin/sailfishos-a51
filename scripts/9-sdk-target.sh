#!/bin/bash
# Install the Sailfish SDK tooling + aarch64 build target, unprivileged.
# Enters the Platform SDK rootfs with bubblewrap and fake-root (--uid 0); works
# because /srv/sailfishos is user-owned. No sudo, no sdk-chroot.
SDK=/srv/sailfishos/sdks/sfossdk
LOG=$HOME/a51-sfos-port/logs/sdk-target.log
VER=5.1.0.11
BASE=https://releases.sailfishos.org/sdk/targets
mkdir -p "$(dirname "$LOG")"
echo "=== sdk target install start $(date -Is) ===" >> "$LOG"

bwrap --bind "$SDK" / --bind "$HOME" "$HOME" \
  --bind /srv/sailfishos/targets /srv/mer/targets \
  --bind /srv/sailfishos/toolings /srv/mer/toolings \
  --proc /proc --dev /dev --tmpfs /tmp --tmpfs /dev/shm --ro-bind /sys /sys \
  --unshare-user --uid 0 --gid 0 \
  --setenv HOME "$HOME" --setenv LC_ALL C.UTF-8 --chdir "$HOME" \
  /bin/bash -c "
    set -x
    sdk-assistant tooling create -y SailfishOS-$VER \
      $BASE/Sailfish_OS-$VER-Sailfish_SDK_Tooling-i486.tar.7z
    sdk-assistant target create -y SailfishOS-$VER-aarch64 \
      $BASE/Sailfish_OS-$VER-Sailfish_SDK_Target-aarch64.tar.7z
    echo '--- installed ---'
    sdk-assistant list
  " >> "$LOG" 2>&1
echo "=== rc=$? $(date -Is) ===" >> "$LOG"
