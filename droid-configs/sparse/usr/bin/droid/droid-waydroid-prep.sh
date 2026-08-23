#!/bin/sh
# Prepare the host side so Waydroid's container can start.
#
# Two things do not survive a reboot and are not created by Waydroid itself on
# this port:
#
#   * The dedicated binder nodes. binderfs devices are runtime-only, and
#     Waydroid's own allocator used to fail here because Samsung declared
#     struct binderfs_device with __u8 major/minor where mainline uses __u32,
#     giving BINDER_CTL_ADD a different ioctl number. The kernel is fixed now,
#     but the nodes still have to be created each boot before the container
#     starts, and doing it here keeps the container independent of whether
#     Waydroid's probe path picks the right names.
#
#   * /run/display/pulse. The container config mounts
#     /run/display/pulse/native, but Sailfish keeps the PulseAudio socket under
#     the user runtime directory; without this the container aborts with
#     "Failed to setup mount entries".
set -e

python3 - <<'PY'
import fcntl, struct, os, glob
def IOC(d, t, nr, size):
    return (d << 30) | (t << 8) | (nr << 0) | (size << 16)
BINDER_CTL_ADD = IOC(3, 98, 1, 264)          # mainline struct: 256 + 4 + 4
try:
    fd = open("/dev/binderfs/binder-control", "rb")
except OSError as exc:
    raise SystemExit("binderfs not mounted: %s" % exc)
for node in ("puddlejumper", "vndpuddlejumper", "hwpuddlejumper"):
    if not os.path.exists("/dev/binderfs/" + node):
        try:
            fcntl.ioctl(fd.fileno(), BINDER_CTL_ADD,
                        struct.pack("256sII", node.encode(), 0, 0))
        except OSError as exc:
            print("failed to create %s: %s" % (node, exc))
fd.close()
# Waydroid looks for /dev/<node>, not /dev/binderfs/<node>.
for path in glob.glob("/dev/binderfs/*puddlejumper"):
    link = "/dev/" + os.path.basename(path)
    if not os.path.exists(link):
        os.symlink(path, link)
    os.chmod(path, 0o666)
PY

[ -e /run/display/pulse ] || ln -sfn /run/user/100000/pulse /run/display/pulse || true
exit 0
