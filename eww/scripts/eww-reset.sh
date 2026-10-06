#!/usr/bin/env bash
# ── THE PANIC BUTTON ─────────────────────────────────────────────────
# Bound to SUPER SHIFT R in hypr/conf/keybinds.conf.
#
# A Hyprland keybind is processed by the compositor BEFORE the keystroke
# is offered to any client, so this still fires when a layer surface has
# taken the keyboard exclusively -- which is the exact situation it is
# for. Nothing else on the desktop is reachable in that state: the
# pointer is being swallowed too, so there is no window to click and no
# menu to open.
#
# See the lock note in panel.sh for how the desktop gets there. That
# lock plus eww-watchdog.sh should mean this is never needed; it exists
# because "should" is not "will", and the failure mode it recovers from
# is a session you would otherwise have to log out of.
CFG="$HOME/.config/eww"

timeout 2 hyprctl dispatch 'hl.dsp.submap("reset")' >/dev/null 2>&1

# The daemon owns the layer surfaces, so killing it is what unmaps them.
# `eww close` cannot be trusted here: the state this recovers from
# includes the daemon's registry disagreeing with what is on screen, and
# in that state close answers "no such window" while the surface stays.
pkill -f "eww --config $CFG" 2>/dev/null
sleep 0.4
pkill -9 -f "eww --config $CFG" 2>/dev/null
sleep 0.2

setsid eww --config "$CFG" daemon >/dev/null 2>&1 &
notify-send -a Desktop "Popups reset" "eww restarted, input released." 2>/dev/null
exit 0
