#!/bin/bash
# Run ON THE HOST with sudo. Prepares this PC to flash the phone in Download mode.
# Two things, both from Thor's own platform notes:
#   1. udev rule so Thor/heimdall can open the Samsung USB device as your user
#   2. keep cdc_acm from claiming the phone - the kernel currently binds it as
#      ttyACM0 (seen in dmesg when the A51 is plugged in), which blocks flashing
set -e
SRC=$HOME/a51-sfos-port/flash/51-android.rules

echo ">> installing $SRC -> /etc/udev/rules.d/"
sudo install -m 0644 "$SRC" /etc/udev/rules.d/51-android.rules
sudo udevadm control --reload-rules
sudo udevadm trigger
echo ">> udev rule active"

echo ">> unloading cdc_acm for this session"
sudo modprobe -r cdc_acm 2>/dev/null || echo "   (in use or already gone - unplug the phone and retry if flashing fails)"

echo ">> blacklisting cdc_acm across reboots"
if [ -f /etc/modprobe.d/cdc_acm-blacklist.conf ]; then
  echo "   already blacklisted"
else
  echo 'blacklist cdc_acm' | sudo tee /etc/modprobe.d/cdc_acm-blacklist.conf >/dev/null
  echo "   written /etc/modprobe.d/cdc_acm-blacklist.conf"
fi

echo
echo ">> done. Flash tool is ready at:"
echo "     ~/a51-sfos-port/flash/Thor-Linux"
echo ">> NOTE: cdc_acm is also used by USB modems/Arduino boards. To undo later:"
echo "     sudo rm /etc/modprobe.d/cdc_acm-blacklist.conf && sudo modprobe cdc_acm"
