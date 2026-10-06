pragma Singleton

// ═══════════════════════════════════════════════════════════════
// WIFI — what the Wi-Fi PANEL reads and does. The bar glyph is still
// Network.qml; this is the list, the connection, and the four verbs.
//
// NATIVE, NOT nmcli. Quickshell 0.3.1 DOES ship NetworkManager, as
// `Quickshell.Networking` -- it lives at Quickshell/Networking, not
// under Quickshell/Services/, which is why an earlier read of this
// install concluded it did not exist. Probed 2026-09-13 against the
// live NetworkManager: the radio, every network in range once the
// scanner is on, signal, security, saved-or-not, connected, and
// connect / connectWithPsk / disconnect / forget. So by the "bind the
// service" rule the panel binds it, and three things eww's panel
// fought are gone rather than handled:
//
//   * THE PASSWORD NEVER TOUCHES ARGV. connectWithPsk hands it to
//     NetworkManager over D-Bus. network-set.sh put it on stdin for
//     the long call and still leaked it into an `eww update` argv for
//     a microsecond, and a password containing ' could not be stored
//     at all. Neither is true here.
//   * THE 802-11-wireless BUG CANNOT HAPPEN. `known` is the service's
//     answer, not an awk pattern over a type string. → network.md
//   * ONE ROW PER SSID. The service groups access points by name, so a
//     router with a 2.4 and a 5 GHz radio is one row. BUG-4's
//     duplicates were the raw scan; this is not the raw scan.
//
// ── SCANNING IS TIED TO THE PANEL BEING OPEN ────────────────────
// With the scanner off the service lists only saved networks (probed:
// 3 of 7). `scanning` is bound by the panel, so NetworkManager scans
// while the list is on screen and stops when it is not. That is the
// line Network.qml draws for the glyph -- never scan because something
// changed -- met from the other side: scan because someone is looking.
//
// ── AND THE LIST FROM LAST TIME IS SHOWN WHILE IT DOES ──────────
// The service shows whatever NetworkManager still holds from its last
// scan, and NetworkManager lets that go: measured 2026-09-15, 9 networks
// straight after a scan, 6 at 60 s, only the connected one from ~315 s.
// So a panel opened five minutes after the last one was empty for the
// whole 3-8 s scan. `remembered` is the list as it stood when the panel
// last closed; while the opening scan runs (`stale`) the panel draws it
// under the live rows, and when the scan lands anything it did not find
// goes. The user's pick over a background scan every few minutes, which
// would keep NetworkManager's own cache warm at the price of the radio
// leaving its channel with nobody looking (Datum Panels, build pass 4).
// In memory only: the first open after login still waits.
//
// ── WHAT IS NOT IN THE SERVICE, AND IS READ ONCE ────────────────
// The band and the IPv4 address. Neither changes while a connection
// stands, so they are read when the connection changes and when the
// panel opens -- a one-shot, not a watcher. The only repeat is while a
// new connection has no address yet: every 3 s until DHCP answers, then
// never again. Both come from nmcli, which ships with NetworkManager
// everywhere, so the panel needs nothing the service does not already.
//
// There is no download meter any more (removed 2026-09-15, "costing us
// too much"). It was a once-a-second /proc sampler; with it went the
// link rate, `iw` and `ip`. → network.md
// ═══════════════════════════════════════════════════════════════

import Quickshell
import Quickshell.Io
import Quickshell.Networking
import QtQuick

Singleton {
    id: root

    // Bound by the panel. True while the list is on screen.
    property bool scanning: false

    readonly property var device: {
        for (const d of Networking.devices.values)
            if (d.type === DeviceType.Wifi) return d;
        return null;
    }

    readonly property bool radioOn: Networking.wifiEnabled

    // Every network the service knows about, hidden SSIDs dropped: a
    // row with no name is a row nobody can choose.
    readonly property var nets: device
        ? device.networks.values.filter(n => n.name !== "")
        : []

    readonly property var active: {
        for (const n of nets)
            if (n.connected) return n;
        return null;
    }

    Binding {
        when: root.device !== null
        target: root.device
        property: "scannerEnabled"
        value: root.scanning
    }

    function setRadio(on) { Networking.wifiEnabled = on; }

    // Stops whatever the device is doing, a join waiting for its password
    // included. NetworkManager then leaves the device alone until someone
    // joins something -- which, from Cancel and from Disconnect, is the
    // point (measured: 30 s after Disconnect, still not rejoined).
    function stop() { if (device) device.disconnect(); }

    // ── RESCAN, AND SAYING WHAT IT DID ──────────────────────────
    // The service has no scan-now call; its scanner is periodic. Rescan
    // used to fire `nmcli device wifi rescan` and forget it, which gave
    // the person pressing it nothing -- and measured, it often did
    // nothing either: that call returns in 50 ms whether or not NM
    // agrees, and straight after a scan NM does not (LastScan did not
    // move). `device wifi list --rescan yes` is the form that WAITS for
    // a real scan to finish -- 7-8 s, measured three times running, with
    // LastScan moving each time -- so its exit is the moment to say what
    // changed.
    //
    // It also runs when the panel opens, so the header can say Scanning…
    // while the list is still filling; what fills it meanwhile is the
    // remembered list (top of this file). `scanBusy` is that wait.
    //
    // `scanResult` is for a scan someone PRESSED for: "" while there is
    // nothing to say, then one short line for a few seconds.
    readonly property bool scanBusy: scanProc.running
    property string scanResult: ""
    property bool scanAsked: false
    property var scanBefore: []

    property var remembered: []    // [{ name, known, security, signalStrength, ghost }]
    property bool stale: false

    Process {
        id: scanProc
        command: ["timeout", "25", "nmcli", "-t", "-f", "SSID", "device", "wifi", "list",
                  "ifname", root.device ? root.device.name : "", "--rescan", "yes"]
        stdout: StdioCollector { id: scanOut }
        onExited: (code) => {
            root.stale = false;
            if (!root.scanAsked) return;
            root.scanAsked = false;
            if (code !== 0) { root.scanResult = "Scan failed"; scanShown.restart(); return; }
            // nmcli -t escapes a colon inside a name as \:, and a hidden
            // network is an empty line -- the panel does not list those.
            const found = scanOut.text.split("\n").map(l => l.replace(/\\:/g, ":")).filter(l => l !== "");
            const fresh = found.filter((n, i) => found.indexOf(n) === i && root.scanBefore.indexOf(n) < 0);
            root.scanResult = fresh.length === 0 ? "Nothing new"
                            : fresh.length === 1 ? "Found 1 new"
                            : "Found " + fresh.length + " new";
            scanShown.restart();
        }
    }
    Timer { id: scanShown; interval: 4000; onTriggered: root.scanResult = "" }

    // `asked` is true for the button, false for the panel opening.
    function rescan(asked) {
        if (!device || !radioOn) return;
        if (asked) {
            scanAsked = true;
            scanResult = "";
            scanShown.stop();
            scanBefore = nets.map(n => n.name);
        }
        if (!scanProc.running) scanProc.running = true;
    }
    onScanningChanged: {
        if (scanning) {
            readFacts();
            rescan(false);
            stale = scanProc.running && remembered.length > 0;   // no radio, no scan, nothing to wait for
        } else {
            // Closed before its scan landed: what is on screen is still the
            // old list plus a partial one, so the old list is kept.
            if (!stale)
                remembered = nets.filter(n => !n.connected).map(n => ({
                    name: n.name, known: n.known, security: n.security,
                    signalStrength: n.signalStrength, ghost: true
                }));
            stale = false;
            scanAsked = false; scanResult = ""; scanShown.stop();
        }
    }

    // ── SECURITY, IN THE WORDS THE ROW USES ─────────────────────
    // "Sae" is what WPA3 is called on the wire and nobody says it.
    function security(n) {
        switch (n.security) {
        case WifiSecurityType.Open:          return "Open";
        case WifiSecurityType.Owe:           return "Open";
        case WifiSecurityType.Sae:           return "WPA3";
        case WifiSecurityType.Wpa3SuiteB192: return "WPA3 Enterprise";
        case WifiSecurityType.Wpa2Psk:       return "WPA2";
        case WifiSecurityType.Wpa2Eap:       return "WPA2 Enterprise";
        case WifiSecurityType.WpaPsk:        return "WPA";
        case WifiSecurityType.WpaEap:        return "WPA Enterprise";
        case WifiSecurityType.StaticWep:
        case WifiSecurityType.DynamicWep:    return "WEP";
        case WifiSecurityType.Leap:          return "LEAP";
        }
        return "";
    }

    // OWE is encrypted but asks for nothing, so it draws no padlock:
    // the padlock means "you will need a key", not "the air is private".
    function locked(n) {
        return n.security !== WifiSecurityType.Open && n.security !== WifiSecurityType.Owe;
    }

    // ── A PASSWORD NETWORKMANAGER WILL ACCEPT ──────────────────
    // Checked BEFORE the join, because a join drops the network you are
    // on first. A WPA/WPA2 key is 8-63 bytes, or exactly 64 hex digits;
    // NetworkManager fails anything else as "no secrets" in ~200 ms --
    // after the disconnect (journal, 2026-09-15: two attempts, the 5G
    // gone both times). Bytes, not characters, is NetworkManager's own
    // count (nm_utils_wpa_psk_valid). WPA3 (SAE) has no length rule, so
    // only an empty key is refused there -- and join() never sends one.
    // A key of the right length can still be wrong; only the access point
    // can say so, and only by trying (~10 s, the handshake's timeout).
    function keyProblem(n, psk) {
        if (n.security !== WifiSecurityType.WpaPsk && n.security !== WifiSecurityType.Wpa2Psk) return "";
        if (/^[0-9a-fA-F]{64}$/.test(psk)) return "";
        const bytes = encodeURIComponent(psk).replace(/%[0-9A-F]{2}/g, "x").length;
        return bytes < 8 ? "Too short. A " + security(n) + " password is at least 8 characters."
             : bytes > 63 ? "Too long. A " + security(n) + " password is at most 63 characters."
             : "";
    }

    // ── THE CONNECTION'S TWO FACTS THE SERVICE DOES NOT CARRY ───────
    property string band: ""
    property string address: ""

    Process {
        id: facts
        // The in-use access point's frequency, a marker line, then the
        // address. The marker is there because either half can be empty --
        // DHCP has not answered yet -- and an unmarked blank line once put
        // the frequency in the address slot ("WPA2 · 5320 MHz", seen live).
        // --rescan no, always: this must never start a scan.
        command: ["sh", "-c",
            "nmcli -t -f IN-USE,FREQ device wifi list ifname \"$1\" --rescan no; echo @addr; " +
            "nmcli -g IP4.ADDRESS device show \"$1\"",
            "sh", root.device ? root.device.name : ""]
        stdout: StdioCollector {
            onStreamFinished: {
                const [scan, addr] = text.split("@addr\n");
                const inUse = (scan || "").split("\n").find(l => l.startsWith("*:"));
                const mhz = inUse ? parseInt(inUse.slice(2)) : NaN;
                // "192.168.8.153/24", and " | " between several.
                root.address = (addr || "").split("\n")[0].split(" | ")[0].split("/")[0];
                root.band = isNaN(mhz) ? ""
                          : mhz < 3000 ? "2.4 GHz"
                          : mhz < 5925 ? "5 GHz"
                          : "6 GHz";
                // Still no address: read again shortly, until DHCP answers.
                if (root.address === "" && root.active) factsAgain.restart();
            }
        }
    }

    function readFacts() {
        if (!active) { band = ""; address = ""; return; }
        if (!facts.running) facts.running = true;
    }

    // The address arrives a moment after `connected` does -- DHCP is
    // not instant -- so there is one more read once it has had time.
    onActiveChanged: { readFacts(); factsAgain.restart(); }
    Timer { id: factsAgain; interval: 3000; onTriggered: root.readFacts() }
}
