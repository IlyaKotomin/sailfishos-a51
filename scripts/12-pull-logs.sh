#!/bin/bash
# Pull and summarise Sailfish's own logs from the rootfs while sitting in TWRP.
ADB=~/.local/opt/platform-tools/adb
R=/data/.stowaways/sailfishos
OUT=${1:-$HOME/a51-sfos-port/logs/$(date +%m%d-%H%M)}
mkdir -p "$OUT"

[ "$($ADB get-state 2>&1)" = recovery ] || { echo "Not in recovery (state: $($ADB get-state 2>&1))"; exit 1; }

echo "== dynparts trace =="
$ADB shell "cat $R/var/log/dynparts.log 2>/dev/null" | tr -d '\r' | tee "$OUT/dynparts.log" | tail -20 | sed 's/^/  /'

$ADB pull "$R/var/log/journal" "$OUT/journal" >/dev/null 2>&1
JDIR="$OUT/journal"
[ ! -d "$JDIR" ] && { echo "no journal found"; exit 1; }

echo; echo "== failed units =="
journalctl -D "$JDIR" --no-pager 2>/dev/null | grep -iE 'Failed with result|Failed to start|Dependency failed' \
  | sed 's/.*]: //' | sort -u | head -30 | sed 's/^/  /'

echo; echo "== droid-hal-init =="
journalctl -D "$JDIR" --no-pager 2>/dev/null | grep -iE 'droid-hal-init|init:' | sed 's/.*GalaxyA51 //' | tail -30 | sed 's/^/  /'

echo; echo "== lipstick / compositor =="
journalctl -D "$JDIR" --no-pager 2>/dev/null | grep -iE 'lipstick|hwcomposer|EGL|gralloc|surfaceflinger' | sed 's/.*GalaxyA51 //' | tail -20 | sed 's/^/  /'

echo; echo "saved to $OUT"
