#!/bin/bash
# Pull lipstick's core from the device (TWRP) and back-trace it.
#
# Symbols come from the SDK target, which holds the same Qt/lipstick RPM
# versions the image was built from. libhybris frames may be approximate because
# the device now runs our locally rebuilt libhybris, but the Qt frames -- the
# ones that matter for "Cannot make QOpenGLContext current in a different
# thread" -- resolve correctly.
ADB=~/.local/opt/platform-tools/adb
R=/data/.stowaways/sailfishos
SYSROOT=/srv/sailfishos/targets/samsung-a51-aarch64
OUT=${1:-$HOME/a51-sfos-port/cores}
mkdir -p "$OUT"

[ "$($ADB get-state 2>&1)" = recovery ] || { echo "Not in TWRP (state: $($ADB get-state 2>&1))"; exit 1; }

CORE=$($ADB shell "ls -t $R/var/cores/core.lipstick.* 2>/dev/null | head -1" | tr -d '\r')
[ -n "$CORE" ] || { echo "No lipstick core on the device yet."; \
                    echo "cores present:"; $ADB shell "ls $R/var/cores/ 2>/dev/null | sed 's/\.[0-9]*$//' | sort | uniq -c" | tr -d '\r'; exit 1; }

echo "== pulling $CORE =="
$ADB pull "$CORE" "$OUT/lipstick.core" >/dev/null 2>&1
ls -la "$OUT/lipstick.core" | awk '{print "  ", $5, "bytes"}'

BIN=$SYSROOT/usr/bin/lipstick
[ -f "$BIN" ] || BIN=$OUT/lipstick.bin
[ -f "$BIN" ] || { $ADB pull $R/usr/bin/lipstick "$OUT/lipstick.bin" >/dev/null 2>&1; BIN=$OUT/lipstick.bin; }

echo "== backtrace =="
gdb -q -batch \
    -ex "set sysroot $SYSROOT" \
    -ex "set solib-search-path $SYSROOT/usr/lib64:$SYSROOT/lib64:$SYSROOT/usr/lib64/qt5/plugins/platforms" \
    -ex "core-file $OUT/lipstick.core" \
    -ex "echo \n=== crashing thread ===\n" \
    -ex "bt" \
    -ex "echo \n=== all threads ===\n" \
    -ex "info threads" \
    -ex "echo \n=== every thread's stack (top frames) ===\n" \
    -ex "thread apply all bt 12" \
    "$BIN" 2>&1 | grep -vE '^\[New LWP|^warning: .*(section|separate debug)' | head -120
