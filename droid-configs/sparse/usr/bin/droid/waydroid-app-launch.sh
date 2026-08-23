#!/bin/sh
# Launch a single Android app from a Sailfish launcher icon.
#
# The whole trick is *who hosts the Android surface*.
#
# waydroid-runner is a nested Wayland compositor (QWaylandQuickCompositor +
# libwayland-server) wrapped in an ordinary Silica window. It publishes its own
# Wayland socket, has the container's hwcomposer connect to that instead of
# lipstick's, and forwards touch into the nested surface -- see
# /usr/share/waydroid-runner/qml/WindowContainer.qml, "touchEventsEnabled = true".
#
# Running "waydroid show-full-ui" directly against lipstick's socket also puts
# Android on screen, and it looks completely correct, but lipstick never sends
# touch events to that foreign surface: the container's hwcomposer opens each
# /dev/input/wl_*_events pipe lazily on the first event of that type, so
# wl_keyboard_events ends up open (compositors send keyboard focus events on
# their own) while wl_touch_events is never even opened. Android registers a
# perfectly healthy wayland_touch device that nothing ever writes to. The UI
# renders, accepts nothing, and reports no error anywhere.
#
# So: always host through the runner, then ask Android for the app inside it.
PKG=$1
LOG=/tmp/waydroid-launch.log

exec >>"$LOG" 2>&1
echo "=== launch $PKG (pid $$) ==="

[ -n "$PKG" ] || { echo "usage: $0 <android.package.name>"; exit 1; }

export XDG_RUNTIME_DIR=${XDG_RUNTIME_DIR:-/run/display}
export WAYLAND_DISPLAY=${WAYLAND_DISPLAY:-wayland-0}

session_running() {
    waydroid status 2>/dev/null | grep -qiE "session:[[:space:]]*running"
}

# The runner brings the session up under its own compositor, so this waits for
# it rather than starting one -- a session started here would bind lipstick's
# socket and lose touch, which is the exact bug this script exists to avoid.
ask_for_app() {
    i=0
    while [ $i -lt 90 ]; do
        session_running && break
        sleep 1
        i=$((i + 1))
    done
    if ! session_running; then
        echo "session never came up, not asking for $PKG"
        return 1
    fi
    # An activity started before Android has mapped a window on the new display
    # gets no input channel from InputDispatcher: dumpsys then shows
    # mCurrentFocus set while InputDispatcher's FocusedWindows list is empty,
    # and the app ignores touch. Let the display settle first.
    sleep 5
    echo "asking for $PKG"
    waydroid app launch "$PKG"
    # Idempotent -- a second request just brings it to the front, and covers
    # losing the race with the display coming up.
    sleep 4
    waydroid app launch "$PKG"
    echo "requested $PKG"
}

if pgrep -x waydroid-runner >/dev/null 2>&1; then
    # A second runner would try to publish a socket the first one already owns.
    # Reuse it: the app appears in the Waydroid window that is already open.
    echo "runner already running, reusing it"
    ask_for_app
    exit 0
fi

# Closing the Waydroid window kills the runner but leaves the session behind,
# still bound to the socket that died with it. Such a session accepts intents
# and shows nothing, so it has to go before a new runner can host anything.
if session_running; then
    echo "stale session from a closed runner, stopping it"
    waydroid session stop >/dev/null 2>&1
    i=0
    while session_running && [ $i -lt 20 ]; do
        sleep 1
        i=$((i + 1))
    done
    echo "stale session cleared after ${i}s"
fi

ask_for_app &

echo "starting waydroid-runner as the host"
exec waydroid-runner
