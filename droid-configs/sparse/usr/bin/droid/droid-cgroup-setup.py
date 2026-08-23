#!/usr/bin/python3
"""Do the cgroup setup droid-hal-init never does.

Android's init calls CgroupSetup() during early boot: it mounts each controller
at the path /etc/cgroups.json names, creates the groups /etc/task_profiles.json
references, and writes a binary map to /dev/cgroup_info/cgroup.rc so
libprocessgroup can find them. droid-hal-init skips all of it, and the
consequences are much wider than they look:

    logd: failed to set background scheduling policy: No such file or directory
    libprocessgroup: Failed to read task profiles from /etc/task_profiles.json
    open() failed for /dev/cgroup_info/cgroup.rc: No such file or directory

Every Android service that sets a scheduling policy aborts. On this device that
was 89 SIGABRTs in one boot -- logd and gpu crash-looping every five seconds,
which is why logcat has never worked on this port.

The controllers themselves are all mounted, just where systemd put them, so this
bind-mounts them onto the Android paths rather than trying to mount them twice
(a v1 controller can only live in one hierarchy).

The file format is from system/core/libprocessgroup/cgrouprc_format:

    CgroupFile:       uint32 version (1), uint32 controller_count
    CgroupController: uint32 version, uint32 flags, char name[16], char path[32]

and WriteRcFile() emits the header followed by one 56-byte controller record
each, in name order.
"""

import json
import os
import struct
import subprocess
import sys

CGROUP_RC = "/dev/cgroup_info/cgroup.rc"
FILE_VERSION_1 = 1
FLAG_MOUNTED = 0x1

NAME_SZ = 16
PATH_SZ = 32

# Where systemd has each controller, and where Android expects to find it.
# cpu and cpuacct share one hierarchy here, so both Android paths point at it.
SOURCES = {
    "blkio": "/sys/fs/cgroup/blkio",
    "cpu": "/sys/fs/cgroup/cpu,cpuacct",
    "cpuacct": "/sys/fs/cgroup/cpu,cpuacct",
    "cpuset": "/sys/fs/cgroup/cpuset",
    "memory": "/sys/fs/cgroup/memory",
    "sfreezer": "/sys/fs/cgroup/freezer",
    "schedtune": "/sys/fs/cgroup/schedtune",
}
# cgroup v2. Android wants it at /sys/fs/cgroup, which is a read-only tmpfs
# here, so point at systemd's unified hierarchy instead -- libprocessgroup only
# ever uses this as a path prefix.
V2_PATH = "/sys/fs/cgroup/unified"


def log(msg):
    print("cgroup-setup: %s" % msg, flush=True)


def mounted(path):
    with open("/proc/mounts") as handle:
        return any(line.split()[1] == path for line in handle)


def bind(source, target):
    if not os.path.isdir(source):
        return False
    if mounted(target):
        return True
    os.makedirs(target, exist_ok=True)
    rc = subprocess.run(["mount", "--bind", source, target],
                        capture_output=True, text=True)
    if rc.returncode != 0:
        log("bind %s -> %s failed: %s" % (source, target, rc.stderr.strip()))
        return False
    return True


def group_paths(profiles):
    """Every cgroup path task_profiles.json expects to exist."""
    found = set()

    def walk(node):
        if isinstance(node, dict):
            for key, value in node.items():
                if key == "Path" and isinstance(value, str):
                    found.add(value)
                else:
                    walk(value)
        elif isinstance(node, list):
            for item in node:
                walk(item)

    walk(profiles)
    # "." and "" mean the controller root, which already exists.
    return sorted(p for p in found if p not in (".", ""))


def main():
    try:
        with open("/etc/cgroups.json") as handle:
            cgroups = json.load(handle)
    except OSError as exc:
        log("cannot read /etc/cgroups.json: %s" % exc)
        return 1

    controllers = []

    for entry in cgroups.get("Cgroups", []):
        name = entry.get("Controller")
        path = entry.get("Path")
        source = SOURCES.get(name)
        if not (name and path and source):
            log("skipping %s: no local hierarchy for it" % name)
            continue
        if bind(source, path):
            controllers.append((name, 1, path))
        else:
            log("skipping %s: could not bind %s" % (name, source))

    v2 = cgroups.get("Cgroups2", {})
    for entry in v2.get("Controllers", []):
        name = entry.get("Controller")
        if name and os.path.isdir(V2_PATH):
            controllers.append((name, 2, V2_PATH))

    # Create the groups the task profiles reference, in every v1 controller.
    try:
        with open("/etc/task_profiles.json") as handle:
            wanted = group_paths(json.load(handle))
    except OSError:
        wanted = []
    made = 0
    for name, version, path in controllers:
        if version != 1:
            continue
        for group in wanted:
            try:
                os.makedirs(os.path.join(path, group), exist_ok=True)
                made += 1
            except OSError:
                pass                      # cpuset groups need cpus/mems first
    log("created %d group directories across %d controllers" % (made, len(controllers)))

    os.makedirs(os.path.dirname(CGROUP_RC), exist_ok=True)
    blob = struct.pack("<II", FILE_VERSION_1, len(controllers))
    for name, version, path in sorted(controllers):
        blob += struct.pack("<II%ds%ds" % (NAME_SZ, PATH_SZ),
                            version, FLAG_MOUNTED,
                            name.encode()[:NAME_SZ - 1],
                            path.encode()[:PATH_SZ - 1])
    with open(CGROUP_RC, "wb") as handle:
        handle.write(blob)
    os.chmod(CGROUP_RC, 0o444)
    log("wrote %s (%d bytes, %d controllers): %s"
        % (CGROUP_RC, len(blob), len(controllers),
           ", ".join("%s@%s" % (n, p) for n, _, p in sorted(controllers))))
    return 0


if __name__ == "__main__":
    sys.exit(main())
