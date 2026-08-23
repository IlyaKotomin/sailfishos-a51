#!/usr/bin/python3
"""Publish the Android apps inside Waydroid as ordinary Sailfish launcher icons.

Waydroid generates .desktop files itself on desktop Linux, but not here, so the
container's apps are otherwise only reachable through the full Android UI. Each
app gets an entry that runs `waydroid app launch <package>`, which starts that
app on its own in a Wayland window rather than the whole Android home screen.

Run it after installing or removing apps in the container:

    droid-waydroid-desktop.py

Entries land in the user's own applications directory, so nothing needs to be
written to /usr and a plain user can refresh their own launcher.
"""

import os
import pwd
import re
import subprocess
import sys

# lipstick only scans the system applications directory, so user-local
# entries never show up in the Sailfish app grid.
APP_DIR = "/usr/share/applications"
PREFIX = "waydroid."
# Container-internal apps that have no business in the host launcher: settings
# panels, stubs and the Android home screen itself.
SKIP = {
    "com.android.settings",
    "com.android.documentsui",
    "com.android.launcher3",
    "com.android.inputmethod.latin",
    "org.lineageos.settings.device",
    "com.android.providers.downloads.ui",
    "com.android.traceur",
}
# Any icon that exists on the device; Android app icons live inside the
# container's APKs and cannot be read out without unpacking them, so all
# entries share the Waydroid icon rather than shipping something misleading.
ICON_CANDIDATES = [
    "/usr/share/icons/hicolor/172x172/apps/waydroid-runner.png",
    "/usr/share/icons/hicolor/128x128/apps/waydroid-runner.png",
    "/usr/share/icons/hicolor/108x108/apps/waydroid-runner.png",
]


def pick_icon():
    for path in ICON_CANDIDATES:
        if os.path.exists(path):
            return path
    return "icon-launcher-android"


def list_apps():
    """Parse `waydroid app list` into (name, package) pairs."""
    try:
        out = subprocess.run(["waydroid", "app", "list"],
                             capture_output=True, text=True, timeout=120).stdout
    except Exception as exc:                                 # noqa: BLE001
        print("could not list apps: %s" % exc, file=sys.stderr)
        return []

    apps, name = [], None
    for line in out.splitlines():
        line = line.strip()
        if line.startswith("Name:"):
            name = line.split(":", 1)[1].strip()
        elif line.startswith("packageName:"):
            pkg = line.split(":", 1)[1].strip()
            if name and pkg and pkg not in SKIP:
                apps.append((name, pkg))
            name = None
    return apps


def write_entry(name, pkg, icon):
    safe = re.sub(r"[^A-Za-z0-9_.-]", "_", pkg)
    path = os.path.join(APP_DIR, "%s%s.desktop" % (PREFIX, safe))
    # Two keys here are load-bearing, both copied from waydroid-runner.desktop:
    #
    #   X-Nemo-Application-Type=no-invoker
    #       Without it lipstick launches the entry through the Sailfish invoker
    #       booster, which expects a Qt application binary. A shell script under
    #       invoker never maps a window, so the launcher spinner just stops and
    #       the icon disappears with no error anywhere.
    #
    #   [X-Sailjail] Sandboxing=Disabled
    #       Leaving the section out does NOT mean "unsandboxed" -- this line
    #       does. A sandboxed wrapper cannot reach the Waydroid session socket
    #       under /run/display, so the launch fails silently.
    body = (
        "[Desktop Entry]\n"
        "Type=Application\n"
        "Name=%s\n"
        "Comment=Android app running in Waydroid\n"
        "Exec=/usr/bin/droid/waydroid-app-launch.sh %s\n"
        "Icon=%s\n"
        "Terminal=false\n"
        "Categories=Android;\n"
        "X-Nemo-Application-Type=no-invoker\n"
        "X-Waydroid-Package=%s\n"
        "\n"
        "[X-Sailjail]\n"
        "Sandboxing=Disabled\n"
    ) % (name, pkg, icon, pkg)
    with open(path, "w") as handle:
        handle.write(body)
    os.chmod(path, 0o644)
    return path


def main():
    os.makedirs(APP_DIR, exist_ok=True)

    # Drop entries from a previous run so uninstalled apps disappear too.
    for existing in os.listdir(APP_DIR):
        if existing.startswith(PREFIX) and existing.endswith(".desktop"):
            os.unlink(os.path.join(APP_DIR, existing))

    icon = pick_icon()
    apps = list_apps()
    if not apps:
        print("no apps found - is the Waydroid session running?")
        return 1

    for name, pkg in apps:
        write_entry(name, pkg, icon)
        print("  %-28s %s" % (name, pkg))
    print("wrote %d launcher entries to %s" % (len(apps), APP_DIR))
    return 0


if __name__ == "__main__":
    sys.exit(main())
