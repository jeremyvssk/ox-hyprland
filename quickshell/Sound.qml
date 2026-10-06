pragma Singleton

// ═══════════════════════════════════════════════════════════════
// SOUND — what the Sound PANEL reads and does. The bar glyph is still
// Audio.qml; this is the devices, the levels, the apps, and the verbs.
//
// NATIVE, NOT audio-watch.sh. Quickshell.Services.Pipewire already holds
// every node, its volume and mute, the two defaults, and every playing
// stream, pushed. So the panel binds it, and eww's whole chain -- pactl
// subscribe, four defpolls, a fifo, a python peak reader -- has nothing
// left to do for it. What the service does NOT have is shelled out, once,
// only when pressed:
//
//   * CARD PROFILES. There is no card object in 0.3.1. Whether a headset
//     is on call quality IS readable natively -- the sink node carries
//     `api.bluez5.profile` -- but putting it back takes `pactl
//     set-card-profile`, and choosing which A2DP profile takes `pactl
//     list cards` (the best available codec, not a hardcoded name; this
//     JBL offers AAC, SBC and SBC-XQ). → audio.md, High quality
//   * THE TEST TONE. pw-play, for as long as the tone is.
//   * OPENING THE MIC. PwNodePeakMonitor is PASSIVE: probed 2026-09-16, it
//     read 0.0000 for 4 s on the JBL's mic with nothing capturing, and
//     0.05-0.07 of room noise the moment a pw-record held the source. So
//     the input Test runs a capture into /dev/null for 6 s and the monitor
//     draws it. That capture is what drops the JBL to call quality --
//     reproduced the same day: a2dp-sink before, headset-head-unit during.
//     AFTER is not what audio.md measured in 2026-09: WirePlumber 1.6.8
//     now switches back by itself when the capture closes. The row's
//     button is for the case that remains -- a card left on call quality
//     with nothing holding the mic, measured stuck for 8 s and put back by
//     one press in 1.5 s.
//   * RESTART. systemctl, like eww's pill.
//
// Every child process runs behind `setpriv --pdeathsig TERM`: Quickshell
// 0.3.1 does not kill a Process when it exits (architecture.md), and a
// capture outliving the shell would hold the headset on call quality.
// ═══════════════════════════════════════════════════════════════

import Quickshell
import Quickshell.Io
import Quickshell.Services.Pipewire
import QtQuick

Singleton {
    id: root

    // ── WHAT IS THERE ────────────────────────────────────────
    // By node type, which comes from the registry and needs no tracking.
    // Filters and wireplumber's internal capture streams are other types
    // (Untracked), so the lists are the devices a person would pick.
    //
    // SORTED BY NODE ID. `Pipewire.nodes` has no order of its own: between
    // two opens on 2026-09-16 HDMI moved above Speakers, and a list that
    // reorders under the pointer delivers the click to a neighbour (Wi-Fi's
    // rule, THE LIST DOES NOT RE-SORT UNDER YOU). Ids only grow, so a
    // device that is plugged in or re-created (a profile switch) goes last.
    readonly property var nodes: Pipewire.nodes.values.slice().sort((a, b) => a.id - b.id)
    readonly property var sinks: nodes.filter(n => n.type === PwNodeType.AudioSink)
    readonly property var sources: nodes.filter(n => n.type === PwNodeType.AudioSource)
    readonly property var streams: nodes.filter(n => n.type === PwNodeType.AudioOutStream)

    readonly property PwNode sink: Pipewire.defaultAudioSink
    readonly property PwNode source: Pipewire.defaultAudioSource

    // Bound by the panel: properties are live only while tracked, and only
    // while someone is looking (Audio.qml tracks the default sink always,
    // for the bar's glyph).
    property bool watching: false
    PwObjectTracker { objects: root.watching ? root.sinks.concat(root.sources, root.streams) : [] }

    function isDefault(n) {
        return n !== null && ((root.sink !== null && n.id === root.sink.id)
                              || (root.source !== null && n.id === root.source.id));
    }

    function makeDefault(n) {
        if (n.type === PwNodeType.AudioSink) Pipewire.preferredDefaultAudioSink = n;
        else if (n.type === PwNodeType.AudioSource) Pipewire.preferredDefaultAudioSource = n;
    }

    // ── NAMES ────────────────────────────────────────────────
    // SHORT, the user's pick: "TU106 High Definition Audio Controller
    // Digital Surround 7.1 (HDMI)" is HDMI. A Bluetooth device's own name
    // is already short and is the one thing that tells two headsets apart.
    // The analog jack is Speakers: the node does not say which port is in
    // use, and on this machine it is the laptop's speakers.
    function bluez(n) { return n.name.startsWith("bluez_"); }

    function label(n) {
        if (bluez(n)) return n.description;
        if (/hdmi|displayport/i.test(n.name)) return "HDMI";
        if (/analog/.test(n.name)) return n.type === PwNodeType.AudioSource ? "Microphone" : "Speakers";
        return n.description || n.nickname || n.name;
    }

    function icon(n) {
        if (n.type === PwNodeType.AudioSource) return "mic-fill";
        if (bluez(n)) return "headphones-fill";
        if (/hdmi|displayport/i.test(n.name)) return "tv-fill";
        return "speaker-fill";
    }

    function appName(s) {
        const p = s.properties || {};
        return p["application.name"] || s.description || s.name;
    }

    // A browser is a globe, anything else a note. Two drawings, not an icon
    // theme: the row's name already says which app it is.
    function appIcon(s) {
        return /firefox|brave|chrom|librewolf|zen|vivaldi|opera/i.test(appName(s)) ? "globe" : "note-fill";
    }

    // ── LEVELS ───────────────────────────────────────────────
    // Stops at 100 %, the user's pick. A level already above it (set
    // elsewhere) reads as what it is and is only clamped when moved.
    function level(n) { return n && n.audio ? n.audio.volume : 0; }
    function muted(n) { return !n || !n.audio || n.audio.muted; }

    // MOVING A LEVEL UNMUTES IT. A slider you drag and hear nothing from
    // reads as broken.
    function setLevel(n, v) {
        if (!n || !n.audio) return;
        n.audio.volume = Math.max(0, Math.min(1, v));
        if (n.audio.muted) n.audio.muted = false;
    }
    function toggleMute(n) { if (n && n.audio) n.audio.muted = !n.audio.muted; }

    // ── CALL QUALITY ─────────────────────────────────────────
    // A Bluetooth sink on HSP/HFP: 16 kHz mono for everything you hear.
    function callQuality(n) {
        const p = n && n.properties ? n.properties : {};
        return bluez(n) && String(p["api.bluez5.profile"] || "").startsWith("headset-head-unit");
    }

    // bluez_output.88_92_CC_5A_71_CA.1 -> bluez_card.88_92_CC_5A_71_CA
    function cardOf(n) {
        const p = n.properties || {};
        return p["device.name"] || ("bluez_card." + n.name.replace(/^bluez_(output|input)\./, "").replace(/\.\d+$/, ""));
    }

    // Asked for from the row. The test is stopped first: the capture is
    // what holds the headset on call quality, and switching under it would
    // only be switched back.
    property string hqCard: ""
    function highQuality(n) {
        stopMicTest();
        hqCard = cardOf(n);
        cards.running = true;
    }
    Process {
        id: cards
        command: ["setpriv", "--pdeathsig", "TERM", "pactl", "-f", "json", "list", "cards"]
        stdout: StdioCollector {
            onStreamFinished: {
                let best = "", pri = -1;
                try {
                    for (const c of JSON.parse(text)) {
                        if (c.name !== root.hqCard) continue;
                        for (const k in c.profiles) {
                            const p = c.profiles[k];
                            if (k.startsWith("a2dp-sink") && p.available && p.priority > pri) { best = k; pri = p.priority; }
                        }
                    }
                } catch (e) {}
                if (best !== "") {
                    Quickshell.execDetached(["pactl", "set-card-profile", root.hqCard, best]);
                    return;
                }
                // NO A2DP PROFILE AT ALL. Measured 2026-09-16 straight after
                // Restart: the card came back on headset-head-unit offering
                // only the two HSP profiles, because BlueZ's A2DP endpoints
                // were not re-registered, so there was nothing to switch to
                // and the press did nothing. Reconnecting the headset brings
                // all three back and lands on a2dp-sink by itself (~4 s), so
                // that is what the press does then. The row goes while it
                // reconnects and returns without the note.
                const mac = root.hqCard.replace(/^bluez_card\./, "").replace(/_/g, ":");
                Quickshell.execDetached(["sh", "-c", "bluetoothctl disconnect \"$1\" >/dev/null; sleep 2; bluetoothctl connect \"$1\" >/dev/null", "sh", mac]);
            }
        }
    }

    // ── THE OUTPUT TEST ──────────────────────────────────────
    // No --target: the default sink is by definition the mint row.
    readonly property bool toneRunning: tone.running
    function testTone() { tone.running = true; }
    function stopTone() { tone.running = false; }
    Process {
        id: tone
        command: ["setpriv", "--pdeathsig", "TERM", "pw-play", "/usr/share/sounds/freedesktop/stereo/audio-test-signal.oga"]
    }

    // ── THE INPUT TEST ───────────────────────────────────────
    // Six seconds, eww's length. Stop ends it. A capture that dies on its
    // own with an error captured nothing -- no source, or it went away --
    // and says "No input" for 2.5 s, because with no bar drawn at rest a
    // silent failure looks exactly like a press that did not register.
    readonly property bool micTesting: cap.running
    property bool noInput: false
    property bool stopping: false
    function micTest() { noInput = false; stopping = false; cap.running = true; }
    function stopMicTest() { if (cap.running) { stopping = true; cap.running = false; } }
    Process {
        id: cap
        command: ["setpriv", "--pdeathsig", "TERM", "timeout", "6",
                  "pw-record", "--rate", "8000", "--channels", "1", "/dev/null"]
        onExited: (code, status) => {
            if (!root.stopping && code !== 0 && code !== 124) { root.noInput = true; noInputClear.restart(); }
            root.stopping = false;
        }
    }
    Timer { id: noInputClear; interval: 2500; onTriggered: root.noInput = false }

    // The level, 0-100, on eww's window: -55 dBFS to 0, fast attack and
    // 7 units of release a tick. THE MONITOR'S PEAK IS A CUBE ROOT, not
    // the sample: Quickshell's peak.cpp takes max |sample| and returns
    // std::cbrt of it. Read as linear, this room's 0.065 was -24 dBFS and
    // the meter sat at half with nobody speaking; cubed it is -71 dBFS,
    // which is eww's "ambient reads 0". So dBFS is 60·log10(peak).
    PwNodePeakMonitor {
        id: peakMon
        node: root.source
        enabled: cap.running
    }
    property real micLevel: 0
    Timer {
        interval: 50
        repeat: true
        running: cap.running || root.micLevel > 0
        onTriggered: {
            const p = cap.running ? peakMon.peak : 0;
            const t = p > 0 ? Math.max(0, Math.min(100, (60 * Math.log10(p) + 55) / 55 * 100)) : 0;
            root.micLevel = t > root.micLevel ? t : Math.max(t, root.micLevel - 7);
        }
    }

    // ── RESTART ──────────────────────────────────────────────
    // Tears down every stream, so the panel asks first. `restarting`
    // holds until PipeWire has gone away and come back -- or 8 s, so a
    // restart the service never notices cannot leave the button dead.
    property bool restarting: false
    property bool sawDown: false
    function restart() {
        stopTone(); stopMicTest();
        restarting = true; sawDown = false;
        restartGuard.restart();
        Quickshell.execDetached(["systemctl", "--user", "restart", "wireplumber", "pipewire", "pipewire-pulse"]);
    }
    Connections {
        target: Pipewire
        function onReadyChanged() {
            if (!Pipewire.ready) root.sawDown = true;
            else if (root.restarting && root.sawDown) root.restarting = false;
        }
    }
    Timer { id: restartGuard; interval: 8000; onTriggered: root.restarting = false }
}
