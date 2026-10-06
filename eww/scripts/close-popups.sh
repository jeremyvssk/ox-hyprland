#!/usr/bin/env bash
# ── BACKDROP CLICK AND ESCAPE BOTH LAND HERE ────────────────────────
#
# ── AND IT FORKS, WHICH IS THE WHOLE POINT OF THIS FILE ─────────────
#
# THE COMPLAINT this fixes: "firefox doesn't run properly, can't press
# any buttons, keeps freezing" -- and nothing is wrong with firefox.
#
# WHAT WAS HAPPENING. eww runs a widget's :onclick synchronously and
# SIGKILLs it after 200ms unless the widget carries a `:timeout`. The
# backdrop is `(button :onclick "close-popups.sh")` and it carried none.
# close_all is
#
#     active-windows (~30ms) -> panel-reveal=false (~30ms)
#     -> sleep 190ms  (REVEAL_S, so the sheet rolls up)
#     -> eww close <every panel> popup-backdrop
#     -> submap reset
#
# which is ~250ms before it reaches the close. So the kill landed INSIDE
# the sleep, every single time, and the two lines that actually take the
# surfaces off the screen were unreachable code.
#
# What that leaves is the worst possible state and the least visible
# one: panel-reveal is false, so the panel has collapsed to 442x1 and
# there is nothing to see -- and popup-backdrop is still mapped, 4012 x
# 4012 at layer level `top`, a transparent GtkButton over the entire
# screen eating every click you make anywhere. The desktop looks normal
# and is completely dead to the mouse. Whatever you were using at the
# time -- Firefox, System Settings -- looks frozen, because every click
# you aim at it is being delivered to an invisible button instead.
#
# MEASURED, not deduced. A throwaway eww window with two buttons, one
# plain and one `:timeout "5s"`, running `echo start; sleep 1; echo end`:
# the plain one logged `start` and never `end`; the timeout one logged
# both. Then on the real config: open the calendar panel, click the
# backdrop, and `hyprctl layers` still showed `popup-backdrop 0 50 4012
# 4012` with `calendar-panel 350x1` beside it, `eww active-windows`
# agreeing both were open, and panel-reveal false. Reproducible on
# demand -- it is not a race, it happens on every backdrop dismissal.
#
# THE FIX is the one search.sh's launch path used (search.sh went with
# eww's launcher on 2026-09-16; backup/search-20260916/): get out of
# eww's 200ms window by not being in it. Re-exec detached and return
# immediately, so the process eww kills has already exited and the real
# work runs in a session of its own with no deadline on it.
#
# The backdrop button also carries a `:timeout` now (see eww.yuck). That
# is belt and braces for the day someone removes the fork above; the
# fork is what is load-bearing, because a `:timeout` long enough to
# cover close_all would also block eww's main thread for 250ms and the
# roll-up animation is drawn by that thread.
if [[ "${CLOSE_POPUPS_ASYNC:-}" != "1" ]]; then
    CLOSE_POPUPS_ASYNC=1 setsid "$0" "$@" >/dev/null 2>&1 &
    exit 0
fi

source "$HOME/.config/eww/scripts/panel.sh"
close_all
