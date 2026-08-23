#!/bin/bash
# Run INSIDE the HABUILD (Ubuntu) chroot:
#   PlatformSDK$ ubu-chroot -r /parentroot/srv/sailfishos/sdks/ubuntu
#   HABUILD_SDK [a51]$ ~/a51-sfos-port/6-habuild-build.sh
#
# Builds the Android HAL bits Sailfish needs. Safe to re-run; it resumes.
set -e
LOG=$HOME/a51-sfos-port/logs/hybris-hal-build.log
mkdir -p "$(dirname "$LOG")"

# --- guard: must be the Ubuntu chroot, not the SDK and not Fedora ------------
. /etc/os-release 2>/dev/null
if [ "$ID" != "ubuntu" ]; then
  echo "!! This is not the HABUILD chroot (found: $NAME $VERSION_ID)."
  echo "   From the Platform SDK run:"
  echo "     ubu-chroot -r /parentroot/srv/sailfishos/sdks/ubuntu"
  exit 1
fi
echo ">> HABUILD: $NAME $VERSION_ID"

source "$HOME/.hadk.env"
export PATH=$HOME/bin:$PATH
[ -d "$ANDROID_ROOT" ] || { echo "!! ANDROID_ROOT=$ANDROID_ROOT missing"; exit 1; }
echo ">> DEVICE=$DEVICE  ANDROID_ROOT=$ANDROID_ROOT"

echo ">> checking build prerequisites"
MISSING=""
for t in cpio bc bison flex rsync zip unzip python3 git make gcc; do
  command -v "$t" >/dev/null 2>&1 || MISSING="$MISSING $t"
done
if [ -n "$MISSING" ]; then
  echo ">> installing:$MISSING"
  sudo apt-get update -qq
  sudo apt-get install -y $MISSING
else
  echo "   all present"
fi

cd "$ANDROID_ROOT"
echo ">> sourcing envsetup + breakfast $DEVICE"
set +e
source build/envsetup.sh
export USE_CCACHE=1
# LineageOS's product lists modules whose repos the hybris manifest omits
# (webview, apns-conf.xml, SimpleSettingsConfig). hybris-hal does not need them;
# this downgrades main.mk:1300's hard error to a warning.
export ALLOW_MISSING_DEPENDENCIES=true
# NOTE: do NOT pipe breakfast into tee - a pipeline runs in a subshell and every
# variable lunch exports (TARGET_PRODUCT, LINEAGE_BUILD, ...) would be lost, which
# makes config.mk skip vendor/lineage/config/BoardConfigLineage.mk and soong then
# dies on "unknown variable '$(PATH_OVERRIDE_SOONG)'". Process substitution keeps
# breakfast in this shell.
breakfast "$DEVICE" > >(tee -a "$LOG") 2>&1
bf=$?
if [ "$bf" != 0 ]; then
  echo "!! breakfast failed (rc=$bf) - see $LOG"
  echo "   usually a missing repo or a device-tree dependency; the tail is:"
  tail -20 "$LOG"; exit "$bf"
fi

echo ">> lunch env: TARGET_PRODUCT=$TARGET_PRODUCT  LINEAGE_BUILD=$LINEAGE_BUILD"
if [ -z "$LINEAGE_BUILD" ]; then
  echo ">> LINEAGE_BUILD was empty - exporting it manually (needed by config.mk:360)"
  export LINEAGE_BUILD="$DEVICE"
fi
[ -n "$TARGET_PRODUCT" ] || { echo "!! TARGET_PRODUCT empty, lunch env did not survive"; exit 1; }

echo ">> building: make -j8 hybris-hal droidmedia   (this takes a while)"
make -j8 hybris-hal droidmedia 2>&1 | tee -a "$LOG"
rc=${PIPESTATUS[0]}
echo ">> make rc=$rc"

echo ">> outputs:"
ls -la out/target/product/$DEVICE/hybris-boot.img \
       out/target/product/$DEVICE/hybris-recovery.img 2>/dev/null || \
  echo "   (images not produced yet)"
[ "$rc" = 0 ] && echo ">> next: kernel config check (Task 7)" || {
  echo "!! build failed. Last 40 lines:"; tail -40 "$LOG"; }
exit "$rc"
