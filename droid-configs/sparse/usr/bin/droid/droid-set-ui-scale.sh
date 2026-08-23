#!/bin/sh
# Change the Sailfish UI scale. Run as root:
#     echo <your-ssh-password> | devel-su /bin/sh -c "/usr/bin/droid/droid-set-ui-scale.sh 2.0"
#
# Valid scales: 1.0 1.25 1.5 1.5-large 1.75 2.0 2.5
# This device is 1080x2400 on 6.5" (~405 ppi); 1.75 matches the Sailfish
# reference of 245 ppi = 1.0. Larger values make everything bigger.
set -e
Z=$1
[ -n "$Z" ] || { echo "usage: $0 <scale>   e.g. $0 2.0"; exit 1; }
RATIO=$(echo "$Z" | sed "s/-large//")

echo ">> installing the graphics pack for z$Z (skipped if present)"
zypper --non-interactive install "sailfish-content-graphics-default-z$Z" \
    "sailfish-content-graphics-closed-z$Z" >/dev/null 2>&1 || \
    echo "   (packages may already be installed)"

echo ">> writing the vendor dconf entry"
F=/etc/dconf/db/vendor.d/silica-configs.txt
{
  printf "[desktop/sailfish/silica]\n"
  printf "theme_pixel_ratio=%s\n" "$RATIO"
  printf "theme_icon_subdir=\047z%s\047\n" "$Z"
} > $F
dconf update 2>/dev/null

echo ">> restarting the UI"
# lipstick runs in the user session, so reach it as that user
su - defaultuser -c "systemctl --user restart lipstick" 2>/dev/null || \
    systemctl --user -M defaultuser@ restart lipstick 2>/dev/null

echo ">> now at pixel_ratio=$RATIO icons=z$Z"
