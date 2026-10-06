#!/usr/bin/env bash
# ── DISPLAY LAYOUT — Hyprland-native. Replaces kanshi. ────────────────
#
# WHY KANSHI HAD TO GO.
# kanshi drives the compositor from OUTSIDE, over the generic
# wlr-output-management protocol. It can only act once Hyprland is up,
# the DRM connectors are enumerated AND the protocol is bound — and if
# it loses that race at boot, nothing ever retries. The session then
# sits on whatever `monitor = ,preferred,auto,1` produced, which for
# this panel is 3440x1440@59.97 (the EDID *preferred* mode is 60 Hz,
# not 100) with the laptop panel still lit. That is precisely the state
# that typing `kanshi` by hand used to repair.
#
# Hyprland applies its own `hl.monitor()` rules from inside the connect
# path, so a rule can never be "too early". Everything that CAN be a
# rule is now one, in hyprland.lua. The one thing a rule cannot
# express is the conditional —
#
#     disable eDP-1, but only while HDMI-A-1 is attached
#
# — so that lives here: applied once at startup, and again on every
# hotplug event read off Hyprland's own event socket. No polling, no
# race, and no second process that can silently lose one.
#
# Run by hand any time with:  ~/.config/hypr/conf/monitors.sh apply
# or the keybind SUPER SHIFT M.

EXTERNAL="HDMI-A-1"
EXTERNAL_RULE='mode = "3440x1440@99.98", position = "0x0", scale = "1"'
INTERNAL="eDP-1"
INTERNAL_RULE='mode = "1920x1080@144", position = "auto", scale = "1"'

STATE="${XDG_RUNTIME_DIR:-/tmp}/hypr-monitors.state"

log() { printf '[%s] %s\n' "$(date +%H:%M:%S)" "$*" >> "$HOME/.cache/hypr-monitors.log"; }

# Runtime rules go through `eval`, and the reply is CHECKED. This path
# spent a whole session failing silently — the old `hyprctl keyword` call
# discarded stderr, so the refusal was never seen and apply() went on to
# log "layout -> external" as if it had worked. `eval` answers a bare
# "ok", or a readable error; anything that is not "ok" is a bug.
hypr_eval() {
    local out
    out=$(hyprctl eval "$1" 2>&1)
    [[ "$out" == "ok" ]] || log "eval failed: $out"
}

apply() {
    local mons want
    mons=$(hyprctl monitors all -j 2>/dev/null) || return 1
    [[ -z "$mons" ]] && return 1

    if jq -e --arg n "$EXTERNAL" 'any(.[]; .name == $n)' <<<"$mons" >/dev/null 2>&1; then
        want="external"
    else
        want="internal"
    fi

    # Re-apply the rules unconditionally — cheap, and it is what repairs
    # a boot where Hyprland brought the panel up on its preferred mode.
    # `hyprctl keyword` is inert under a Lua config — it refuses with
    # "keyword can't work with non-legacy parsers. Use eval." and changes
    # nothing at all. Both branches therefore issue Lua.
    if [[ "$want" == "external" ]]; then
        hypr_eval "hl.monitor({ output = \"$EXTERNAL\", $EXTERNAL_RULE })
                   hl.monitor({ output = \"$INTERNAL\", disabled = true })"
    else
        # `disabled` is STICKY: a spec MERGES into the rule already on the
        # output, so naming a mode is not enough to light the panel again.
        # Measured — without the explicit false, unplugging the external
        # leaves the session with no enabled monitor at all.
        hypr_eval "hl.monitor({ output = \"$INTERNAL\", $INTERNAL_RULE, disabled = false })"
    fi

    if [[ "$want" != "$(cat "$STATE" 2>/dev/null)" ]]; then
        log "layout -> $want"
        printf '%s\n' "$want" > "$STATE"
        # eww binds its popups to a monitor INDEX, so the index has to be
        # re-resolved when the set of active outputs changes. Nothing else
        # on the bar cares: waybar tracks outputs itself.
        if pgrep -x eww >/dev/null 2>&1; then
            ( sleep 1
              pkill -x eww 2>/dev/null
              eww --config "$HOME/.config/eww" daemon ) &
        fi
    fi
}

listen() {
    local sock="${XDG_RUNTIME_DIR}/hypr/${HYPRLAND_INSTANCE_SIGNATURE}/.socket2.sock"
    # Wait for the socket rather than assume it: this may start before
    # Hyprland has finished opening it.
    for _ in {1..40}; do [[ -S "$sock" ]] && break; sleep 0.25; done
    [[ -S "$sock" ]] || { log "no socket2 at $sock — hotplug handling disabled"; return 1; }

    socat -U - UNIX-CONNECT:"$sock" 2>/dev/null | while read -r line; do
        case "$line" in
            monitoradded*|monitorremoved*)
                # DRM settles a beat after the event; applying into the
                # middle of that gets ignored.
                sleep 0.4
                apply
                ;;
            configreloaded*)
                # Re-measured on 0.56.2 + Lua and the answer FLIPPED: a
                # runtime disable does NOT survive `hyprctl reload` any
                # more — the config is re-evaluated and eDP-1 comes back
                # lit. So this branch is load-bearing, not belt and
                # braces: without it the laptop panel turns itself back
                # on every time the config is saved.
                sleep 0.3
                apply
                ;;
        esac
    done
}

case "${1:-daemon}" in
    apply)  apply ;;
    daemon)
        # First pass immediately — by the time exec-once runs, the
        # connectors Hyprland found at startup are already there.
        apply
        # A second pass a moment later catches an output that arrived
        # while Hyprland was still coming up (the old kanshi race).
        ( sleep 2; apply ) &
        listen
        ;;
esac
