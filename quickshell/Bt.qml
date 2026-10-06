pragma Singleton

// ═══════════════════════════════════════════════════════════════
// BT — Bluetooth, for the bar's glyph and the Bluetooth PANEL.
//
// NATIVE, NOT bt-snapshot.sh. Quickshell 0.3.1 ships BlueZ as
// `Quickshell.Bluetooth` (beside Services/, like Networking). Probed live
// 2026-09-16: the adapter, its power and discovery, and per device the
// name, BlueZ's icon, paired / bonded / trusted / connected and the
// battery -- all pushed by BlueZ's own signals. So the glyph and the
// list bind it, and the gdbus subscription, bt-snapshot.sh's JSON and
// bt-watch.sh have nothing left to do here.
//
// Why "the bus did not answer" can no longer be drawn as "there is no
// adapter" (bluetooth.md's old bug): the module never parses a whole
// tree at once, so one advertising device cannot blank the reading.
//
// ── WHAT THE MODULE CANNOT DO, AND bt-agent.py DOES ─────────────
// It has no pairing agent, and pair() / connect() report failure only to
// the log (src/bluetooth/device.cpp). So Pair, Connect, Disconnect and
// CancelPairing go through bt-agent.py, which is an Agent1 and says what
// happened, error names included. Power, discovery, trust and forget
// stay native. The agent runs only while the panel wants it (`agentOn`),
// behind `setpriv --pdeathsig TERM` like every child of this shell.
//
// ── ONE SCAN, OURS, AND IT ENDS ─────────────────────────────────
// Discovery is started only by the Scan button and stops by itself after
// 15 s (bluetooth.md: a scan running while a headset connects makes the
// link drop and come back). `scanning` is OUR scan, not the adapter's
// `discovering`: another program's discovery would otherwise make the
// button say Stop and do nothing when pressed -- BlueZ only lets a
// client stop its own.
// ═══════════════════════════════════════════════════════════════

import Quickshell
import Quickshell.Io
import Quickshell.Bluetooth
import QtQuick

Singleton {
    id: root

    // Null until BlueZ has answered, and on a machine with no adapter.
    // The first probe of the module read null 1.5 s after start once and
    // the adapter 5 ms after start the next time: null means "not known",
    // and nothing here announces an absence from it.
    readonly property var adapter: Bluetooth.defaultAdapter
    readonly property bool on: adapter !== null && adapter.enabled
    readonly property bool blocked: adapter !== null && adapter.state === BluetoothAdapterState.Blocked
    readonly property var devices: adapter ? adapter.devices.values : []

    // ── THE BAR'S GLYPH ──────────────────────────────────────
    // Three discrete facts, not bands of one quantity: off (or no
    // adapter -- the same answer to the bar's one question), on, and on
    // with something connected. → Icons.qml bt / bt-off / bt-conn
    readonly property int connectedCount: devices.filter(d => d.connected).length
    readonly property string icon: !on ? "bt-off" : connectedCount > 0 ? "bt-conn" : "bt"

    // ── THE LISTS ────────────────────────────────────────────
    // Yours: anything paired, bonded, trusted or connected. Sorted by name
    // so the order is the same every time the panel opens -- the module's
    // own order is a hash's, and differs between runs.
    readonly property var mine: devices.filter(d => d.paired || d.bonded || d.trusted || d.connected)
        .sort((a, b) => a.name.localeCompare(b.name) || a.address.localeCompare(b.address))
    // Nearby: found by a scan, not yours, and named. A device that never
    // advertised a name shows its address as its alias, and a row that
    // reads "5C-A4-90-10-BA-11" is a row nobody can choose. In the order
    // BlueZ found them, so a new one arrives at the bottom and nothing
    // already on screen moves.
    readonly property var nearby: devices.filter(d => !(d.paired || d.bonded || d.trusted || d.connected) && d.deviceName !== "")

    // BlueZ's icon names (freedesktop's) to our drawings. Unknown kinds,
    // and devices that report none, get the Bluetooth rune.
    function kindIcon(d) {
        const i = d ? d.icon : "";
        if (i === "audio-headset") return "headset-fill";
        if (i === "audio-headphones") return "headphones-fill";
        if (i === "audio-card" || i === "audio-speakers") return "speaker-fill";
        if (i.startsWith("input-keyboard")) return "keyboard-fill";
        if (i === "input-mouse" || i === "input-tablet") return "mouse-fill";
        if (i === "input-gaming") return "gamepad-fill";
        if (i === "phone") return "phone-fill";
        if (i === "computer") return "laptop-fill";
        if (i === "video-display" || i === "tv") return "tv-fill";
        return "bt";
    }

    function byAddress(a) {
        for (const d of devices) if (d.address === a) return d;
        return null;
    }

    // ── POWER ────────────────────────────────────────────────
    // rfkill's soft block is the one "off" the adapter cannot undo from
    // its own Powered property, so it is lifted first. `rfkill` is
    // util-linux; the seat's user may write /dev/rfkill (udev uaccess),
    // and where they may not, the panel's reconcile puts the switch back.
    // `unblocking` lives only until the block lifts, or 5 s: a wish left
    // standing would turn the radio back on the next time anything else
    // turned it off.
    property bool unblocking: false
    function setPower(want) {
        if (!adapter) return;
        unblocking = want && blocked;
        if (unblocking) {
            Quickshell.execDetached(["rfkill", "unblock", "bluetooth"]);
            unblockEnd.restart();
        } else {
            adapter.enabled = want;
        }
    }
    Timer { id: unblockEnd; interval: 5000; onTriggered: root.unblocking = false }
    Connections {
        target: root.adapter
        function onStateChanged() {
            if (!root.unblocking || root.blocked) return;
            root.unblocking = false;
            if (!root.adapter.enabled) root.adapter.enabled = true;
        }
    }

    // ── SCAN ─────────────────────────────────────────────────
    property bool scanning: false
    function scan(want) {
        if (!adapter) return;
        const was = scanning;
        scanning = want && on;
        // Only ever start or stop our own: stopping when we never started
        // would be a StopDiscovery aimed at somebody else's scan.
        if (scanning !== was) adapter.discovering = scanning;
        if (scanning) scanEnd.restart(); else scanEnd.stop();
    }
    Timer { id: scanEnd; interval: 15000; onTriggered: root.scan(false) }
    onOnChanged: {
        if (!on) { scanning = false; scanEnd.stop(); relinkTry.stop(); return; }
        if (relink.length > 0) { relinkTry.left = 8; relinkTry.start(); }
    }

    // ── COMING BACK ON ───────────────────────────────────────
    // Measured 2026-09-17, JBL Tune 770NC: radio off then on, the headset
    // came back by itself in ~25 s once and not within 60 s the next time --
    // nothing on this side asked. So whatever was connected when the radio
    // went off is asked for again. Remembered only while the adapter is
    // plainly Enabled: BlueZ says "on-disabling" BEFORE it drops the links
    // (dbus-monitor), so a power-off never empties the list it needs.
    // Native connect(): no agent needed, and it puts the device in
    // Connecting, which the panel's row shows. A Connect sent 0.3 s after
    // power-on failed once with a page timeout, so it retries -- every 4 s,
    // 8 times -- and a device that never answers is not asked for next time.
    property var relink: []
    readonly property var linked: devices.filter(d => d.connected).map(d => d.address)
    onLinkedChanged: if (!relinkTry.running && adapter && adapter.state === BluetoothAdapterState.Enabled) relink = linked
    Timer {
        id: relinkTry
        property int left: 0
        interval: 4000
        repeat: true
        triggeredOnStart: true
        onTriggered: {
            const want = root.relink.map(a => root.byAddress(a)).filter(d => d && !d.connected);
            if (want.length === 0 || left-- <= 0) { stop(); root.relink = root.linked; return; }
            for (const d of want)
                if (d.state !== BluetoothDeviceState.Connecting) d.connect();
        }
    }

    // ── THE AGENT ────────────────────────────────────────────
    // Lines for bt-agent.py queue until it has started; `event` carries
    // what it says, with the device's address added so the panel can key
    // its state by something that survives a row being re-created.
    signal event(var e)
    property bool agentOn: false
    property var queue: []

    function send(line) {
        agentOn = true;
        if (agent.running) agent.write(line + "\n");
        else queue = queue.concat([line]);
    }
    function pair(d)        { scan(false); send("pair " + d.dbusPath); }
    function link(d)        { scan(false); send("connect " + d.dbusPath); }
    // A device let go of by hand is not asked for again when the radio returns.
    function unlink(d)      { relink = relink.filter(a => a !== d.address); send("disconnect " + d.dbusPath); }
    function cancelPair(d)  { send("cancelpair " + d.dbusPath); }
    function answer(line)   { send(line); }

    // Everything in flight goes with it: the panel closing ends a pairing,
    // because the question it would ask has nowhere to be shown. BlueZ
    // cancels the pairing itself when the agent's connection closes.
    function release() {
        scan(false);
        queue = [];
        agentOn = false;
    }

    Process {
        id: agent
        command: ["setpriv", "--pdeathsig", "TERM", "--", "python3", Quickshell.shellDir + "/bt-agent.py"]
        running: root.agentOn
        stdinEnabled: true
        onStarted: {
            for (const l of root.queue) agent.write(l + "\n");
            root.queue = [];
        }
        stdout: SplitParser {
            onRead: line => {
                let e;
                try { e = JSON.parse(line); } catch (err) { return; }
                if (e.path) {
                    const d = root.devices.find(x => x.dbusPath === e.path);
                    e.address = d ? d.address : "";
                }
                root.event(e);
            }
        }
        // Died, or could not start (no python3): whatever it was carrying
        // will never be answered, and the panel must not wait on it.
        onExited: code => {
            root.agentOn = false;
            root.event({ ev: "gone", code: code });
        }
    }
}
