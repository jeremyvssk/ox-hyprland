pragma Singleton

// ═══════════════════════════════════════════════════════════════
// WI-FI — is this radio on a network.
//
// Two states, and here that is the whole truth rather than a
// simplification: a Wi-Fi radio that is on and associated with nothing
// is not a resting state, it is the same answer as off to anyone
// glancing at a bar. (Bt.qml draws three for the opposite reason --
// idle is normal there.)
//
// SIGNAL STRENGTH IS NOT ON THIS GLYPH, and was not on the last one
// either. Four near-identical fans are unreadable at 15 px; strength
// lives in the panel this button opens, next to the SSID, where there
// is room for a number. → network.md
//
// ── WHAT IS ASKED, AND WHAT IS DELIBERATELY NOT ──────────────
//     nmcli -t -f TYPE,STATE device
//
// and NOT `nmcli dev wifi`, which is the obvious way to get the SSID
// and is the wrong call to make on every state change: it defaults to
// --rescan auto, so a stale list makes it START A SCAN. Scanning on
// every change is the Bluetooth mistake in a different radio --
// toggle-bluetooth.sh used to put the adapter into inquiry every time
// the panel opened, and that is how you get a link that comes up,
// drops and comes back. The device table is free and is the actual
// question.
//
// `wifi-p2p` is a separate TYPE from `wifi`, so the p2p-dev-* device
// that NetworkManager always lists cannot be mistaken for the radio.
//
// ── ETHERNET IS NOT DRAWN, ON PURPOSE ────────────────────────
// waybar's module had a third branch: connected with no SSID meant a
// cable, and it drew an ethernet rune. This does not, because the
// glyph is the label on a button that opens the WI-FI panel, and a
// control that draws one subsystem while opening another is the thing
// design-system.md forbids. On a machine on a cable with the radio
// down, this reads wifi-off -- which is true about Wi-Fi.
//
// ── THE SUBSCRIPTION ─────────────────────────────────────────
// `nmcli monitor` prints a line whenever NetworkManager changes
// anything and exits when NetworkManager goes away; Watcher.qml
// re-subscribes. Every line counts -- unlike BlueZ there is no
// per-beacon noise on this source, so there is nothing to filter and a
// filter would only be a list to get wrong later.
// ═══════════════════════════════════════════════════════════════

import Quickshell
import QtQuick

Singleton {
    id: root

    property bool up: false

    readonly property string icon: up ? "wifi" : "wifi-off"

    Watcher {
        subscribe: ["nmcli", "monitor"]
        reading: ["nmcli", "-t", "-f", "TYPE,STATE", "device"]

        onAnswered: out => {
            // -t escapes a literal colon as \: and neither of these two
            // fields can contain one anyway, so a plain split is safe
            // here in a way it is NOT safe on an SSID -- see the bug in
            // network.md that matched 0 of 12 saved profiles.
            let seen = false;
            let on = false;
            for (const line of out.split("\n")) {
                const f = line.split(":");
                if (f[0] !== "wifi") continue;
                seen = true;
                if (f[1] === "connected") on = true;
            }

            // No wifi device in the answer means nmcli had nothing to
            // say -- NetworkManager down, or the read failed. Hold.
            // A radio that is merely off still appears here, as
            // `wifi:unavailable`, so this is not the off state.
            if (!seen)
                return;

            root.up = on;
        }
    }
}
