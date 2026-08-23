#!/bin/sh
# Put the device user in the groups this port needs.
#
# privileged: lipstick's screenshot D-Bus API rejects every caller outside this
# group ("PID N is not in privileged group"), so without it screenshots can only
# be taken from the UI itself -- which makes remote debugging of display issues
# needlessly painful. Sailfish's own user setup does not grant it here.
#
# Runs at every boot rather than once at install time: the user does not exist
# until the first-boot wizard has run, so an install-time scriptlet is too early.
USER_NAME=defaultuser
id "$USER_NAME" >/dev/null 2>&1 || exit 0

for group in privileged; do
    if id -nG "$USER_NAME" 2>/dev/null | tr ' ' '\n' | grep -qx "$group"; then
        continue
    fi
    if usermod -a -G "$group" "$USER_NAME" 2>/dev/null; then
        echo "added $USER_NAME to $group"
    else
        echo "could not add $USER_NAME to $group" >&2
    fi
done
exit 0
