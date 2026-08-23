#!/bin/bash
# Build hybris-hal WITHOUT root: enters the HABUILD (Ubuntu 20.04) rootfs with
# bubblewrap using an unprivileged user namespace, instead of ubu-chroot's
# sudo+chroot. Same rootfs, same prebuilts, same out/ dir - so artifacts are
# interchangeable with an interactive `sfossdk` + `ubu-chroot` session.
UBU=/srv/sailfishos/sdks/ubuntu
LOG=$HOME/a51-sfos-port/logs/hybris-hal-build.log
mkdir -p "$(dirname "$LOG")"
JOBS=${JOBS:-8}

[ -x "$UBU/bin/bash" ] || { echo "!! $UBU is not unpacked"; exit 1; }
# --- pre-flight: repo sync recreates manifest linkfiles whose upstream targets no
# --- longer exist (external/chromium-webview/Android.mk), and kati dies including
# --- them. Prune before every build so a sync can't silently break the build again.
pruned=0
while IFS= read -r l; do rm -f "$l" && pruned=$((pruned+1)); done < <(
  find "$HOME/hadk" -maxdepth 6 -xtype l \
    \( -name 'Android.mk' -o -name 'Android.bp' -o -name 'CleanSpec.mk' \) \
    -not -path "$HOME/hadk/.repo/*" -not -path "$HOME/hadk/out/*" 2>/dev/null)
[ "$pruned" -gt 0 ] && echo ">> pruned $pruned dangling build-file symlink(s)" | tee -a "$LOG"

# --- pre-flight: the single-fstab file and the hybris patches must be in place
[ -f "$HOME/hadk/device/samsung/a51/fstab.hybris-a51" ] || \
  echo "!! device/samsung/a51/fstab.hybris-a51 missing - run 4-post-sync.sh" | tee -a "$LOG"
if [ "$(git -C "$HOME/hadk/bionic" log --oneline -40 2>/dev/null | grep -c -E '\(hybris\)|halium')" = 0 ]; then
  echo "!! hybris patches not applied - run 4-post-sync.sh" | tee -a "$LOG"; exit 1
fi

echo "=== bwrap build start $(date -Is) jobs=$JOBS ===" >> "$LOG"

exec bwrap \
  --bind "$UBU" / \
  --bind "$HOME" "$HOME" \
  --proc /proc --dev /dev --tmpfs /tmp --tmpfs /dev/shm --tmpfs /var/tmp \
  --ro-bind /sys /sys \
  `# the rootfs ships /etc/resolv.conf as a dangling symlink, so binding onto it
   # fails; the build needs no DNS, only apt would, and that already ran` \
  --setenv HOME "$HOME" --setenv USER "$USER" --setenv LC_ALL C.UTF-8 \
  --chdir "$HOME/hadk" \
  /bin/bash -c '
    set -o pipefail
    . "$HOME/.hadk.env"
    export PATH=$HOME/bin:$PATH
    export USE_CCACHE=1
    # LineageOS product lists modules whose repos are not in the hybris manifest
    # (webview, apns-conf.xml, SimpleSettingsConfig). We build hybris-hal, not a
    # full ROM, so downgrade that hard error to a warning (main.mk:1300).
    export ALLOW_MISSING_DEPENDENCIES=true
    cd "$ANDROID_ROOT" || exit 1
    . build/envsetup.sh >/dev/null
    breakfast "$DEVICE" >/dev/null 2>&1
    : "${LINEAGE_BUILD:=$DEVICE}"; export LINEAGE_BUILD
    echo ">> TARGET_PRODUCT=$TARGET_PRODUCT LINEAGE_BUILD=$LINEAGE_BUILD ALLOW_MISSING_DEPENDENCIES=$ALLOW_MISSING_DEPENDENCIES"
    make -j'"$JOBS"' hybris-hal droidmedia
    rc=$?
    echo ">> make rc=$rc"
    ls -la out/target/product/$DEVICE/hybris-boot.img out/target/product/$DEVICE/hybris-recovery.img 2>/dev/null
    exit $rc
  ' >> "$LOG" 2>&1
