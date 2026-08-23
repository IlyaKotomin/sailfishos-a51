#!/bin/bash
# Run ON THE HOST with sudo available, BEFORE the first Android build.
# 15 GiB RAM + 8 GiB zram is not enough for soong/Android 13 - zram costs RAM,
# so we add real disk swap. NOTE: / is btrfs, so fallocate/dd swapfiles are
# invalid here (no CoW, no compression allowed) - use btrfs's own helper.
set -e
SWAP=/swapfile-hadk
if swapon --show=NAME --noheadings | grep -qx "$SWAP"; then
  echo ">> $SWAP already active"; swapon --show; exit 0
fi
echo ">> creating 24G btrfs swapfile at $SWAP (nocow, no compression, handled by btrfs)"
sudo btrfs filesystem mkswapfile --size 24g "$SWAP"
sudo swapon "$SWAP"
echo ">> to keep it across reboots:"
echo "   echo '$SWAP none swap defaults 0 0' | sudo tee -a /etc/fstab"
swapon --show; free -h
