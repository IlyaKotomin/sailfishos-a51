#!/bin/sh
# Keep a [sailfish] section in the Android linker configuration.
#
# ld.config.txt selects a section by matching the executable against its
# "dir.<label> = <path>" entries. Everything generated points into /system,
# /vendor and /product, so a /usr/bin binary matches nothing and bionic falls
# back to built-in defaults whose permitted paths contain no /vendor/lib64.
# lipstick then cannot load hwcomposer.exynos9611.so or libGLES_mali.so through
# libvndksupport, and aborts right after enumerating the panel.
#
# HYBRIS_LD_LIBRARY_PATH does not cover this: it fixes libhybris's own dlopen
# (which is what let test_hwcomposer render) but libvndksupport goes through the
# linker namespace instead.
#
# This polls instead of using a .path unit. That unit never fired -- one service
# start at 15:27:03, apexd finishing at 15:27:14, init regenerating the config
# afterwards, no retrigger -- because /linkerconfig is a bind-mounted tmpfs and
# the inotify watch does not survive it being rewritten. init regenerates once
# apexd reports all 35 packages activated, so the section has to be re-applied
# after that, and lipstick keeps restarting until it is.
CFG=/linkerconfig/ld.config.txt
LOG=/var/log/linkerconfig.log

log() {
    echo "linkerconfig: $*" > /dev/kmsg 2>/dev/null
    echo "linkerconfig: $*" >> $LOG 2>/dev/null
}

patch_config() {
    TMP=/tmp/ld.config.sailfish.$$
    {
        # dir. entries are matched in file order, so ours go first.
        echo "dir.sailfish = /usr/bin"
        echo "dir.sailfish = /usr/libexec/droid-hybris/system/bin"
        echo "dir.sailfish = /usr/lib"
        echo "dir.sailfish = /usr/sbin"
        echo "dir.sailfish = /bin"
        cat "$CFG"
        echo ""
        echo "# Sailfish binaries using libhybris."
        echo "[sailfish]"
        echo "namespace.default.isolated = false"
        # explicit lib64/lib: hybris's bundled linker does not expand ${LIB}
        for l in lib64 lib; do
            for d in /usr/libexec/droid-hybris/system /system /system/hw /system/system_ext \
                     /vendor /vendor/hw /vendor/egl /odm /odm/hw /product; do
                case $d in
                    */hw)  echo "namespace.default.search.paths += ${d%/hw}/$l/hw" ;;
                    */egl) echo "namespace.default.search.paths += ${d%/egl}/$l/egl" ;;
                    *)     echo "namespace.default.search.paths += $d/$l" ;;
                esac
            done
            echo "namespace.default.search.paths += /apex/com.android.vndk.v33/$l"
            echo "namespace.default.search.paths += /apex/com.android.runtime/$l/bionic"
            # libmedia.so pulls in libandroidicu.so, which ships only inside the
            # i18n apex; without this minisfservice and minimediaservice fail to
            # link and droid-hal-init restarts them forever, so gst-droid never
            # gets a media or buffer-allocator service and the camera is dead.
            echo "namespace.default.search.paths += /apex/com.android.i18n/$l"
        done
    } > "$TMP" 2>/dev/null
    if [ -s "$TMP" ]; then
        cat "$TMP" > "$CFG" && log "applied [sailfish] section ($(wc -l < "$CFG") lines)"
        rm -f "$TMP"
    else
        log "FAILED to build patched config"
        rm -f "$TMP"
    fi
}

log "watching $CFG"
i=0
while [ $i -lt 90 ]; do
    if [ -f "$CFG" ] && ! grep -q '^\[sailfish\]' "$CFG" 2>/dev/null; then
        patch_config
    fi
    sleep 2
    i=$((i + 1))
done
log "watch finished"
exit 0
