#!/bin/sh
# Apply the audio mixer routing that the Android vendor HAL would normally set.
#
# Usage:  droid-audio-route.sh [default|speaker|headphones|handset|all]
#
# There is no usable audio HAL on this port: the Samsung implementation
# (/vendor/lib/hw/audio.primary.exynos9611.so) is 32-bit only, so 64-bit
# PulseAudio can only dlopen the AOSP stub. Nothing therefore walks
# /vendor/etc/mixer_paths.xml, and without that the card comes up routed to
# nowhere with DAC1 Playback Volume at 0 -- silence on every output, which looks
# exactly like "audio is not supported" until you actually read the mixer. It
# has 381 controls and a fully attached Realtek RT5665 codec.
#
# Every value below is the vendor's own, resolved out of mixer_paths.xml:
#   media-headphone -> HPOL/HPOR via DAC1
#   media-speaker   -> the Richtek RT5510 amp, which hangs off ABOX UAIF2
#   media-handset   -> the earpiece, via DAC L2 fed from IF1 DAC2
#
# Deviations from the vendor table, both deliberate:
#
#   * The vendor drives the speaker from RDMA7 -> SIFS1 -> UAIF2. RDMA7 cannot be
#     opened here (-EIO every time), so UAIF2 is fed from SIFS0 instead -- the
#     same mixer output the headphone path uses, so one stream reaches both.
#
#   * "default" enables speaker and headphones together. Jack detection was the
#     HAL's job too, so nothing switches routes on plug/unplug; enabling both
#     means audio is audible either way, at the cost of the speaker playing while
#     headphones are inserted. The earpiece is left off, since it is a call path.
#
# Board note: this is A51 board REV01, which carries the Richtek RT5510.
# REV02 switched to a TI TAS2562 and Samsung ships one DTBO overlay per
# revision -- only the REV02 overlay declares the TI part. Both drivers are
# enabled in the defconfig, and whichever is present binds itself, so this
# script only needs to know which amp controls exist (see amp_present).

CARD=0
LOG=/var/log/audio-route.log
ROUTE=${1:-default}

log() { echo "audio-route: $*" >> "$LOG"; }

set_ctl() {
    if amixer -c "$CARD" cset name="$1" "$2" >/dev/null 2>&1; then
        log "ok   $1 = $2"
    else
        log "FAIL $1 = $2"
    fi
}

has_ctl() {
    amixer -c "$CARD" cget name="$1" >/dev/null 2>&1
}

# The ABOX driver registers the card well before this normally runs, but wait
# rather than race it.
i=0
while [ ! -e /proc/asound/card$CARD ] && [ $i -lt 30 ]; do
    sleep 1
    i=$((i + 1))
done
if [ ! -e /proc/asound/card$CARD ]; then
    log "card $CARD never appeared, giving up"
    exit 0
fi

: > "$LOG"
log "route=$ROUTE on $(cat /proc/asound/card$CARD/id 2>/dev/null)"

# ---- shared: ABOX mixer output to both interface links -------------------
set_ctl "ABOX UAIF0 SPK" SIFS0     # codec link: headphones + earpiece
set_ctl "ABOX UAIF2 SPK" SIFS0     # amp link: loudspeaker

# DAC1 is 0-175 and defaults to 0, which alone guarantees silence. Note this and
# the volumes below are cset-only controls: "amixer sset" reports success on
# them without changing anything.
set_ctl "DAC1 Playback Volume" 140,140
set_ctl "DAC1 MIXL DAC1 Switch" 1
set_ctl "DAC1 MIXR DAC1 Switch" 1
set_ctl "Stereo1 DAC MIXL DAC L1 Switch" 1
set_ctl "Stereo1 DAC MIXR DAC R1 Switch" 1

# ---- per-route outputs ---------------------------------------------------
hp=0; spk=0; ear=0
case "$ROUTE" in
    speaker)     spk=1 ;;
    headphones)  hp=1 ;;
    handset)     ear=1 ;;
    all)         hp=1; spk=1; ear=1 ;;
    *)           hp=1; spk=1 ;;   # default
esac

# Headphones: HPOL/HPOR off DAC1.
set_ctl "HPO Playback Switch" $hp
set_ctl "HEADPHONE Switch" $hp
[ "$hp" = 1 ] && set_ctl "Headphone Playback Volume" 12,12

# Loudspeaker: the smart amp. Mute_Enable is inverted -- 0 means unmuted.
set_ctl "SPEAKER Switch" $spk
if has_ctl "Mute_Enable"; then
    set_ctl "Mute_Enable" $([ "$spk" = 1 ] && echo 0 || echo 1)
    log "amp: Richtek RT5510 (REV01 board)"
elif has_ctl "TAS2562 Mute"; then
    log "amp: TI TAS2562 present (REV02 board) - routing may need adjusting"
fi

# Earpiece: a separate DAC channel. DAC L2 is fed from IF1 DAC2, not DAC1, which
# is why enabling the DAC1 chain alone leaves it silent -- and why in-call audio
# from the modem lands here naturally.
set_ctl "RECEIVER Switch" $ear
if [ "$ear" = 1 ]; then
    set_ctl "DAC L2 Mux" "IF1 DAC2"
    set_ctl "Mono DAC MIXL DAC L2 Switch" 1
    set_ctl "Mono MIX DAC L2 Switch" 1
    set_ctl "Mono Playback Switch" 1
    set_ctl "Mono Playback Volume" 15,15
else
    set_ctl "Mono Playback Switch" 0
fi

log "done (hp=$hp spk=$spk ear=$ear)"
exit 0
