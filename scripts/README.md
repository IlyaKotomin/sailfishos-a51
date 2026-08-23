# Helper scripts

Scripts used while building and debugging this port. They are conveniences, not
part of the image — read one before running it, and expect to adjust paths for
your own setup.

None of them contain credentials. The SSH helpers require `A51_HOST` and
`A51_PASS` in the environment and refuse to run without them.

## Setting up a build environment

| Script | Purpose |
|---|---|
| `1-install-platform-sdk.sh` | Fetch and unpack the Sailfish Platform SDK |
| `2-inside-sdk-setup.sh` | Run inside the SDK chroot: tooling, targets, and disabling password aging in the Ubuntu chroot |
| `3-add-swap.sh` | Add swap — the Android build and the `mic` image step both want more RAM than this class of machine has |
| `4-post-sync.sh` | Fix-ups after a `repo sync` |
| `5-bootstrap-droid-hal.sh` | First droid-hal build |
| `6-habuild-build.sh` | Build `hybris-hal` inside the HABUILD (Ubuntu) chroot |
| `7-build-bwrap.sh` | Build without root, via bubblewrap |
| `9-sdk-target.sh`, `11-sdk-target-install.sh` | Manage the aarch64 build target |
| `10-repair-sdk-perms.sh` | Repair SDK permissions after a botched `sudo` |

`fast-sync.sh` and `throttled-sync.py` make `repo sync` survive a domestic
connection — the manifest pulls tens of gigabytes and the default parallelism
tends to stall.

## Driving the build

`sdk-run.sh` sends a command into an interactive Platform SDK session running in
`tmux` and waits for it to finish:

```bash
tmux new -s sdk        # then, inside it:  sfossdk
./sdk-run.sh 'cd $ANDROID_ROOT && rpm/dhd/helpers/build_packages.sh --configs' 900
```

This exists because the SDK wants an interactive shell, while builds want to be
scripted and take long enough that you do not want to babysit them.

## Talking to the phone

```bash
export A51_HOST=192.168.x.y            # from Settings -> Developer tools
export A51_PASS=<developer-mode password>
./ssh/a51 'uname -a'                   # run a command
./ssh/a51-push local.file /remote/path # copy a file over
```

`askpass.sh` feeds the password to `ssh` non-interactively, since `sshpass` is
not available. Two things to expect from this device: it never answers ping, and
its Wi-Fi is slow to wake, so use generous timeouts and wake the screen first.

For anything Android-side, capture the container's own screen rather than
fighting the lipstick screenshot API:

```bash
./ssh/a51 'echo $A51_PASS | devel-su /bin/sh -c \
  "lxc-attach -P /var/lib/waydroid/lxc -n waydroid -- /system/bin/screencap -p /data/local/tmp/s.png"'
```

## Debugging

| Script | Purpose |
|---|---|
| `8-prep-flash-host.sh` | Prepare the host for flashing (heimdall, udev rules) |
| `12-pull-logs.sh` | Collect logs off the device |
| `13-analyze-core.sh` | Inspect a core dump |
| `waydroid-bench.sh` | Rough Waydroid performance measurements |
