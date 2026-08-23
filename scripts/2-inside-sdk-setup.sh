#!/bin/bash
# Run this INSIDE the Sailfish Platform SDK.
#   host$ exec bash        # pick up the sfossdk alias
#   host$ sfossdk          # you are now in the SDK (prompt: PlatformSDK ...)
#   PlatformSDK$ ~/a51-sfos-port/2-inside-sdk-setup.sh
set -e

# --- guard: refuse to run on the host -------------------------------------
if ! command -v zypper >/dev/null 2>&1; then
  echo "!! This is NOT the Sailfish Platform SDK - no zypper here."
  echo "!! You appear to be on: $(. /etc/os-release 2>/dev/null; echo "$NAME $VERSION_ID")"
  echo
  echo "   Enter the SDK first, then re-run this script:"
  echo "     exec bash"
  echo "     sfossdk"
  echo "     ~/a51-sfos-port/2-inside-sdk-setup.sh"
  exit 1
fi
echo ">> inside SDK: $(. /etc/os-release; echo "$NAME $VERSION_ID")"

# --- work out where the SDK lives, as seen from in here -------------------
if [ -n "$PLATFORM_SDK_ROOT" ] && [ -d "$PLATFORM_SDK_ROOT/sdks" ]; then
  SDKS="$PLATFORM_SDK_ROOT/sdks"
elif [ -d /parentroot/srv/sailfishos/sdks ]; then
  SDKS=/parentroot/srv/sailfishos/sdks
else
  echo "!! cannot locate the SDK 'sdks' directory from inside the chroot."
  echo "   PLATFORM_SDK_ROOT='$PLATFORM_SDK_ROOT'"; ls -d /parentroot/srv/* 2>/dev/null
  exit 1
fi
echo ">> sdks dir: $SDKS"

echo ">> refreshing repos (adaptation0 will fail: it is an ssu plugin repo that needs"
echo "   D-Bus, which does not exist in a chroot - harmless here, we continue)"
sudo zypper --non-interactive ref || true

echo ">> installing HADK tools (android-tools-hadk kmod createrepo_c)"
# zypper returns 106 (ZYPPER_EXIT_INF_REPOS_SKIPPED) when any repo was skipped -
# adaptation0 always is in here - so 0 and 106 both mean "install went fine".
rc=0
sudo zypper --non-interactive in android-tools-hadk kmod createrepo_c || rc=$?
case "$rc" in
  0|106) echo "   zypper rc=$rc (ok)" ;;
  *)     echo "   !! zypper failed with rc=$rc"; exit "$rc" ;;
esac

echo ">> verifying the tools actually landed"
for t in ubu-chroot createrepo_c; do
  if command -v "$t" >/dev/null 2>&1; then echo "   OK   $t -> $(command -v $t)"
  else echo "   FAIL $t not found"; exit 1; fi
done

TARBALL=$HOME/a51-sfos-port/downloads/ubuntu-focal-20210531-android-rootfs.tar.bz2
UBUNTU_CHROOT="$SDKS/ubuntu"
[ -f "$TARBALL" ] || { echo "!! missing $TARBALL"; exit 1; }

if [ -x "$UBUNTU_CHROOT/bin/bash" ]; then
  echo ">> Ubuntu chroot already unpacked at $UBUNTU_CHROOT, skipping"
else
  echo ">> unpacking $(du -h "$TARBALL" | cut -f1) Ubuntu focal chroot into $UBUNTU_CHROOT"
  sudo mkdir -p "$UBUNTU_CHROOT"
  sudo tar --numeric-owner -xjf "$TARBALL" -C "$UBUNTU_CHROOT"
fi

# The HADK guide runs `chage -M 999999 $(id -nu 1000)` here, but that fails on a
# fresh rootfs: your account does not exist in the chroot yet. ubu-chroot injects
# it (prepare_user) on first entry, so password aging can only be fixed after that
# - and only if sudo inside HABUILD actually complains. Non-fatal either way.
CHROOT_USER=$(awk -F: '$3==1000 {print $1}' "$UBUNTU_CHROOT/etc/passwd" 2>/dev/null)
if [ -n "$CHROOT_USER" ]; then
  sudo chroot "$UBUNTU_CHROOT" /bin/bash -c "chage -M 999999 $CHROOT_USER" \
    && echo ">> password aging disabled for '$CHROOT_USER' inside the chroot" \
    || echo ">> note: chage failed, harmless unless sudo misbehaves in HABUILD"
else
  echo ">> no uid-1000 user in the chroot yet (expected) - ubu-chroot adds yours on entry"
fi

echo
echo ">> verify with:"
echo "     ubu-chroot -r $UBUNTU_CHROOT"
echo "   prompt should read:  HABUILD_SDK [a51]"
