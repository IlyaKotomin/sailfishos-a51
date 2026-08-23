#!/bin/bash
# Run this ON THE HOST (Fedora). Needs sudo for the chroot extraction + mounts.
# Installs the already-downloaded Sailfish Platform SDK. Nothing is downloaded here.
set -e
TARBALL=$HOME/a51-sfos-port/downloads/Jolla-latest-SailfishOS_Platform_SDK_Chroot-i486.tar.bz2
export PLATFORM_SDK_ROOT=/srv/sailfishos

[ -f "$TARBALL" ] || { echo "missing $TARBALL"; exit 1; }
echo ">> extracting $(du -h "$TARBALL" | cut -f1) SDK rootfs into $PLATFORM_SDK_ROOT/sdks/sfossdk"
sudo mkdir -p "$PLATFORM_SDK_ROOT/sdks/sfossdk"
sudo tar --numeric-owner -p -C "$PLATFORM_SDK_ROOT/sdks/sfossdk" -xjf "$TARBALL"

echo ">> done. Now open a new shell (or: exec bash) and run:  sfossdk"
echo ">> inside the SDK you should see the prompt 'PlatformSDK ... HABUILD-ready' and 'Env setup for a51'"
