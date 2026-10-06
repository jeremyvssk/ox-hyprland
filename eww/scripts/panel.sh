#!/usr/bin/env bash
# ── ONE PLACE FOR THE POPUP OPEN/CLOSE CHOREOGRAPHY ──────────────────
#
# The four bar popups (sound, network, bluetooth, calendar) used to be
# four copies of the same eight lines, and each copy just called
# `eww open`. Hyprland then animated the window in with the global
# `layersIn ... slide` rule, and THAT is what made them "come from the
# top of the screen":
#
#   Hyprland's layer slide offsets a layer by its OWN HEIGHT. A 400px
#   panel whose final top edge sits 60px down starts at y=-340, i.e.
#   entirely off-screen, and travels down ACROSS the island on its way
#   in. Nothing clips a layer animation to the bar, and there is no
#   `slide from <point>` -- so as long as the window is what moves, it
#   can only ever fly in from off-screen.
#
# So the window stopped moving (see the `noanim` layerrules in
# animations.conf) and the CONTENT animates instead: every panel body
# lives inside a GTK revealer driven by the shared `panel-reveal` var.
# The window is placed once, 10px under the island, and the sheet
# unrolls downward from that edge -- which is the "comes out from under
# the toolbar" read that was asked for.
#
# ONE var is enough for all four because exactly one panel is ever open:
# every entry point closes the others first.
#
# SWITCHING between two panels is the same choreography run twice, and
# it is deliberately sequenced rather than crossfaded: the old sheet
# rolls up, the window swaps while nothing is visible, the new sheet
# rolls down. Two panels of different heights sliding through each other
# is the thing that used to look wrong.

# ── EVERY eww CALL IS BOUNDED ────────────────────────────────────────
# Not defensive padding. Measured on 2026-09-03: the daemon can end up
# answering `active-windows` from its registry while its GTK side has
# stopped acting on commands, and in that state a bare `eww open-many`
# never returns -- a client was found still waiting after 5m35s. The
# script that called it was holding a half-open panel at the time, so a
# hang here is not "a popup is slow", it is "the desktop keeps an
# invisible full-screen surface and every click on it dies". 3s is far
# past the ~30ms a healthy call takes.
EWW="timeout 3 eww --config $HOME/.config/eww"

# ── THE LOCK, AND THE LOCKUP IT EXISTS TO PREVENT ────────────────────
#
# WHAT HAPPENED. Open the launcher and press Enter quickly -- which is
# the normal way to use it: Super+S, two letters, Enter -- and the
# desktop stops taking mouse clicks entirely. No panel is visible, so it
# does not look like a popup problem; it looks like the browser froze.
# It is not frozen. Nothing under the pointer is getting the click.
#
# WHY. open_panel is not atomic. Opening the launcher is
#
#     open-many backdrop+search-panel -> wait_mapped -> reveal
#     -> sleep 190ms -> open search-panel-kb -> wait_mapped
#     -> close search-panel -> submap
#
# ~500ms end to end, and every step is a separate round trip to the
# daemon. Enter lands in the middle of that: the GtkEntry fires
# search.sh launch, which forks and calls close_all. So close_all runs
# its `eww close` on the panels BEFORE the tail of open_panel opens
# search-panel-kb -- and the window that gets opened last is the one
# that stays. Nothing is left to close it: close_all already ran, the
# submap has been reset, and Escape is no longer bound to anything.
#
# What is left on screen is search-panel-kb with the revealer still
# collapsed: 442x1 px, invisible, and `:focusable true`, which under
# layer-shell is EXCLUSIVE -- it takes the keyboard AND, per the long
# note in eww.yuck, every pointer event on the monitor. Or the same race
# the other way round leaves popup-backdrop, a transparent full-screen
# GtkButton, mapped alone. Either way: an invisible surface eating all
# input, and no way back short of killing eww.
#
# REPRODUCED, not deduced: racing `open-many` against `close` on a
# throwaway eww instance leaves exactly these two states behind, and the
# live session was found in the second one -- popup-backdrop mapped at
# 0,50 4012x4012 with eww's own registry reporting no windows open.
#
# ── AND search-panel-kb NO LONGER EXISTS (2026-09-06) ───────────────
# The launcher is one `:focusable true` window now -- see the note where
# the hand-off used to be, near the end of _open_panel. The story above
# is kept because it is the reason this lock exists and the shape it
# guards against has not changed: the open choreography is still several
# round trips long and an Enter still lands in the middle of it. Only
# the leak it produced is now the backdrop rather than the twin, and the
# launcher's own surface is `:focusable true` from its first frame, so a
# leaked one is exactly as dangerous as the twin was.
#
# THE FIX IS SERIALISATION. Every entry point that opens or closes a
# panel takes this lock first, so the choreography above always runs to
# completion before the next one starts. Pressing Super+S twice fast now
# opens and then closes, which is what a toggle should do anyway.
#
# ── HELD FOR THE OPERATION, NOT FOR THE PROCESS ─────────────────────
# The obvious implementation -- take the lock and let the kernel drop it
# when the script exits -- is wrong here, and eww's old network-set.sh
# (deleted 2026-09-13, Wi-Fi is Quickshell now) was why: its double-click
# path called set_kb and then ran `nmcli connection up` IN THE SAME
# PROCESS. That is a 30s connect, and a process-lifetime
# lock would make every popup on the bar refuse to open for the duration
# of it. So the lock is scoped to the call, with a depth counter for the
# nesting (toggle_panel -> close_all / open_panel, both of which are
# public entry points that lock in their own right; flock on a second fd
# to the same file from the same process would deadlock against itself).
#
# The kernel is still the backstop: if a script is killed mid-operation
# -- and eww SIGKILLs :onclick handlers after 200ms, see eww.md --
# the fd dies with it and the lock is released. There is no stale-lock
# case to clean up.
PANEL_LOCK="${XDG_RUNTIME_DIR:-/tmp}/eww-panel.lock"

# -w 5, not -n. A caller that gives up on contention is the bug, not the
# fix: the Escape that arrives mid-open has to close the panel that open
# is still creating, and dropping it is how you get the orphan above.
# 5s is comfortably over the ~1.6s worst-case hold (two wait_mapped
# timeouts plus two reveal sleeps).
panel_lock() {
    PANEL_LOCK_DEPTH=$(( ${PANEL_LOCK_DEPTH:-0} + 1 ))
    (( PANEL_LOCK_DEPTH > 1 )) && return 0
    # Fail OPEN if the lock file itself cannot be opened. That is the
    # old, racy behaviour, and it is still better than a bar whose
    # buttons have stopped working because $XDG_RUNTIME_DIR went away.
    # Braced, so the 2>/dev/null applies to THIS open and nothing else.
    # Bare `exec {FD}>file 2>/dev/null` is a redirection on the shell
    # itself: it points the script's stderr at /dev/null permanently,
    # and every caller that sources this file would lose its diagnostics.
    { exec {PANEL_LOCK_FD}>"$PANEL_LOCK"; } 2>/dev/null || return 0
    if ! flock -w 5 "$PANEL_LOCK_FD"; then
        # 5s means the holder is wedged on something this script cannot
        # see. Proceeding without the lock is the old bug; refusing is
        # one popup that does not open, and the watchdog is watching.
        PANEL_LOCK_DEPTH=0
        exec {PANEL_LOCK_FD}>&-
        unset PANEL_LOCK_FD
        return 1
    fi
    return 0
}

# ── STARTING SOMETHING LONG-LIVED WHILE WE HOLD THE LOCK ────────────
#
# An flock lives on the OPEN FILE DESCRIPTION, not on the process, and a
# forked child inherits its parent's descriptors. So a background job
# started while this lock is held goes on holding it for as long as that
# job lives -- long after the script that took it has exited and every
# panel_unlock has run. The kernel backstop described above ("the fd
# dies with the process") is only true if no child kept a copy.
#
# MEASURED, and it produced the exact bug this lock exists to prevent:
# eww-watchdog.sh, spawned from the tail of _open_panel, inherited
# PANEL_LOCK_FD -- and being a `while :` loop it then held the panel
# lock for the whole session. Every popup afterwards waited 5s on flock,
# gave up, and did nothing at all. Found with a sweep of /proc/*/fd
# looking for who had the lock file open; the answer was the watchdog
# and its `sleep 2`.
#
# `{PANEL_LOCK_FD}>&-` closes that descriptor in the child only. So
# every background spawn under the lock goes out through here, and the
# lock file stays a thing only the operation itself holds.
panel_spawn() {
    if [[ -n "${PANEL_LOCK_FD:-}" ]]; then
        setsid "$@" >/dev/null 2>&1 {PANEL_LOCK_FD}>&- &
    else
        setsid "$@" >/dev/null 2>&1 &
    fi
    return 0
}

panel_unlock() {
    PANEL_LOCK_DEPTH=$(( ${PANEL_LOCK_DEPTH:-1} - 1 ))
    (( PANEL_LOCK_DEPTH > 0 )) && return 0
    PANEL_LOCK_DEPTH=0
    [[ -n "${PANEL_LOCK_FD:-}" ]] && exec {PANEL_LOCK_FD}>&-
    unset PANEL_LOCK_FD
    return 0
}

# ── AND HOW IT IS APPLIED ────────────────────────────────────────────
# Every public function below is a two-line wrapper around a `_`-
# prefixed body. The wrapper is not decoration: the bodies return from
# several places each (set_kb has four), and lock/unlock pairs sprinkled
# through them is exactly the kind of thing that ends up unbalanced
# after the next edit. One wrapper, one release, whatever the body does.
#
# ── AND THE LOCK IS TAKEN *HERE* ────────────────────────────────────
# It was not, for a while. panel_lock was written, documented at length
# above, and called from NOWHERE -- panel_guard ran the body and then
# released a lock it had never acquired, so every entry point raced
# exactly as it had before the lock existed and the note above described
# a fix that was not running.
#
# Found by reading, confirmed by reproducing: toggle-search.sh in the
# background, `search.sh launch 0` 50ms later (which is precisely what
# GtkEntry's activate does when you press Enter), and the desktop was
# left with search-panel-kb mapped alone -- exclusive keyboard,
# exclusive pointer, nothing else on the screen able to take a click.
# With the lock actually held the same race closes cleanly, every time.
#
# A caller that cannot get the lock does NOT run. See the note over
# `flock -w 5`: five seconds means the holder is wedged, and the worst
# outcome of refusing is one popup that does not open, which the
# watchdog can see and you can retry. Proceeding anyway is the bug.
panel_guard() {
    local fn="$1"; shift
    panel_lock || return 1
    "$fn" "$@"
    local rc=$?
    panel_unlock
    return $rc
}
# search-panel left on 2026-09-16: Search is quickshell/SearchPanel.qml.
# bluetooth-panel and its -kb keyboard twin left the same day: Bluetooth
# is quickshell/BluetoothPanel.qml. No panel left here has a twin.
PANELS=(calendar-panel)

# Must match :duration on the revealers in eww.yuck. A little under, not
# over: GTK has already finished the visible part of the collapse by the
# time the tail of the curve runs, and waiting the full duration puts a
# perceptible dead beat in the middle of a panel switch.
REVEAL_S=0.19

# GtkRevealer only ANIMATES a widget that is already mapped; flipping
# reveal_child on an unmapped one snaps straight to the end state. So the
# window has to be on screen in its collapsed form before the var flips.
# `eww open` returns before that has happened, and a fixed sleep is
# either a guess that is too short (measured: at 60ms the panel appeared
# in a single frame, no unroll at all) or a guess that is too long, which
# is dead time between the click and anything moving.
#
# The layer surface appearing in `hyprctl layers` IS the map, so wait for
# exactly that and no longer. ~8ms per hyprctl round trip.
#
# The match must be ANCHORED at both ends. `hyprctl layers` prints
# `namespace: bluetooth-panel, pid: 2495`, so a bare grep for
# "namespace: bluetooth-panel" also matches bluetooth-panel-kb -- which
# would make the swap between the two return instantly and every time,
# on the wrong window.
wait_mapped() {
    local ns="$1" i
    for i in $(seq 1 40); do
        timeout 2 hyprctl layers 2>/dev/null | grep -qE "namespace: ${ns}(,|\$)" && return 0
        sleep 0.01
    done
    return 1
}

is_open() { $EWW active-windows 2>/dev/null | grep -q "^$1:"; }

# ── MAKE SURE THE NET IS ACTUALLY UNDER US ──────────────────────────
# eww-watchdog.sh is started by `exec-once` in hypr/conf/autostart.conf,
# and exec-once has one property that matters here: it runs at login and
# never again. `hyprctl reload` does not re-run it. So the watchdog was
# ADDED to autostart in the middle of a session and then did not exist
# for the whole rest of that session -- the desktop spent hours with no
# net under it while the config on disk said there was one. That is not
# a hypothetical; it is what `ps` showed when this was looked at.
#
# Same hole if it ever dies: nothing would bring it back until logout.
#
# So opening a panel -- the moment the net starts mattering -- also
# checks that it is there. `pgrep -f` is ~4ms and this is called AFTER
# the panel is on screen, so it is off the path between the keypress and
# the animation. Detached, so a slow start cannot hold the lock.
# The watchdog holds a flock for its whole life, so taking that lock
# non-blockingly IS the liveness test -- and unlike `pgrep -f`, it
# cannot be fooled by another process that merely has the script's name
# somewhere on its command line. Starting a second one is harmless
# anyway: it takes the same lock and exits.
ensure_watchdog() {
    local fd start=0
    { exec {fd}>"${XDG_RUNTIME_DIR:-/tmp}/eww-watchdog.lock"; } 2>/dev/null || return 0
    flock -n "$fd" && { flock -u "$fd"; start=1; }
    # Closed BEFORE the spawn, not after: the child would inherit this
    # descriptor too, and the whole point of the file is that holding it
    # means "a watchdog is running".
    exec {fd}>&-
    (( start )) && panel_spawn "$HOME/.config/eww/scripts/eww-watchdog.sh"
    return 0
}

# ── WHICH SUBMAP A PANEL GETS ────────────────────────────────────────
# Every panel needs Escape, and Escape alone is `eww-popup`. The launcher
# had its own `eww-search` submap for Up, Down and Return; it went with
# eww's search-panel on 2026-09-16, so every panel left gets this one.
#
# Defined in hypr/conf/keybinds.lua. A submap only consumes the keys it
# BINDS; every other keystroke still reaches the client.
submap_for() {
    printf 'eww-popup'
}

# ONE `eww active-windows` for the whole list, not one per panel.
#
# This used to call is_open in the loop, which is an `eww active-windows`
# per entry -- measured at ~30 ms a call. With five panels that was
# 150 ms, and it is paid TWICE on every open (toggle_panel asks, then
# open_panel asks again), so a third of the delay between clicking a bar
# icon and anything moving was this function talking to the daemon about
# windows it had already been told about. Adding the launcher's two
# windows would have made it 210 ms a call.
#
# is_open is kept for callers that genuinely want to ask about one
# window; it is deliberately no longer used here.
open_panel_name() {
    local active p
    active="$($EWW active-windows 2>/dev/null)" || return 1
    for p in "${PANELS[@]}"; do
        grep -q "^$p:" <<<"$active" && { printf '%s' "$p"; return 0; }
    done
    return 1
}

# ── WHAT A PANEL DOES ON ITS WAY OUT ────────────────────────────────
# Nothing, now. The hook existed for eww's Bluetooth panel, which emptied
# its Nearby list on close; it went with that panel on 2026-09-16.

# $1 is the panel that is on screen, when the caller knows it -- both
# callers do. It matters because the launcher rolls up on a DIFFERENT
# var from the other four.
#
# Every panel left is one revealer holding everything, so panel-reveal
# false collapses the lot. (The launcher needed a second revealer,
# search-shell, and went to Quickshell on 2026-09-16.)
roll_up() {
    $EWW update panel-reveal=false >/dev/null 2>&1
    sleep "$REVEAL_S"
}

_close_all() {
    local cur
    if cur="$(open_panel_name)"; then
        roll_up "$cur"
    fi
    $EWW close "${PANELS[@]}" popup-backdrop >/dev/null 2>&1
    timeout 2 hyprctl dispatch 'hl.dsp.submap("reset")' >/dev/null 2>&1
}

# $2 is optional and is what is ALREADY open, when the caller happens to
# know -- toggle_panel does, because it just asked. Passing it saves an
# `eww active-windows` round trip (~30 ms) on the one path where every
# round trip is between a keypress and the first thing that moves.
# Omitted, this asks for itself, so direct callers still work.
_open_panel() {
    local want="$1" cur="${2-__ask__}"
    [[ "$cur" == "__ask__" ]] && { cur="$(open_panel_name)" || cur=""; }

    # Something else is showing: roll it up before the swap, so the
    # window never changes size while it is visible.
    if [[ -n "$cur" ]]; then
        roll_up "$cur"
        $EWW close "${PANELS[@]}" >/dev/null 2>&1
    fi

    # Belt and braces: if the var were left true (a killed script, a
    # daemon restart) the new panel would map fully expanded.
    $EWW update panel-reveal=false >/dev/null 2>&1

    # One round trip, not two. The backdrop and the panel are always
    # opened together and each `eww open` costs ~30 ms against the
    # daemon.
    $EWW open-many popup-backdrop "$want" >/dev/null 2>&1
    wait_mapped "$want"
    $EWW update panel-reveal=true >/dev/null 2>&1
    timeout 2 hyprctl dispatch "hl.dsp.submap(\"$(submap_for "$want")\")" >/dev/null 2>&1

    ensure_watchdog
}

_toggle_panel() {
    local cur
    cur="$(open_panel_name)" || cur=""
    if [[ -n "$cur" && "$cur" == "$1" ]]; then
        close_all
    else
        open_panel "$1" "$cur"
    fi
}

# ── THE KEYBOARD SWAP ────────────────────────────────────────────────
# set_kb swapped a panel for its focusable -kb twin while a text field was
# on screen. Its last user, eww's Bluetooth panel, went to Quickshell on
# 2026-09-16, and it went with it. The reason it had to be two windows is
# in panels.md.

# ── THE PUBLIC ENTRY POINTS ─────────────────────────────────────────
# Defined last so the bodies above are all in scope. Sourcing this file
# gets you these three and nothing else changes for the caller: the
# signatures are identical to what they were before the lock existed.
close_all()    { panel_guard _close_all    "$@"; }
open_panel()   { panel_guard _open_panel   "$@"; }
toggle_panel() { panel_guard _toggle_panel "$@"; }
