#!/usr/bin/env bash
set -euo pipefail

cmd="${1:-}"
arg="${2:-}"

have_wpctl() { command -v wpctl >/dev/null 2>&1; }

# Only the restart button needs to push a var back; the rest of this
# script changes PipeWire and lets audio-watch.sh do the repainting.
EWW="eww --config $HOME/.config/eww"

_float() {
    # Convert integer 0-100 to float 0.00-1.00 for wpctl
    awk "BEGIN {printf \"%.2f\", ${1}/100.0}"
}

case "$cmd" in
    volume)
        vol="${arg:-0}"
        (( vol > 100 )) && vol=100
        (( vol < 0   )) && vol=0
        if have_wpctl; then
            wpctl set-volume -l 1.0 @DEFAULT_AUDIO_SINK@ "$(_float "$vol")"
        else
            pactl set-sink-volume @DEFAULT_SINK@ "${vol}%"
        fi
        ;;
    volume-up)
        if have_wpctl; then
            wpctl set-volume -l 1.0 @DEFAULT_AUDIO_SINK@ 5%+
        else
            pactl set-sink-volume @DEFAULT_SINK@ +5%
        fi
        ;;
    volume-down)
        if have_wpctl; then
            wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%-
        else
            pactl set-sink-volume @DEFAULT_SINK@ -5%
        fi
        ;;
    mute-toggle)
        if have_wpctl; then
            wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle
        else
            pactl set-sink-mute @DEFAULT_SINK@ toggle
        fi
        ;;
    set-sink)
        name="${arg:-}"
        [[ -z "$name" ]] && exit 0
        pactl set-default-sink "$name"
        # Move all existing streams to the new sink
        pactl list short sink-inputs | awk '{print $1}' | \
            xargs -I{} pactl move-sink-input {} "$name" 2>/dev/null || true
        ;;
    mic-volume)
        vol="${arg:-0}"
        (( vol > 100 )) && vol=100
        (( vol < 0   )) && vol=0
        if have_wpctl; then
            wpctl set-volume -l 1.0 @DEFAULT_AUDIO_SOURCE@ "$(_float "$vol")"
        else
            pactl set-source-volume @DEFAULT_SOURCE@ "${vol}%"
        fi
        ;;
    mic-mute-toggle)
        if have_wpctl; then
            wpctl set-mute @DEFAULT_AUDIO_SOURCE@ toggle
        else
            pactl set-source-mute @DEFAULT_SOURCE@ toggle
        fi
        ;;
    set-source)
        name="${arg:-}"
        [[ -z "$name" ]] && exit 0
        pactl set-default-source "$name"
        pactl list short source-outputs | awk '{print $1}' | \
            xargs -I{} pactl move-source-output {} "$name" 2>/dev/null || true
        ;;

    # ── THE TEST TONE ─────────────────────────────────────────────
    # Plays through @DEFAULT_AUDIO_SINK@ with no --target, which is by
    # definition the sink this panel draws the dot on -- so there is
    # nothing to look up and nothing to pass in.
    #
    # setsid, and the reason is NOT the one you would expect. eww
    # SIGKILLs a widget handler at 200ms (see eww.md) and the tone is
    # 1.41s, so the obvious story is that it gets cut off -- but that
    # was measured and it is wrong. eww kills the SHELL, and pw-play is
    # orphaned rather than group-killed, so the tone plays out either
    # way: 1330ms with setsid, 1279ms without.
    #
    # What setsid actually buys is visible in pgid/sid, clicked live:
    #
    #     eww                pid 317117  pgid 317116  sid 317116
    #     setsid pw-play     pid 366481  pgid 366481  sid 366481
    #     plain  pw-play     pid 366671  pgid 317116  sid 317116
    #
    # Without it the tone sits in EWW'S OWN process group and session,
    # so anything that signals that group -- the daemon exiting, a
    # startup.sh restart -- takes the tone with it. With it, the tone is
    # its own session and owes eww nothing.
    #
    # The file comes from `sound-theme-freedesktop`. Silent death is the
    # one failure mode a TEST button must not have -- if it is missing
    # you would read "no sound" as a hardware answer -- hence the
    # fallback and the explicit exit rather than letting pw-play fail.
    #
    # On the bluez sink the tone starts ~150-200ms late. That is A2DP
    # latency, not a bug, and this kind of thing has been reported as
    # one here before.
    test)
        snd="/usr/share/sounds/freedesktop/stereo/audio-test-signal.oga"
        [[ -f "$snd" ]] || snd="/usr/share/sounds/freedesktop/stereo/bell.oga"
        [[ -f "$snd" ]] || exit 0
        setsid pw-play "$snd" >/dev/null 2>&1 &
        ;;

    # ── THE MIC TEST ──────────────────────────────────────────────
    # The input half of Test, and the only thing this case does is
    # write one word down a fifo: mic-meter.sh is a deflisten that has
    # been sitting blocked on that read since the daemon started, and
    # it owns the capture. The reasoning for that shape -- eww update
    # at ~15ms a call against a 20fps meter -- is in the header of that
    # script.
    #
    # The write cannot block, because mic-meter.sh holds the fifo open
    # read/write; the timeout is only there so that a press with the
    # listener dead fails in 300ms instead of hanging until eww's 200ms
    # kill lands on it.
    #
    # It does NOT drop the headset to call quality, which was the
    # expected cost and was measured not to happen -- see the profile
    # note in mic-meter.sh. If something else ever does, the High
    # quality pill appears in the bottom row by itself.
    mic-test)
        fifo="${XDG_RUNTIME_DIR:-/tmp}/eww-mic-meter.fifo"
        [[ -p "$fifo" ]] || exit 0
        timeout 0.3 bash -c 'printf "start\n" > "$1"' _ "$fifo" >/dev/null 2>&1 &
        ;;

    # ── STOPPING IT ───────────────────────────────────────────────
    # The same pill, pressed while it is listening. It does NOT go down
    # the fifo: mic-meter.sh is inside the capture pipeline for those
    # six seconds and nothing is reading that fifo until they are over,
    # so a word written there would be acted on after the capture it
    # was meant to cut short. The peak reader is the part that is awake
    # -- twenty times a second -- so the flag goes where it will be
    # seen. It clears the flag itself when the capture ends; touching
    # it here and removing it there is what keeps a stop from leaking
    # into the next press.
    mic-stop)
        : > "${XDG_RUNTIME_DIR:-/tmp}/eww-mic-meter.stop"
        ;;

    # ── BACK TO HIGH QUALITY ──────────────────────────────────────
    # The narrow half of Restart. A headset left on an HSP/HFP profile
    # plays everything at 16kHz mono, and the fix is one profile write
    # -- no torn-down graph, no dropped streams, nothing to reconnect.
    # Restart also clears it, but it clears it by rebuilding the whole
    # server, which is a sledgehammer for a card property.
    #
    # The profile is CHOSEN, not hardcoded: this headset offers AAC
    # (a2dp-sink, priority 133), SBC-XQ (131) and SBC (132) and the
    # right one is whichever available a2dp profile the card rates
    # highest. Hardcoding "a2dp-sink" happens to be correct here and
    # would silently pick a worse codec on the next headset.
    hq)
        card=$("$(dirname "$0")/audio-get.sh" hfp-card)
        [[ -z "$card" ]] && exit 0
        prof=$(pactl list cards 2>/dev/null | awk -v c="$card" '
            /^Card #/                 { incard = 0 }
            /^[ \t]+Name: /           { incard = ($2 == c) }
            incard && /^[ \t]+a2dp-sink[^ ]*: / {
                name = $1; sub(/:$/, "", name)
                p = 0
                if (match($0, /priority: [0-9]+/))
                    p = substr($0, RSTART + 10, RLENGTH - 10) + 0
                if ($0 ~ /available: yes/ && p > best) { best = p; sel = name }
            }
            END { print sel }
        ')
        [[ -z "$prof" ]] && prof="a2dp-sink"
        pactl set-card-profile "$card" "$prof"
        ;;

    # ── RESTART: THE "SOUND HAS GONE STUPID" BUTTON ───────────────
    # The structural twin of Rescan on the network panel and Scan on
    # bluetooth. Every panel in this set ends in the action you take
    # when the subsystem underneath it is misbehaving; for PipeWire
    # that is this, and the alternative was opening a terminal.
    #
    # IT IS DISRUPTIVE, so it is armed first and fired second. The two
    # presses are two separate cases because eww picks which one to send
    # from audio-restart-arm (the :onclick ternary in eww.yuck), so this
    # script never has to read eww state back out.
    #
    # The disarm timer is detached for the same 200ms reason as above: a
    # `sleep 3` inside the handler is killed at 200ms and the button
    # would stay armed for the rest of the session.
    restart-arm)
        $EWW update audio-restart-arm=yes >/dev/null 2>&1 || true
        setsid bash -c "sleep 3; $EWW update audio-restart-arm=no" \
            >/dev/null 2>&1 &
        ;;

    # WHAT SURVIVES THIS: audio-watch.sh, whose `pactl subscribe` loop is
    # wrapped in `while :;` precisely so that a pipewire-pulse restart
    # reconnects and repaints instead of leaving the panel frozen on
    # stale numbers -- and waybar's volume module, which that same
    # watcher signals. The panel is deliberately left OPEN, so the
    # device lists can be watched repopulating.
    #
    # WHAT DOES NOT: streams held by apps that do not reconnect (mpv,
    # some Electron), which have to be restarted themselves. BlueZ is
    # untouched -- bluetoothd is a system service -- so the headset
    # stays paired and connected and only its A2DP node is rebuilt.
    restart-go)
        $EWW update audio-restart-arm=no >/dev/null 2>&1 || true
        setsid systemctl --user restart wireplumber pipewire pipewire-pulse \
            >/dev/null 2>&1 &
        ;;
esac
