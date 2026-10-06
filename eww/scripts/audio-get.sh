#!/usr/bin/env bash
set -euo pipefail
cmd="${1:-}"

have_wpctl() { command -v wpctl >/dev/null 2>&1; }

# ── ONE READ FOR ALL FOUR VALUES ────────────────────────────────────
# `wpctl get-volume` prints "Volume: 0.35" or "Volume: 0.35 [MUTED]", so
# a single call already carries both the level and the mute for one
# endpoint. audio-watch.sh fires on every PipeWire change -- which during
# a slider drag or a volume key repeat is dozens of times a second -- so
# what it costs to answer matters: four separate invocations of this
# script was 4 forks and 4 wpctl round trips per event, and it is now
# one fork and two.
#
# Prints: "<vol> <mute> <micvol> <micmute>", e.g. "35 false 60 true".
_one() {   # $1 = wpctl target; echoes "<0-100> <true|false>"
    local out lvl
    out=$(wpctl get-volume "$1" 2>/dev/null) || { echo "0 false"; return; }
    lvl=$(awk '{printf "%d", $2 * 100}' <<<"$out")
    [[ -z "$lvl" ]] && lvl=0
    if [[ "$out" == *MUTED* ]]; then echo "$lvl true"; else echo "$lvl false"; fi
}

case "$cmd" in
    state)
        if have_wpctl; then
            printf '%s %s\n' "$(_one @DEFAULT_AUDIO_SINK@)" "$(_one @DEFAULT_AUDIO_SOURCE@)"
        else
            # pactl fallback: four reads, but this path only runs on a
            # box without wireplumber, where nothing else here works
            # either.
            printf '%s %s %s %s\n' \
                "$("$0" volume)" "$("$0" mute)" "$("$0" mic-vol)" "$("$0" mic-mute)"
        fi
        ;;
    volume)
        if have_wpctl; then
            wpctl get-volume @DEFAULT_AUDIO_SINK@ 2>/dev/null \
                | awk '{printf "%d\n", $2 * 100}' || echo 0
        else
            pactl get-sink-volume @DEFAULT_SINK@ 2>/dev/null \
                | awk -F'/' 'NR==1{gsub(/ |%/,"",$2); print $2+0}' || echo 0
        fi
        ;;
    mute)
        if have_wpctl; then
            wpctl get-volume @DEFAULT_AUDIO_SINK@ 2>/dev/null | grep -q MUTED \
                && echo true || echo false
        else
            [[ "$(pactl get-sink-mute @DEFAULT_SINK@ 2>/dev/null)" == *yes* ]] \
                && echo true || echo false
        fi
        ;;
    sinks-json)
        default=$(pactl get-default-sink 2>/dev/null || echo "")
        pactl list sinks 2>/dev/null | awk -v def="$default" '
            BEGIN { printf "["; first=1 }
            /^\s*Name:/ { name=$2 }
            /^\s*Description:/ {
                sub(/^\s*Description:\s*/,"")
                desc=$0; gsub(/"/,"\\\"",desc)
                active = (name == def) ? "yes" : "no"
                if (!first) printf ","
                first=0
                printf "{\"name\":\"%s\",\"desc\":\"%s\",\"active\":\"%s\"}", name, desc, active
            }
            END { printf "]" }
        '
        ;;
    mic-vol)
        # `|| echo 0` never fired: awk exits 0 on EMPTY input, it just
        # prints nothing. With no capture device present at all -- which
        # is the normal state here once the headset disconnects -- the
        # panel rendered a bare "%" with no number in front of it. The
        # default has to come from awk's END, not from the exit code.
        if have_wpctl; then
            wpctl get-volume @DEFAULT_AUDIO_SOURCE@ 2>/dev/null \
                | awk '{printf "%d\n", $2 * 100; f=1} END{if (!f) print 0}'
        else
            pactl get-source-volume @DEFAULT_SOURCE@ 2>/dev/null \
                | awk -F'/' 'NR==1{gsub(/ |%/,"",$2); print $2+0; f=1} END{if (!f) print 0}'
        fi
        ;;
    mic-mute)
        if have_wpctl; then
            wpctl get-volume @DEFAULT_AUDIO_SOURCE@ 2>/dev/null | grep -q MUTED \
                && echo true || echo false
        else
            [[ "$(pactl get-source-mute @DEFAULT_SOURCE@ 2>/dev/null)" == *yes* ]] \
                && echo true || echo false
        fi
        ;;
    sources-json)
        default=$(pactl get-default-source 2>/dev/null || echo "")
        pactl list sources 2>/dev/null | awk -v def="$default" '
            BEGIN { printf "["; first=1 }
            /^\s*Name:/ { name=$2 }
            /^\s*Description:/ {
                sub(/^\s*Description:\s*/,"")
                desc=$0
                if (index(desc,"Monitor") > 0) next
                gsub(/"/,"\\\"",desc)
                active = (name == def) ? "yes" : "no"
                if (!first) printf ","
                first=0
                printf "{\"name\":\"%s\",\"desc\":\"%s\",\"active\":\"%s\"}", name, desc, active
            }
            END { printf "]" }
        '
        ;;
    # ── IS A HEADSET STUCK IN CALL MODE? ───────────────────
    # Prints the card name when a Bluetooth card is sitting on an
    # HSP/HFP profile, and nothing otherwise. That profile is a real
    # degradation and not a cosmetic one: the whole card drops to 16kHz
    # mono, so music played while it is active comes out at phone
    # quality. Found live during the meter work -- the headset was on
    # headset-head-unit with NOTHING holding the microphone, which is
    # wireplumber's autoswitch having gone in and not come back.
    #
    # Only bluez cards can be in this state; an analog card's profiles
    # do not have a call mode, so the name test keeps this from ever
    # firing on the built-in audio.
    hfp-card)
        pactl list cards 2>/dev/null | awk '
            /^Card #/            { name=""; }
            /^[ \t]+Name: /      { name=$2 }
            /^[ \t]+Active Profile: / {
                if (name ~ /^bluez_card\./ && $3 ~ /head-unit|handsfree/) {
                    print name; exit
                }
            }
        '
        ;;
esac
