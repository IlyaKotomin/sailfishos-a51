#!/bin/sh
# Waydroid performance measurement for the a51 port.
#
# Run as root on the phone:
#     echo <ssh-password> | devel-su /bin/sh -c /home/defaultuser/waydroid-bench.sh
#
# Measures the two configurations that actually differ on this device:
#   hardware rendering (Mali via gralloc/hwcomposer, shared with lipstick)
#   software rendering (SwiftShader)
#
# Uses Android's own instrumentation instead of store benchmarks, because
# `am start -W` and `dumpsys gfxinfo` give numbers you can compare directly and
# need no Play account, no downloads and no network.

PKG=${1:-com.android.settings}
ACT=${2:-}

say() { printf "\n=== %s ===\n" "$1"; }

say "environment"
waydroid status 2>&1 | head -6
echo "renderer props:"
waydroid prop get ro.hardware.egl 2>/dev/null | sed 's/^/  ro.hardware.egl = /'
waydroid prop get ro.hardware.gralloc 2>/dev/null | sed 's/^/  ro.hardware.gralloc = /'

say "cold launch time (3 runs)"
# TotalTime is the number to compare: ms from intent to first frame drawn.
for i in 1 2 3; do
    waydroid shell am force-stop "$PKG" >/dev/null 2>&1
    sleep 2
    if [ -n "$ACT" ]; then
        waydroid shell am start -W -n "$PKG/$ACT" 2>&1 | grep -E "TotalTime|WaitTime"
    else
        waydroid shell monkey -p "$PKG" -c android.intent.category.LAUNCHER 1 >/dev/null 2>&1
        waydroid shell am start -W "$PKG" 2>&1 | grep -E "TotalTime|WaitTime"
    fi
done

say "frame statistics"
# Drive the app a little so there are frames to measure, then read the
# histogram. "Janky frames" and the 95th/99th percentiles are what matter --
# an average frame time hides the stutter you actually feel.
waydroid shell input swipe 540 1600 540 400 300 >/dev/null 2>&1
sleep 1
waydroid shell input swipe 540 400 540 1600 300 >/dev/null 2>&1
sleep 1
waydroid shell dumpsys gfxinfo "$PKG" 2>&1 | grep -iE \
    "Total frames|Janky frames|50th|90th|95th|99th|Number Missed Vsync|Number High input|Number Slow" | head -12

say "GPU driver actually in use inside the container"
waydroid shell getprop ro.hardware.egl 2>/dev/null
waydroid shell dumpsys SurfaceFlinger 2>&1 | grep -iE "GLES:|EGL |Vendor" | head -4

say "host side while Android runs"
echo "cpu load: $(cut -d' ' -f1-3 /proc/loadavg)"
echo "mem free: $(awk '/MemAvailable/ {printf "%.0f MB", $2/1024}' /proc/meminfo)"
echo "lipstick rss: $(awk '/VmRSS/ {print $2/1024 " MB"}' /proc/$(pgrep -f '[l]ipstick' | head -1)/status 2>/dev/null)"

cat <<'NOTE'

--- how to read this ---
TotalTime          cold launch, ms. Under ~1500 ms feels usable; several
                   seconds means the container is thrashing.
Janky frames       percentage is the headline number. Under 10% is smooth,
                   over 30% is visibly stuttery.
95th/99th          worst-case frame times. 16.7 ms = 60 fps budget.

--- switching renderer to compare ---
Software (SwiftShader):
    waydroid prop set ro.hardware.egl swiftshader
    waydroid session stop && waydroid session start
Hardware (default, Mali via gralloc):
    waydroid prop set ro.hardware.egl mali
    waydroid session stop && waydroid session start

Run this script under each and compare TotalTime and Janky frames. Software
rendering will lose badly on anything animated; it is only worth measuring if
the GPU path cannot be shared with lipstick at all.
NOTE
