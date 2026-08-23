#!/bin/bash
# Installs the Sailfish SDK tooling + aarch64 build target.
# Run this INSIDE the Platform SDK:
#     host$ sfossdk
#     PlatformSDK$ ~/a51-sfos-port/11-sdk-target-install.sh
set -e
VER=5.1.0.11
BASE=https://releases.sailfishos.org/sdk/targets

# --- guard: sdk-assistant only exists inside the Platform SDK ---
if ! command -v sdk-assistant >/dev/null 2>&1; then
  . /etc/os-release 2>/dev/null
  echo "!! Not inside the Platform SDK (no sdk-assistant here)."
  echo "!! Detected: ${NAME:-unknown} ${VERSION_ID:-}"
  echo
  echo "   Enter it first, then re-run:"
  echo "     sfossdk"
  echo "     ~/a51-sfos-port/11-sdk-target-install.sh"
  exit 1
fi
[ "$(id -u)" != 0 ] || { echo "!! don't run this as root - sdk-assistant refuses"; exit 1; }
echo ">> inside: $(. /etc/os-release; echo "$NAME $VERSION_ID")"

if sdk-assistant list 2>/dev/null | grep -q "SailfishOS-$VER\$"; then
  echo ">> tooling SailfishOS-$VER already present"
else
  echo ">> creating tooling SailfishOS-$VER (455 MiB download)"
  sdk-assistant tooling create -y "SailfishOS-$VER" \
    "$BASE/Sailfish_OS-$VER-Sailfish_SDK_Tooling-i486.tar.7z"
fi

if sdk-assistant list 2>/dev/null | grep -q "SailfishOS-$VER-aarch64"; then
  echo ">> target SailfishOS-$VER-aarch64 already present"
else
  echo ">> creating target SailfishOS-$VER-aarch64 (187 MiB download)"
  sdk-assistant target create -y "SailfishOS-$VER-aarch64" \
    "$BASE/Sailfish_OS-$VER-Sailfish_SDK_Target-aarch64.tar.7z"
fi

# HADK's build_packages.sh addresses the target as $VENDOR-$DEVICE-$PORT_ARCH,
# not by the SDK's version-based name. Clone it under the name it expects
# (local copy, no download).
. "$HOME/.hadk.env"
HADK_TARGET="$VENDOR-$DEVICE-$PORT_ARCH"
if sdk-assistant list 2>/dev/null | grep -q "$HADK_TARGET"; then
  echo ">> target $HADK_TARGET already present"
else
  echo ">> cloning SailfishOS-$VER-aarch64 -> $HADK_TARGET (what build_packages.sh expects)"
  sdk-assistant target clone "SailfishOS-$VER-aarch64" "$HADK_TARGET"
fi

echo
echo ">> installed:"
sdk-assistant list
echo
echo ">> next: ~/a51-sfos-port/5-bootstrap-droid-hal.sh  (also inside the Platform SDK)"
