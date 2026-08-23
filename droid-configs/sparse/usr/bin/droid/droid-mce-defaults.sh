#!/bin/sh
# Seed MCE display defaults once, on first boot.
#
# With the light sensor working, MCE drives the backlight from it, and Settings
# offers no way to turn that off: the toggle is conditional on the device
# advertising Feature_LightSensor through ssu-sysinfo hw-features, which this
# port does not ship. So the phone dims and brightens on its own with no visible
# control -- surprising enough that off is the better default here.
#
# Seeded once rather than enforced every boot, so anyone who turns adaptive
# brightness back on (mcetool --set-als-autobrightness=enabled) keeps it.
# MCE persists its own settings in /var/lib/mce/builtin-gconf.values.
STAMP=/var/lib/droid-mce-defaults.done
[ -e "$STAMP" ] && exit 0

MCETOOL=/usr/sbin/mcetool
[ -x "$MCETOOL" ] || exit 0

# MCE has to be up to accept this over D-Bus.
i=0
while [ $i -lt 30 ]; do
    "$MCETOOL" --set-als-autobrightness=disabled >/dev/null 2>&1 && break
    sleep 2
    i=$((i + 1))
done

if [ $i -lt 30 ]; then
    echo "adaptive brightness disabled by default"
    mkdir -p "$(dirname "$STAMP")"
    : > "$STAMP"
else
    echo "could not reach mce, leaving the default alone" >&2
fi
exit 0
