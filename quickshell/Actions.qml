pragma Singleton

// ═══════════════════════════════════════════════════════════════
// WHAT THE BAR DOES WHEN YOU CLICK IT.
//
// NONE OF THE FIVE POPUPS IS EWW'S NOW. The calendar went last, on
// 2026-09-28: the clock grows the body into CalendarPanel.qml. Sound
// (SoundPanel.qml), Search (SearchPanel.qml) and Bluetooth
// (BluetoothPanel.qml) moved on 2026-09-16, the way Wi-Fi did below.
// dunst, rofi and wlogout never learn anything changed.
//
// WI-FI IS NOT IN THIS FILE ANY MORE (2026-09-13). Its glyph grows the
// island's body into WifiPanel.qml -- the Datum Panels design, built in
// Quickshell -- and nothing here is involved. eww's network-panel and
// its scripts were deleted the same day; toggle-network.sh survives
// only as a one-line call to this shell's IPC, for the retired waybar.
//
// For the drawer and the session menu, this file is the whole seam.
// ═══════════════════════════════════════════════════════════════

import Quickshell

Singleton {
    readonly property string scripts: Quickshell.env("HOME") + "/.config/eww/scripts/"

    // The session menu is the one action that is not an eww panel --
    // it is wlogout, started by a script that lives with the
    // compositor's own config because that is where it has always
    // lived. Two directories, named, rather than one directory and a
    // special case.
    readonly property string hypr: Quickshell.env("HOME") + "/.config/hypr/conf/"

    // execDetached, never a Process: these scripts re-exec themselves
    // and outlive the call by design, and eww SIGKILLs a widget
    // handler at 200 ms unless it carries :timeout. Holding a pipe
    // open on them buys nothing and can wedge the caller -- a bare
    // `eww open-many` has been found still waiting after 5m35s.
    function run(script, dir) {
        Quickshell.execDetached(["bash", (dir === undefined ? scripts : dir) + script]);
    }
}
