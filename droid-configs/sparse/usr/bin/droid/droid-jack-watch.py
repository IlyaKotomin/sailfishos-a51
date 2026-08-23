#!/usr/bin/python3
"""Switch the audio route when the headset jack is plugged or unplugged.

On Android the vendor audio HAL owns jack detection as well as the mixer, so
with no HAL nothing reacts to the jack at all. droid-audio-route.sh knows how to
select a route; this just tells it when to.

It also guards the routing. The ABOX DSP downloads its firmware the first time
the card is opened, and that resets every codec register -- so if the boot-time
route ran before the first open (it does: the card node appears seconds before
PulseAudio touches it), the routing is silently wiped and the phone is mute with
a service that reported success. Polling for that is cheap and repairs it.

The kernel exposes the jack twice: as an Android-style switch node
(/sys/class/switch/h2w/state) and as a normal input device reporting EV_SW. The
input device is used here so the watcher blocks instead of polling, and the
switch node is read once at startup to get the current state -- an input device
only reports transitions, so without that a phone booted with headphones already
inserted would come up routed to the speaker.
"""

import glob
import os
import select
import struct
import subprocess
import sys

ROUTE_SCRIPT = "/usr/bin/droid/droid-audio-route.sh"
SWITCH_STATE = "/sys/class/switch/h2w/state"

# How often to check that the routing is still in place, and the control that
# gives it away: DAC1 defaults to 0, and 0 means silence on every output.
GUARD_INTERVAL = 5.0
GUARD_CONTROL = "DAC1 Playback Volume"

# struct input_event on 64-bit: struct timeval (2x long) + type + code + value
EVENT_FORMAT = "llHHi"
EVENT_SIZE = struct.calcsize(EVENT_FORMAT)

EV_SW = 0x05
SW_HEADPHONE_INSERT = 0x02
SW_MICROPHONE_INSERT = 0x04
SW_LINEOUT_INSERT = 0x06
JACK_CODES = (SW_HEADPHONE_INSERT, SW_MICROPHONE_INSERT, SW_LINEOUT_INSERT)


def log(msg):
    print("jack-watch: %s" % msg, flush=True)


def find_jack_device():
    """Locate the headset jack input device by name, not by a fixed number."""
    for name_path in sorted(glob.glob("/sys/class/input/event*/device/name")):
        try:
            with open(name_path) as handle:
                name = handle.read().strip()
        except OSError:
            continue
        if "jack" in name.lower() or "headset" in name.lower():
            event = os.path.basename(os.path.dirname(os.path.dirname(name_path)))
            return "/dev/input/" + event, name
    return None, None


def apply_route(plugged):
    route = "headphones" if plugged else "speaker"
    log("jack %s -> route %s" % ("inserted" if plugged else "removed", route))
    try:
        subprocess.run(["/bin/sh", ROUTE_SCRIPT, route], check=False, timeout=30)
    except Exception as exc:                      # noqa: BLE001 - keep watching
        log("failed to apply route: %s" % exc)


def routing_lost():
    """True if something has reset the mixer behind our back."""
    try:
        out = subprocess.run(["amixer", "-c", "0", "cget", "name=" + GUARD_CONTROL],
                             capture_output=True, text=True, timeout=10).stdout
    except Exception:                                # noqa: BLE001 - keep watching
        return False
    for line in out.splitlines():
        line = line.strip()
        if line.startswith(": values="):
            values = line.split("=", 1)[1].split(",")
            return all(v.strip() in ("0", "") for v in values)
    return False


def initial_state():
    """An input device only reports changes, so seed from the switch node."""
    try:
        with open(SWITCH_STATE) as handle:
            return handle.read().strip() not in ("0", "")
    except OSError:
        return False


def main():
    device, name = find_jack_device()
    if not device:
        log("no headset jack input device found, nothing to watch")
        return 0
    log("watching %s (%s)" % (device, name))

    plugged = initial_state()
    apply_route(plugged)

    while True:
        try:
            with open(device, "rb", buffering=0) as handle:
                while True:
                    # Wake up periodically even with no jack activity, so a
                    # routing that was reset after boot gets repaired.
                    ready, _, _ = select.select([handle], [], [], GUARD_INTERVAL)
                    if not ready:
                        if routing_lost():
                            log("routing was reset, re-applying")
                            apply_route(plugged)
                        continue
                    data = handle.read(EVENT_SIZE)
                    if not data or len(data) < EVENT_SIZE:
                        break
                    _, _, etype, code, value = struct.unpack(EVENT_FORMAT, data)
                    if etype == EV_SW and code in JACK_CODES:
                        plugged = bool(value)
                        apply_route(plugged)
        except OSError as exc:
            # The node can disappear briefly on suspend/resume; retry rather
            # than exit, or the route would stay wrong until the next boot.
            log("read error on %s (%s), reopening" % (device, exc))
            try:
                import time
                time.sleep(2)
            except KeyboardInterrupt:
                return 0
        except KeyboardInterrupt:
            return 0


if __name__ == "__main__":
    sys.exit(main())
