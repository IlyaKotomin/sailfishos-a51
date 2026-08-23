#!/bin/sh
# Mount selinuxfs and load an actual SELinux policy before droid-hal-init.
#
# Android's first-stage init compiles the device's CIL policy and loads it. The
# hybris init skips that step, so selinuxfs was mounted with no policy behind it
# -- and that is worse than either extreme. libselinux's access checks then fail
# closed, so every HAL registration was refused:
#
#   AidlLazyServiceRegistrar: Failed to register service apexservice
#     (Status(-1, EX_SECURITY): 'SELinux denial')
#   android.hidl.allocator@1.0-service: Unable to register allocator service:
#     -2147483648
#   android.hardware.wifi@1.0-service: registerAsService() != NO_ERROR
#   android.hardware.graphics.composer@2.1-service: gralloc-mapper is missing
#
# and with no composer HAL registered, lipstick dies on "failed to get
# hwcomposer service".
#
# The kernel cmdline already asks for permissive (androidboot.selinux=permissive),
# so with a policy loaded the checks return allowed instead of failing closed.
#
# The compile is Android's own argument set from system/core/init/selinux.cpp.
# secilc links against the bootstrap linker, so it runs before apex is mounted.
POLICY=/var/lib/droid-sepolicy.bin
SECILC=/system/bin/secilc
SE=/system/etc/selinux
VE=/vendor/etc/selinux
LOG=/var/log/sepolicy.log

log() {
    echo "sepolicy: $*" > /dev/kmsg 2>/dev/null
    echo "sepolicy: $*" >> $LOG 2>/dev/null
}

if [ ! -e /sys/fs/selinux/status ] && [ -d /sys/fs/selinux ]; then
    mount -t selinuxfs selinuxfs /sys/fs/selinux 2>/dev/null \
        && log "mounted selinuxfs" || log "FAILED to mount selinuxfs"
fi
[ -e /sys/fs/selinux/load ] || { log "no selinuxfs, nothing to load"; exit 0; }

# Already loaded (a policy is only loadable once per boot)?
if [ "$(cat /sys/fs/selinux/policy_capabilities/network_peer_controls 2>/dev/null)" != "" ] \
   && [ -s /sys/fs/selinux/policy ] 2>/dev/null; then
    log "a policy is already loaded"
    exit 0
fi

if [ ! -s "$POLICY" ]; then
    log "no cached policy, compiling"
    VERS=$(cat /sys/fs/selinux/policyvers 2>/dev/null)
    [ -n "$VERS" ] || VERS=31
    PLAT_VERS=$(cat "$VE/plat_sepolicy_vers.txt" 2>/dev/null | tr -d ' \n')
    [ -n "$PLAT_VERS" ] || PLAT_VERS=33.0
    MAPPING="$SE/mapping/${PLAT_VERS}.cil"
    [ -f "$MAPPING" ] || { log "no mapping file $MAPPING"; exit 0; }
    [ -x "$SECILC" ] || { log "no $SECILC"; exit 0; }
    mkdir -p "$(dirname $POLICY)"
    if $SECILC "$SE/plat_sepolicy.cil" -m -M true -G -N -c "$VERS" \
        "$MAPPING" "$VE/plat_pub_versioned.cil" "$VE/vendor_sepolicy.cil" \
        -o "$POLICY.tmp" -f /sys/fs/selinux/null >> $LOG 2>&1; then
        mv -f "$POLICY.tmp" "$POLICY"
        log "compiled policy ($(wc -c < "$POLICY") bytes, vers=$VERS, mapping=$PLAT_VERS)"
    else
        log "FAILED to compile policy"
        rm -f "$POLICY.tmp"
        exit 0
    fi
fi

# The kernel's sel_write_load() expects the whole policy image in a single
# write(). cat streams it in 128K chunks, so the first short write is rejected
# and the load fails with EINVAL -- which is exactly what happened on the first
# attempt ("FAILED to load policy into the kernel"). dd with a block size larger
# than the policy does one read and one write, the way init does it.
SZ=$(wc -c < "$POLICY" 2>/dev/null)
log "loading policy ($SZ bytes) in a single write"
if dd if="$POLICY" of=/sys/fs/selinux/load bs=8M 2>>$LOG; then
    echo 0 > /sys/fs/selinux/enforce 2>/dev/null
    log "loaded policy, enforce=$(cat /sys/fs/selinux/enforce 2>/dev/null), policyvers=$(cat /sys/fs/selinux/policyvers 2>/dev/null)"
else
    log "FAILED to load policy into the kernel (see errors above)"
fi
exit 0
