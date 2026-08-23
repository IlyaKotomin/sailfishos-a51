#!/bin/sh
# Activate the Android dynamic (logical) partitions that live inside 'super',
# then mount them where droid-hal-init expects to find them.
#
# The A51 has no static system/vendor/product/odm partitions: they are dm-linear
# maps carved out of /dev/block/sda25 (major:minor 259:9). Android's first-stage
# init builds those maps from the LP metadata in 'super', but Sailfish boots
# straight into systemd, so nothing did it -- /system stayed empty and
# droid-hal-init died with ENOENT on its own loader,
# /system/bin/bootstrap/linker64 (reported by nohup as status=127).
#
# Tables captured from stock A515FXXU8HWI1. Re-capture with 'dmsetup table'
# after flashing a different ROM: the extents move.

SUPER=259:9
DM=/usr/sbin/dmsetup
LOG=/var/log/dynparts.log
SYSROOT=/mnt/system_root

log() {
    echo "dynparts: $*" > /dev/kmsg 2>/dev/null
    echo "dynparts: $*" >> $LOG 2>/dev/null
    echo "dynparts: $*"
}

# A named map may already exist (another boot stage, or a recovery that did
# first_stage_mount for us), so ask the kernel rather than guessing from /dev:
# Android puts the nodes in /dev/block/mapper, device-mapper in /dev/mapper.
activate() {
    _name=$1
    shift
    if $DM info "$_name" > /dev/null 2>&1; then
        log "$_name already active"
    elif printf '%s\n' "$@" | $DM create "$_name" --noudevsync; then
        log "activated $_name"
    else
        log "FAILED to activate $_name"
        return 1
    fi
    $DM mknodes "$_name" > /dev/null 2>&1
}

node_for() {
    for _p in "/dev/mapper/$1" "/dev/block/mapper/$1"; do
        [ -b "$_p" ] && { echo "$_p"; return 0; }
    done
    return 1
}

mount_ro() {
    _name=$1
    _dir=$2
    _dev=$(node_for "$_name") || { log "FAILED: no device node for $_name"; return 1; }
    [ -d "$_dir" ] || mkdir -p "$_dir"
    if mount -t ext4 -o ro "$_dev" "$_dir" 2>/dev/null; then
        log "mounted $_dir from $_dev"
    else
        log "FAILED to mount $_dir from $_dev"
    fi
}

log "starting (super=$SUPER)"

activate system  "0 9173656 linear $SUPER 2048"

activate vendor  "0 1165312 linear $SUPER 9949184" \
                 "1165312 20480 linear $SUPER 9873408" \
                 "1185792 67584 linear $SUPER 9414656" \
                 "1253376 57344 linear $SUPER 9357312" \
                 "1310720 16384 linear $SUPER 9482240" \
                 "1327104 2048 linear $SUPER 9658368" \
                 "1329152 18696 linear $SUPER 9177088"

activate product "0 1394688 linear $SUPER 11276288" \
                 "1394688 75776 linear $SUPER 12902400" \
                 "1470464 34816 linear $SUPER 9914368" \
                 "1505280 161792 linear $SUPER 11114496" \
                 "1667072 40960 linear $SUPER 12681216" \
                 "1708032 20480 linear $SUPER 9893888" \
                 "1728512 180224 linear $SUPER 12722176" \
                 "1908736 71680 linear $SUPER 12978176" \
                 "1980416 159744 linear $SUPER 9498624" \
                 "2140160 43008 linear $SUPER 9283584" \
                 "2183168 110592 linear $SUPER 9660416" \
                 "2293760 86016 linear $SUPER 9197568" \
                 "2379776 30720 linear $SUPER 9326592" \
                 "2410496 52152 linear $SUPER 9771008"

activate odm     "0 8496 linear $SUPER 12670976"

# The stock A51 system image is "system-as-root": the real tree sits in
# <partition>/system, and the partition root only carries absolute compat
# symlinks (bin -> /system/bin, etc -> /system/etc) for a ROM that mounts it
# on /. Mounting the partition straight onto /system therefore turns
# /system/bin into a self-referential symlink -- ELOOP -- and droid-hal-init
# still fails to find /system/bin/bootstrap/linker64. Mount it aside and bind
# the system/ subdirectory into place instead. A flat image (LineageOS-style,
# where the partition root already *is* /system) is handled too, so this keeps
# working if we ever swap the Android base.
mount_ro system $SYSROOT
if [ -d $SYSROOT/system/bin ]; then
    _src=$SYSROOT/system
    _kind="system-as-root"
elif [ -d $SYSROOT/bin ]; then
    _src=$SYSROOT
    _kind="flat"
else
    _src=""
    log "FAILED: no recognisable system layout under $SYSROOT"
fi
if [ -n "$_src" ]; then
    # A freshly installed rootfs has no /system: unlike the mount_ro targets
    # below, nothing has created it yet, and mount --bind will not create its
    # own mountpoint. Without this the bind fails, /system stays empty, and
    # droid-hal-init never finds a linker or an init.rc -- which looks like the
    # device hanging on the vendor splash with no logs to explain it.
    [ -d /system ] || mkdir -p /system
    if mount --bind "$_src" /system; then
        log "bound $_src -> /system ($_kind layout)"
    else
        log "FAILED to bind $_src -> /system"
    fi
fi

mount_ro vendor   /vendor
mount_ro product  /product
mount_ro odm      /odm

# Android's libdm (apexd, snapuserd) opens /dev/device-mapper. devtmpfs only
# creates the same misc device as /dev/mapper/control, so apexd fails with
# "Failed to open device-mapper", cannot build the dm-verity devices for the
# APEX images, and /apex/com.android.runtime never appears. Every non-bootstrap
# /system binary then dies in the linker looking for libc.so, which on
# Android 10+ ships inside that apex instead of /system/lib64 -- servicemanager
# goes first, and because it is 'critical' init gives up on the whole boot.
if [ ! -e /dev/device-mapper ]; then
    _minor=$(awk '$2 == "device-mapper" { print $1 }' /proc/misc 2>/dev/null)
    if [ -n "$_minor" ] && mknod /dev/device-mapper c 10 "$_minor" 2>/dev/null; then
        log "created /dev/device-mapper (c 10 $_minor)"
    elif ln -s /dev/mapper/control /dev/device-mapper 2>/dev/null; then
        log "linked /dev/device-mapper -> /dev/mapper/control"
    else
        log "FAILED to provide /dev/device-mapper"
    fi
else
    log "/dev/device-mapper already present"
fi

# ---------------------------------------------------------------------------
# Android block-device compatibility.
#
# Vendor code addresses partitions as /dev/block/by-name/<label>. droid-hal
# ships 998-droid-system.rules for this, but it builds the path out of
# $env{PLATFORM_FOLDER}/$env{PLATFORM_DEVICE}, neither of which udev sets here,
# so the links land in /dev/block/platform//by-name/ where nothing looks. cbd
# then cannot read the modem firmware ("BIN(/dev/block/by-name/radio) open
# fail") and the modem never boots. PARTNAME from sysfs works this early,
# unlike /dev/disk/by-partlabel, which needs udev to have settled.
# ---------------------------------------------------------------------------
mkdir -p /dev/block/by-name
_links=0
for _sys in /sys/class/block/*/; do
    [ -f "${_sys}partition" ] || continue
    _pname=$(sed -n 's/^PARTNAME=//p' "${_sys}uevent" 2>/dev/null)
    [ -n "$_pname" ] || continue
    ln -sf "/dev/$(basename "$_sys")" "/dev/block/by-name/$_pname"
    _links=$((_links + 1))
done
log "created $_links /dev/block/by-name links"

# libsec-ril hardcodes /dev/block/param rather than going through by-name.
if [ -e /dev/block/by-name/param ]; then
    ln -sf "$(readlink -f /dev/block/by-name/param)" /dev/block/param
fi

# udev leaves the partition nodes root:disk, but cbd and rild run as uid radio
# and ueventd.rc is where Android records the owner each one needs.
for _rc in /vendor/ueventd*.rc /system/etc/ueventd*.rc; do
    [ -f "$_rc" ] || continue
    while read -r _path _mode _user _group _rest; do
        case "$_path" in /dev/block/by-name/*) ;; *) continue ;; esac
        _target=$(readlink -f "$_path" 2>/dev/null)
        [ -b "$_target" ] || continue
        chown "$_user:$_group" "$_target" 2>/dev/null
        chmod "$_mode" "$_target" 2>/dev/null
    done < "$_rc"
done

# ---------------------------------------------------------------------------
# libprocessgroup - linked into logd, netd and most other Android services -
# reads /etc/cgroups.json and /etc/task_profiles.json. On Android /etc *is*
# /system/etc; here /etc is Sailfish's own, so both files are missing, every
# task-profile lookup fails and logd aborts on startup, which costs us logcat.
#
# These must be *copies*, not symlinks. libbase's ReadFileToString() opens with
# O_NOFOLLOW unless explicitly asked to follow links:
#
#     flags = O_RDONLY | O_CLOEXEC | O_BINARY | (follow_symlinks ? 0 : O_NOFOLLOW)
#
# so a symlink here reads as ENOENT-by-another-name. Every Android service that
# sets a scheduling policy then aborts with "failed to set background scheduling
# policy" -- 89 SIGABRTs in a single boot on this device, logd and gpu
# crash-looping every five seconds. Linking these files was itself the bug.
# ---------------------------------------------------------------------------
for _json in cgroups.json task_profiles.json; do
    if [ -f "/system/etc/$_json" ]; then
        if [ -L "/etc/$_json" ]; then
            rm -f "/etc/$_json"          # drop a symlink left by an older build
        fi
        if cp "/system/etc/$_json" "/etc/$_json"; then
            chmod 644 "/etc/$_json"
            log "copied /etc/$_json"
        fi
    fi
done

log "loader present: $([ -e /system/bin/bootstrap/linker64 ] && echo yes || echo NO)"
log "init.rc present: $([ -e /system/etc/init/hw/init.rc ] && echo yes || echo NO)"
log "done"
exit 0
