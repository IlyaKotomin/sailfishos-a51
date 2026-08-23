# These and other macros are documented in ../droid-configs-device/droid-configs.inc
# Feel free to cleanup this file by removing comments, once you have memorised them ;)

%define device a51
%define vendor samsung

%define vendor_pretty Samsung
%define device_pretty Galaxy A51

# Community HW adaptations need this
%define community_adaptation 1

# Pixel ratio 1.0 was originally jolla phone with 245ppi, and the devices
# should roughly have their ppi compared to that. Large displays can use
# bigger ratio if seen fit. Values are with 0.25 increments.
# 1080x2400 on a 6.5" panel is ~405 ppi. Sailfish's reference is the Jolla 1
# at ~245 ppi with ratio 1.0, so the matching value here is 405/245 ~= 1.65,
# and 1.75 is the nearest scale the theme actually ships (the same one the
# 1080p Xperias use). At the stock 1.0 the UI renders at Jolla-1 size on a
# 405 ppi panel: text and touch targets are tiny and most of the screen is
# left empty.
%define pixel_ratio 1.75

# droid-config-a51 ships /etc/ofono/binder.conf (+ binder.d/) from dhd's sparse
# tree, which collides with the distro's ofono-configs-binder during image
# composition ("Could not run transaction"). droid-configs.inc:39 documents the
# fix: claim the generic package so it is never selected.
Provides:   ofono-configs
Provides:   ofono-configs-binder
Obsoletes:  ofono-configs-binder

%include droid-configs-device/droid-configs.inc
%include patterns/patterns-sailfish-device-adaptation-a51.inc
%include patterns/patterns-sailfish-device-configuration-a51.inc

# IMPORTANT if you want to comment out any macros in your .spec, delete the %
# sign, otherwise they will remain defined! E.g.:
#define some_macro "I'll not be defined because I don't have % in front"

