#!/bin/bash
# Uncapped repo sync at -j8. Resumes whatever the throttled run already fetched.
export PATH=$HOME/bin:$PATH
source "$HOME/.hadk.env"
L=$HOME/a51-sfos-port/logs/repo-sync.log
S=$HOME/a51-sfos-port/logs/sync-status.txt
cd "$ANDROID_ROOT" || exit 1
echo "=== uncapped -j8 sync start $(date -Is) ===" >> "$L"
printf 'mode     uncapped, -j8\nstarted  %s\n' "$(date +%F' '%T)" > "$S"
repo sync -c -j8 --no-tags >> "$L" 2>&1
rc=$?
echo "=== sync exited rc=$rc $(date -Is) ===" >> "$L"
printf 'mode     uncapped, -j8\nfinished %s\nrc       %s\n' "$(date +%F' '%T)" "$rc" > "$S"
exit $rc
