#!/bin/bash
# Run INSIDE the Platform SDK (sfossdk), AFTER `make hybris-hal droidmedia` succeeds.
# Creates the three port repos (droid-hal / droid-config / droid-hal-version) for a51.
# Idempotent: skips anything that already exists.
set -e

# --- guard: must run INSIDE the Platform SDK (has mb2), not host, not HABUILD ---
. /etc/os-release 2>/dev/null
if ! command -v mb2 >/dev/null 2>&1 || [ "$ID" != "sailfishos" ]; then
  echo "!! must run INSIDE the Platform SDK (no mb2 here)."
  echo "!! Detected: ${NAME:-unknown} ${VERSION_ID:-}"
  echo "   From the host:  sfossdk"
  echo "   then:           ~/a51-sfos-port/5-bootstrap-droid-hal.sh"
  exit 1
fi
echo ">> inside: $NAME $VERSION_ID"

source "$HOME/.hadk.env"
cd "$ANDROID_ROOT"

DEV=a51; VEN=samsung; DEV_PRETTY="Galaxy A51"; VEN_PRETTY="Samsung"

if [ ! -d rpm ]; then
  echo ">> creating rpm/ (droid-hal-$DEV)"
  mkdir rpm && cd rpm && git init -q
  git submodule add -q https://github.com/mer-hybris/droid-hal-device dhd
  sed -e "s/@DEVICE@/$DEV/" -e "s/@VENDOR@/$VEN/" \
      -e "s/@DEVICE_PRETTY@/$DEV_PRETTY/" -e "s/@VENDOR_PRETTY@/$VEN_PRETTY/" \
      dhd/droid-hal-@DEVICE@.spec.template > "droid-hal-$DEV.spec"
  git add . && git commit -qm "[dhd] Initial content"
  cd "$ANDROID_ROOT"
else echo ">> rpm/ exists, skipping"; fi

if [ ! -d hybris/droid-configs ]; then
  echo ">> creating hybris/droid-configs (droid-config-$DEV)"
  mkdir -p hybris/droid-configs && cd hybris/droid-configs && git init -q
  git submodule add -q https://github.com/mer-hybris/droid-hal-configs droid-configs-device
  mkdir -p rpm
  sed -e "s/@DEVICE@/$DEV/" -e "s/@VENDOR@/$VEN/" \
      -e "s/@DEVICE_PRETTY@/$DEV_PRETTY/" -e "s/@VENDOR_PRETTY@/$VEN_PRETTY/" \
      droid-configs-device/droid-config-@DEVICE@.spec.template > "rpm/droid-config-$DEV.spec"
  git add . && git commit -qm "[dcd] Initial content"
  cd "$ANDROID_ROOT"
else echo ">> hybris/droid-configs exists, skipping"; fi

if [ ! -d "hybris/droid-hal-version-$DEV" ]; then
  echo ">> creating hybris/droid-hal-version-$DEV"
  mkdir -p "hybris/droid-hal-version-$DEV" && cd "hybris/droid-hal-version-$DEV" && git init -q
  git submodule add -q https://github.com/mer-hybris/droid-hal-version
  # the version package needs its spec generated from the template too - dhd
  # otherwise calls mb2 with an empty spec path ("dirname: missing operand",
  # then "//droid-hal-version-a51.log: Permission denied")
  mkdir -p rpm
  sed -e "s/@DEVICE@/$DEV/" -e "s/@VENDOR@/$VEN/" \
      -e "s/@DEVICE_PRETTY@/$DEV_PRETTY/" -e "s/@VENDOR_PRETTY@/$VEN_PRETTY/" \
      droid-hal-version/droid-hal-version-@DEVICE@.spec.template > "rpm/droid-hal-version-$DEV.spec"
  git add . && git commit -qm "[dhv] Initial content"
  cd "$ANDROID_ROOT"
else echo ">> droid-hal-version-$DEV exists, skipping"; fi

echo ">> generating patterns / compositor config"
rpm/dhd/helpers/add_new_device.sh

echo ">> review these before building:"
grep -n -E '^%define (device|vendor)' "rpm/droid-hal-$DEV.spec" || true
ls hybris/droid-configs/patterns/ 2>/dev/null

cat <<'NEXT'

>> next (still inside the Platform SDK, in order - each must succeed):
   rpm/dhd/helpers/build_packages.sh --droid-hal
   rpm/dhd/helpers/build_packages.sh --configs
   rpm/dhd/helpers/build_packages.sh --mw
   rpm/dhd/helpers/build_packages.sh --gg
   rpm/dhd/helpers/build_packages.sh --version
>> "Installed (but unpackaged) file(s) found" is normal: add the listed paths to
   %define straggler_files in rpm/droid-hal-a51.spec, then re-run --droid-hal
NEXT
