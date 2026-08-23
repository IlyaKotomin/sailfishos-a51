#!/bin/sh
# Start the Android NFC HAL service.
#
# /vendor/etc/init/nxp.android.hardware.nfc@1.1-service.rc declares it as
#
#     service nfc_hal_service /vendor/bin/hw/nxp.android.hardware.nfc@1.1-service
#         class hal
#         oneshot
#         disabled
#
# i.e. Android's NFC framework starts it on demand. There is no Android
# framework here and nfcd does not start it either, so without this nfcd finds no
# INfc interface to bind and the device looks like it has no NFC hardware at all.
# Note the service name is nfc_hal_service, not the binary name.
SETPROP=$(command -v setprop || echo /system/bin/setprop)
GETPROP=$(command -v getprop || echo /system/bin/getprop)
[ -x "$SETPROP" ] || exit 0

# Nothing to do on a device whose vendor has no NFC HAL.
[ -e /vendor/bin/hw/nxp.android.hardware.nfc@1.1-service ] || exit 0

"$SETPROP" ctl.start nfc_hal_service

i=0
while [ $i -lt 20 ]; do
    state=$("$GETPROP" init.svc.nfc_hal_service 2>/dev/null)
    if [ "$state" = "running" ]; then
        echo "nfc_hal_service running"
        exit 0
    fi
    sleep 1
    i=$((i + 1))
done
echo "nfc_hal_service did not come up (state: ${state:-unknown})" >&2
exit 0
