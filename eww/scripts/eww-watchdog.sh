#!/usr/bin/env bash
# ── THE THING THAT NOTICES THE DESKTOP HAS GONE DEAF ─────────────────
#
# Read the lock note at the top of panel.sh first. Short version: an eww
# popup is a layer surface, the backdrop is a FULL-SCREEN one, and the
# launcher's keyboard twin is `:focusable true`, which under layer-shell
# is exclusive -- it takes the keyboard and every pointer event on the
# monitor. Both are invisible while the revealer inside them is
# collapsed. So the shape of this failure is not "a popup is stuck", it
# is "nothing on the screen responds and there is nothing to see".
#
# The lock in panel.sh removes the race that produced it. This is the
# net under that, and it is here because of what was actually found on
# 2026-09-03: popup-backdrop mapped at 0,50 4012x4012 for six minutes
# while eww's OWN registry reported no windows open. No script can close
# a window the daemon does not believe it has -- `eww close` answers
# "no such window" and the surface stays. Only killing the daemon drops
# it, and nothing was watching, so it stayed until someone looked.
#
# TWO FAULTS, TWO REMEDIES:
#
#   GHOST   a surface is mapped that eww does not list as open. The
#           daemon has leaked it; it cannot be closed. Restart eww.
#
#   ORPHAN  a panel is open and eww agrees it is open, but no submap is
#           active. Every open_panel sets one, so `default` here means
#           whatever opened this panel died before finishing. Escape is
#           unbound in that state, which is why the user cannot get out.
#           close_all is enough.
#
#   STUCK   a surface is mapped that has no business being on screen:
#           a panel whose revealer is collapsed, or the backdrop with no
#           panel behind it. Neither is a state any code path holds --
#           a panel is either revealed or closed -- so seeing one for
#           two ticks running means a close was truncated part way.
#           close_all finishes it.
#
#           THIS IS THE ONE THAT WAS MISSING, and it is the one the
#           desktop was actually failing on. The backdrop's :onclick was
#           being SIGKILLed by eww at 200ms inside close_all's roll-up
#           sleep (see the note at the top of close-popups.sh), so every
#           dismissal by backdrop click left popup-backdrop mapped over
#           the whole screen with panel-reveal false. GHOST does not see
#           it -- eww's registry still lists the window, correctly, as
#           open. ORPHAN does not see it -- the submap is still set.
#           Two faults that both describe disagreement, and the failure
#           was perfect agreement about a state that must not persist.
#
# WHY TWO STRIKES. Both conditions are briefly TRUE during a normal
# open: there is a window between `eww open` returning and the submap
# being dispatched, and another between Escape resetting the submap and
# close_all finishing. Both are a few hundred ms. Requiring the same
# fault on two consecutive ticks puts the bar at 2s+ of a state that
# should never last past one frame.
#
# COST: one `hyprctl layers` every 2s (~8ms) and nothing else -- eww is
# only asked about its windows when a surface is actually mapped, which
# is a few seconds a day.

CFG="$HOME/.config/eww"
EWW="timeout 3 eww --config $CFG"
INTERVAL=2

# ── ONE OF ME, AND CHEAP TO ASK ABOUT ───────────────────────────────
# Held for the life of the process, so `flock -n` on this file is an
# exact answer to "is the watchdog running" -- which is what
# ensure_watchdog in panel.sh needs, and what `pgrep -f eww-watchdog`
# could not give it: any shell whose command line merely MENTIONS this
# script matches that pattern, and an editor or a script that greps for
# the name would have answered yes while nothing was watching.
#
# It also makes starting it twice harmless. autostart.conf starts one at
# login and panel.sh starts one if it finds none; without this, a missed
# check would leave two loops both closing the same panels.
# ── SHED ANYTHING WE WERE HANDED ────────────────────────────────────
# This is started from panel.sh, which may be holding the panel lock at
# the time, and a child inherits its parent's descriptors: an flock is
# owned by the open file description, so an inherited fd means this loop
# would hold the panel lock for the entire session and every popup would
# time out on it. panel_spawn closes it on the way out, and this closes
# it on the way in -- the failure is silent, total, and looks exactly
# like the bug this script is here to catch, so it is worth stopping at
# both ends rather than trusting one.
for _f in /proc/self/fd/*; do
    _n="${_f##*/}"
    (( _n >= 3 )) 2>/dev/null || continue
    [[ "$(readlink "$_f" 2>/dev/null)" == "${XDG_RUNTIME_DIR:-/tmp}/eww-panel.lock" ]] \
        && eval "exec ${_n}>&-"
done
unset _f _n

WD_LOCK="${XDG_RUNTIME_DIR:-/tmp}/eww-watchdog.lock"
{ exec {WD_FD}>"$WD_LOCK"; } 2>/dev/null
[[ -n "${WD_FD:-}" ]] && { flock -n "$WD_FD" || exit 0; }

# popup-backdrop is not in panel.sh's PANELS list (it is opened
# alongside a panel, never on its own) and it is the single most
# dangerous surface to leave behind, so it is named explicitly here.
WATCHED=(calendar-panel
         popup-backdrop)

strikes=0
last=""

while :; do
    sleep "$INTERVAL"

    layers="$(timeout 2 hyprctl layers 2>/dev/null)" || continue
    [[ -z "$layers" ]] && continue

    mapped=(); panels=()
    for ns in "${WATCHED[@]}"; do
        grep -qE "namespace: ${ns}(,|\$)" <<<"$layers" || continue
        mapped+=("$ns")
        # The backdrop is not a panel. It is opened alongside one and
        # is meaningless on its own, which is exactly why it is tracked
        # separately here rather than counted with them.
        [[ "$ns" == popup-backdrop ]] || panels+=("$ns")
    done

    submap="$(timeout 2 hyprctl submap 2>/dev/null | tr -d '[:space:]')"
    [[ -z "$submap" ]] && submap="default"

    # Nothing of ours on screen. The only fault possible here is a
    # submap left behind, which silently eats Escape and the arrow keys
    # for the rest of the session.
    if (( ${#mapped[@]} == 0 )); then
        if [[ "$submap" == eww-* ]]; then
            fault="submap"
        else
            strikes=0; last=""; continue
        fi
    else
        active="$($EWW active-windows 2>/dev/null)"
        fault=""
        for ns in "${mapped[@]}"; do
            grep -q "^${ns}:" <<<"$active" || { fault="ghost"; break; }
        done

        # STUCK. Asked only when something is mapped, so this costs one
        # extra eww round trip on the few seconds a day a popup is up.
        #
        # Both halves are transiently true during a NORMAL open, which
        # is what the two-strike rule downstream is for: open_panel maps
        # the window before it sets panel-reveal (~50ms apart), and the
        # swap to a keyboard twin closes the old panel while leaving the
        # backdrop up (~100ms). Two strikes puts the bar at 2s of a
        # state that never survives one frame of animation.
        if [[ -z "$fault" ]]; then
            reveal="$($EWW get panel-reveal 2>/dev/null | tr -d '[:space:]')"
            if (( ${#panels[@]} > 0 )) && [[ "$reveal" != "true" ]]; then
                fault="stuck"
            elif (( ${#panels[@]} == 0 )); then
                fault="stuck"          # backdrop alone: nothing to back
            fi
        fi

        if [[ -z "$fault" && "$submap" == "default" ]]; then
            fault="orphan"
        fi
        [[ -z "$fault" ]] && { strikes=0; last=""; continue; }
    fi

    # Same fault twice running, or start the count over.
    if [[ "$fault" == "$last" ]]; then
        strikes=$((strikes + 1))
    else
        last="$fault"; strikes=1
    fi
    (( strikes < 2 )) && continue

    case "$fault" in
        ghost)
            "$HOME/.config/eww/scripts/eww-reset.sh" >/dev/null 2>&1
            notify-send -a Desktop "Desktop input recovered" \
                "A popup surface was left behind by eww and has been cleared." \
                2>/dev/null
            ;;
        orphan|stuck)
            # Subshell: close_all takes the panel lock and holds it for
            # the life of the process that took it. This loop must not
            # be that process.
            ( source "$HOME/.config/eww/scripts/panel.sh"; close_all ) \
                >/dev/null 2>&1
            # STUCK is the one fault a user is guaranteed to have
            # noticed -- the mouse has been dead for four seconds -- so
            # it says so. ORPHAN is invisible and stays quiet.
            [[ "$fault" == stuck ]] && notify-send -a Desktop \
                "Desktop input recovered" \
                "A popup was left over the screen and has been closed." \
                2>/dev/null
            ;;
        submap)
            timeout 2 hyprctl dispatch 'hl.dsp.submap("reset")' >/dev/null 2>&1
            ;;
    esac

    strikes=0; last=""
    # Give the remedy a moment to land before judging the state again.
    sleep 1
done
