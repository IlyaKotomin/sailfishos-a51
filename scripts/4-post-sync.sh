#!/bin/bash
# Run after `repo sync` finishes. Verifies the tree and applies the a51
# fixup-mountpoints stanza generated from the live device.
set -e
source "$HOME/.hadk.env"
cd "$ANDROID_ROOT"

echo "=== 1. device/kernel/vendor trees present? ==="
for f in device/samsung/a51/BoardConfig.mk \
         device/samsung/universal9611-common/BoardConfigCommon.mk \
         kernel/samsung/universal9611/Makefile \
         vendor/samsung/a51/a51-vendor.mk \
         hybris/hybris-boot/fixup-mountpoints \
         hybris/mer-kernel-check/mer_verify_kernel_config; do
  [ -e "$f" ] && echo "  OK   $f" || { echo "  MISS $f"; MISSING=1; }
done
[ -n "$MISSING" ] && { echo ">> tree incomplete - re-run repo sync"; exit 1; }

echo "=== 2. confirm the kernel config the build will use ==="
grep -H TARGET_KERNEL_CONFIG device/samsung/a51/BoardConfig.mk
ls -la kernel/samsung/universal9611/arch/arm64/configs/vendor/a51-aosp_defconfig

echo "=== 2a. hybris patches applied? ==="
# 62 patches in hybris-patches/ retarget bionic/system-core/frameworks/... for
# libhybris. The manifest pulls plain LineageOS repos, so they are NOT pre-applied,
# and skipping this yields missing modules and weird init behaviour later.
applied=$(git -C "$ANDROID_ROOT/bionic" log --oneline -40 2>/dev/null | grep -c -E '\(hybris\)|halium')
if [ "${applied:-0}" -gt 0 ]; then
  echo "   already applied ($applied hybris commits in bionic)"
else
  echo "   applying hybris-patches/apply-patches.sh --mb"
  ( cd "$ANDROID_ROOT" && ./hybris-patches/apply-patches.sh --mb ) || {
    echo "   !! patch application failed - fix conflicts, then re-run"; exit 1; }
fi
total=0
for d in bionic system/core system/apex frameworks/av frameworks/native build/make hardware/libhardware; do
  n=$(git -C "$ANDROID_ROOT/$d" log --oneline -60 2>/dev/null | grep -c -E '\(hybris\)|halium')
  total=$((total+n))
done
echo "   $total/$(find "$ANDROID_ROOT/hybris-patches" -name '*.patch' | wc -l) patches present"

echo "=== 2b. prune dangling build-file symlinks created by manifest linkfiles ==="
# The hybris-20.0 manifest still declares linkfiles that upstream repos have since
# deleted (e.g. external/chromium-webview/Android.mk, removed by LineageOS commit
# 091983e). repo recreates the symlink on every sync; kati then dies with
# "No such file or directory" while including it. Prune the dead ones.
pruned=0
while IFS= read -r l; do
  rm -f "$l" && { echo "   removed dangling $l"; pruned=$((pruned+1)); }
done < <(find "$ANDROID_ROOT" -maxdepth 6 -xtype l \
           \( -name 'Android.mk' -o -name 'Android.bp' -o -name 'CleanSpec.mk' \) \
           -not -path "$ANDROID_ROOT/.repo/*" -not -path "$ANDROID_ROOT/out/*" 2>/dev/null)
[ "$pruned" = 0 ] && echo "   none dangling"

echo "=== 2c. ensure hybris-boot sees exactly one fstab ==="
# hybris/hybris-boot/Android.mk derives HYBRIS_BOOT_PART/HYBRIS_DATA_PART by scanning
# fstabs. device/samsung/a51 has none, so it falls back to scanning all of
# device/samsung, which contains BOTH fstab.exynos9611 (/dev/block/by-name/..., the
# form this device really uses) and fstab.exynos9610 (platform/13520000.ufs form).
# Two candidates -> "one and only one device entry for HYBRIS_DATA_PART". Placing the
# authoritative fstab in the device dir short-circuits the fallback scan.
A51_FSTAB="$ANDROID_ROOT/device/samsung/a51/fstab.hybris-a51"
SRC_FSTAB="$ANDROID_ROOT/device/samsung/universal9611-common/configs/init/fstab.exynos9611"
if [ -f "$A51_FSTAB" ]; then
  echo "   already present: ${A51_FSTAB#$ANDROID_ROOT/}"
elif [ -f "$SRC_FSTAB" ]; then
  { echo "# Copy of fstab.exynos9611 so hybris-boot finds exactly one fstab."
    cat "$SRC_FSTAB"; } > "$A51_FSTAB"
  echo "   created ${A51_FSTAB#$ANDROID_ROOT/}"
else
  echo "   !! $SRC_FSTAB missing - check the common device tree"; exit 1
fi
found=$(find "$ANDROID_ROOT"/device/*/a51 -name '*fstab*' | wc -l)
echo "   hybris-boot will find $found fstab(s) $([ "$found" = 1 ] && echo OK || echo AMBIGUOUS)"

echo "=== 2d. fs_config_generator must be python3 ==="
# Android 13 ships it as python2; the Platform SDK has only python3, so
# build_packages.sh --droid-hal dies with "python2: No such file or directory".
FSG="$ANDROID_ROOT/build/make/tools/fs_config/fs_config_generator.py"
if head -1 "$FSG" | grep -q python2; then
  install -m 0755 "$HOME/a51-sfos-port/reference/fs_config_generator.py3" "$FSG"
  echo "   replaced with the AOSP 14 python3 version"
else
  echo "   already python3"
fi

echo "=== 3. apply the a51 fixup-mountpoints stanza ==="
FM=hybris/hybris-boot/fixup-mountpoints
if grep -q '"a51")' "$FM"; then
  echo "  already patched"
else
  python3 - "$FM" "$HOME/a51-sfos-port/reference/fixup-mountpoints-a51.snippet" <<'PY'
import sys
fm, snip = sys.argv[1], sys.argv[2]
body = open(fm).read()
stanza = open(snip).read().rstrip("\n") + "\n"
anchor = 'case "$DEVICE" in\n'
i = body.index(anchor) + len(anchor)
open(fm, "w").write(body[:i] + stanza + body[i:])
print("  inserted a51 stanza")
PY
fi
grep -A18 '"a51")' "$FM"

echo "=== 4. sanity: every node matches the device map ==="
while IFS=$'\t' read -r name node; do
  grep -q "block/by-name/$name $node " "$FM" && echo "  OK   $name -> $node" || true
done < "$HOME/a51-sfos-port/reference/by-name-map.txt"

echo
echo ">> next: enter HABUILD and build"
echo "   sfossdk"
echo "   ubu-chroot -r \$PLATFORM_SDK_ROOT/sdks/ubuntu"
echo "   cd \$ANDROID_ROOT && source build/envsetup.sh && export USE_CCACHE=1"
echo "   breakfast a51 && make -j8 hybris-hal droidmedia"
