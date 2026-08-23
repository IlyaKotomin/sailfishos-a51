# Feel free to disable non-critical HA parts during devel by commenting lines out
# Generated in hadk by executing: rpm/dhd/helpers/add_new_device.sh

%package -n patterns-sailfish-device-adaptation-a51
Summary: Jolla HW Adaptation a51
Requires: droid-hal-a51
Requires: droid-hal-a51-img-boot
Requires: droid-hal-a51-kernel-modules
Requires: droid-hal-a51-detritus
Requires: droid-config-a51-sailfish
Requires: droid-config-a51-pulseaudio-settings
Requires: droid-config-a51-policy-settings
Requires: droid-config-a51-preinit-plugin
Requires: droid-config-a51-flashing
Requires: droid-config-a51-bluez5
Requires: droid-hal-version-a51

# Hybris packages
Requires: libhybris-libEGL
Requires: libhybris-libGLESv2
Requires: libhybris-libwayland-egl

# Sensors
Requires: hybris-libsensorfw-qt5

# Vibra
Requires: ngfd-plugin-native-vibrator
Requires: libngf-qt5-qtfeedback

# Needed for /dev/touchscreen symlink
Requires: qt5-plugin-generic-evdev

Requires: pulseaudio-modules-droid
Requires: pulseaudio-modules-droid-hidl

# The -dummy-af is needed for newer devices that run the main
# audiosystem-passthrough in qti mode (e.g. >=Android 9 Qualcomm),
# to fix non-responding Camera app and/or voice during a phone call:
#Requires: audiosystem-passthrough-dummy-af

# for audio recording to work:
Requires: qt5-qtmultimedia-plugin-mediaservice-gstmediacapture

# These need to be per-device due to differing backends (fbdev, eglfs, hwc, ..?)
Requires: qt5-qtwayland-wayland_egl
Requires: qt5-qpa-hwcomposer-plugin
Requires: qtscenegraph-adaptation

# For hybris devices with droidmedia, see HADK pdf for more information
Requires: gstreamer1.0-droid
Obsoletes: gmp-droid

# This is needed for notification LEDs
Requires: mce-plugin-libhybris

# USB mode controller
Requires: usb-moded
# alsa-utils: this port has no audio HAL, so the mixer routing is applied by
# droid-audio-route.sh and re-applied by droid-jack-watch.py -- both of which
# shell out to amixer. Nothing else in the image pulls it in, and without it
# every routing command fails and the phone is silent from first boot, while the
# route script still exits 0 and its service reports success.
Requires: alsa-utils
# Bluetooth: bluebinder proxies the Android HAL onto /dev/vhci, which is the only
# route to the radio here -- there is no HCI UART. bluez5 drives it, and the
# service was previously masked by this very port because the kernel panicked on
# the first AF_BLUETOOTH socket; with hci_sock.c restored it works, so the
# packages have to actually be present.
Requires: bluebinder
Requires: bluez5
Requires: bluez5-tools
# ofono needs the binder RIL plugin to see the modem at all; without it ofono
# runs and reports zero modems.
Requires: ofono-binder-plugin
# NFC: nfcd reaches the vendor NXP HAL over binder via nfcd-binder-plugin, and
# the settings page is what actually powers the chip -- nfcd powers up for a
# client that consumes tags, not for one merely holding a mode. Confirmed by
# reading a MIFARE Classic 1k card on this device.
Requires: nfcd
Requires: nfcd-binder-plugin
Requires: jolla-settings-system-nfc

# hammerhead, grouper, and maguro use this in scripts, so include for all
Requires: rfkill

# enable device lock and allow to select untrusted software
Requires: jolla-devicelock-daemon-encsfa

# Enable home encryption
#Requires: sailfish-device-encryption

# For GPS
Requires: geoclue-provider-hybris

# For FM radio on some QCOM devices
#Requires: qt5-qtmultimedia-plugin-mediaservice-irisradio
#Requires: jolla-mediaplayer-radio

# NFC support
# 1. binder plugin requires Android 8 or a newer base
# 2. pn54x plugin talks directly to pn54x driver
# These plugins are mutually exclusive, you need to pick one:
#Requires: nfcd-binder-plugin
#Requires: nfcd-pn54x-plugin

%description -n patterns-sailfish-device-adaptation-a51
Pattern with packages for a51 HW Adaptation

%files -n patterns-sailfish-device-adaptation-a51
