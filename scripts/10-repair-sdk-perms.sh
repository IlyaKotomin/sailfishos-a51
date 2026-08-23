#!/bin/bash
# Repairs the damage from `sudo chown -R $USER /srv/sailfishos`.
#
# chown -R does two things you can't see: it changes the owner AND silently strips
# setuid/setgid bits from every binary. That broke sudo inside both chroots
# ("/etc/sudo.conf is owned by uid 1000, should be 0"), which breaks zypper/apt and
# sdk-assistant in the interactive sfossdk / ubu-chroot sessions.
#
# This restores root ownership and re-applies the exact setuid/setgid modes taken
# from the original tarballs - no re-download, and installed packages are kept.
set -e

# --- guard: must run on the HOST (Fedora), not inside sfossdk or ubu-chroot ---
. /etc/os-release 2>/dev/null
if [ ! -d /srv/sailfishos/sdks/sfossdk ] || [ "$ID" != "fedora" ]; then
  echo "!! This must run on the HOST, not inside a chroot."
  echo "!! Detected: ${NAME:-unknown} ${VERSION_ID:-}"
  echo
  echo "   You are probably in HABUILD or PlatformSDK. Leave them first:"
  echo "     exit      # HABUILD_SDK -> PlatformSDK"
  echo "     exit      # PlatformSDK -> host"
  echo "   then re-run:  ~/a51-sfos-port/10-repair-sdk-perms.sh"
  echo
  echo "   (sudo inside those chroots is exactly what is broken, so it cannot"
  echo "    repair itself from in there - the host's own sudo is unaffected.)"
  exit 1
fi

P=$HOME/a51-sfos-port
SDK=/srv/sailfishos/sdks/sfossdk
UBU=/srv/sailfishos/sdks/ubuntu

repair() {
  local root="$1" list="$2" label="$3"
  [ -d "$root" ] || { echo ">> $label not present, skipping"; return; }
  echo ">> $label: restoring root ownership"
  sudo chown -R root:root "$root"
  echo ">> $label: re-applying setuid/setgid modes ($(wc -l < "$list") files)"
  local n=0 miss=0
  while read -r mode path; do
    f="$root/${path#./}"
    if [ -e "$f" ]; then
      # translate the tar mode string (e.g. -rwsr-xr-x) into chmod symbolic form
      case "$mode" in
        -rws*) sudo chmod u+s "$f";;
      esac
      case "$mode" in
        *-sr-x|*r-sr-*|*-s??$) sudo chmod g+s "$f";;
      esac
      n=$((n+1))
    else
      miss=$((miss+1))
    fi
  done < "$list"
  echo "   applied to $n files ($miss listed files absent - fine if packages differ)"
}

repair "$SDK" "$P/reference/sdk-setuid-files.txt" "Platform SDK"
repair "$UBU" "$P/reference/ubu-setuid-files.txt" "Ubuntu (HABUILD)"

# targets/toolings are managed by sdk-assistant as root; hand them back too
for d in /srv/sailfishos/targets /srv/sailfishos/toolings /srv/sailfishos /srv/sailfishos/sdks; do
  sudo chown root:root "$d"
done

echo
echo ">> verify:"
ls -l "$SDK/usr/bin/sudo" "$UBU/usr/bin/sudo" 2>/dev/null
echo ">> expect -rwsr-xr-x root root on both. Then, inside sfossdk, sudo works again."
