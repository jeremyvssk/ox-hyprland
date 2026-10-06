// ═══════════════════════════════════════════════════════════════
// THE SOUND PANEL — what the island's body holds for the volume glyph.
//
// 620 x 438 under the bar's 38, the same body the Wi-Fi panel grows
// into, with no background, blur or edge of its own. → WifiPanel.qml
//
// Built from Datum Panels, Sound round two, with the values off the
// user's dock screenshots (2026-09-16) -- every number here was read off
// the mock-up's computed boxes, half pixels of type rounded up:
//   Kit      Track · Flush rows · Plain cursor · ROUNDED hover · Sans + mono · motion on
//   Sliders  per section · Block · light fill · readout always · stop at 100 % · mute on the glyph
//   Devices  short names · call quality on the row
//   Input    Test on the label, glyph + word · mic level during Test · meter under the slider
//   Apps     Playing now while something plays
//   Buttons  ghost, medium
// One copy change on top, by request: the JBL's row says "On call quality"
// and its action is "Switch to high quality" -- what it is on, then what
// pressing does.
//
// ── WHAT MOVES ───────────────────────────────────────────────
// Gated by the motion skill. The body's height is the island's. Inside:
//   the meter's slot   0 <-> 8 px, 180 ms drawer -- it opens when Test
//                      starts and closes when it ends, so the rows under
//                      Input move only when you asked for a test.
//   row hover / cursor colour, 130 ms.
// Nothing else. The slider fills and the meter bar are readouts, and a
// level you are dragging or a volume key you are pressing (hundreds a
// day) must not trail behind itself. The Restart question replaces the
// title in place, as Disconnect's does, without motion.
// ═══════════════════════════════════════════════════════════════

import Quickshell
import Quickshell.Services.Pipewire
import QtQuick

Item {
    id: root

    property bool open: false
    signal closeRequested()

    width: Theme.widthNormal
    height: Theme.panelDepth

    readonly property int pad: 17
    readonly property color txt: Theme.textPrimary
    readonly property color txt2: Theme.textDim
    // The mock-up's outline over the cursor's fill, composited -- see
    // WifiPanel.qml, OUTLINES ON A FILL.
    readonly property color ringOnCursor: Qt.rgba(1, 1, 1, 0.186)

    Binding { target: Sound; property: "watching"; value: root.open }

    property bool askRestart: false
    // "o:<id>", "i:<id>" or "a:<id>" -- a key, not a delegate, because a
    // node can be re-created under the cursor (a profile switch does).
    property string cursor: ""

    onOpenChanged: {
        if (open) {
            root.forceActiveFocus();
        } else {
            askRestart = false;
            cursor = "";
            list.contentY = 0;
            Sound.stopMicTest();
        }
    }

    readonly property var order: Sound.sinks.map(n => "o:" + n.id)
        .concat(Sound.sources.map(n => "i:" + n.id), Sound.streams.map(n => "a:" + n.id))

    // What a row's slider moves: a device row moves the level of its
    // direction's default, an app row its own.
    function nodeFor(key) {
        if (key.startsWith("o:")) return Sound.sink;
        if (key.startsWith("i:")) return Sound.source;
        const id = +key.slice(2);
        return Sound.streams.find(s => s.id === id) || null;
    }
    function deviceFor(key) {
        const id = +key.slice(2);
        return Sound.sinks.concat(Sound.sources).find(n => n.id === id) || null;
    }

    // A test you cannot hear reads as broken hardware, so a muted endpoint
    // says so and the press unmutes; a running test says Stop.
    function testOut() {
        if (Sound.muted(Sound.sink)) Sound.toggleMute(Sound.sink);
        else if (Sound.toneRunning) Sound.stopTone();
        else Sound.testTone();
    }
    function testIn() {
        if (Sound.muted(Sound.source)) Sound.toggleMute(Sound.source);
        else if (Sound.micTesting) Sound.stopMicTest();
        else Sound.micTest();
    }

    // ── THE KEYBOARD ─────────────────────────────────────────
    // ↑↓ move, ←→ the level of the row you are on, Enter makes a device
    // the one in use, Space mutes, Escape backs out: the question, then
    // the panel. Nothing is drawn to teach any of it.
    Keys.onPressed: event => {
        const k = event.key;
        if (k === Qt.Key_Escape) {
            if (askRestart) askRestart = false; else root.closeRequested();
            event.accepted = true;
        } else if ((k === Qt.Key_Down || k === Qt.Key_Up) && order.length > 0) {
            const i = order.indexOf(cursor), d = k === Qt.Key_Down ? 1 : -1;
            cursor = order[i < 0 ? (d > 0 ? 0 : order.length - 1) : Math.max(0, Math.min(order.length - 1, i + d))];
            reveal.restart();
            event.accepted = true;
        } else if (k === Qt.Key_Left || k === Qt.Key_Right) {
            const n = nodeFor(cursor === "" ? "o:" : cursor);
            Sound.setLevel(n, Math.round(Sound.level(n) * 100 + (k === Qt.Key_Right ? 5 : -5)) / 100);
            event.accepted = true;
        } else if ((k === Qt.Key_Return || k === Qt.Key_Enter) && cursor !== "") {
            const n = deviceFor(cursor);
            if (n) Sound.makeDefault(n);
            event.accepted = true;
        } else if (k === Qt.Key_Space) {
            Sound.toggleMute(nodeFor(cursor === "" ? "o:" : cursor));
            event.accepted = true;
        }
    }

    // ═══ THE HEAD ═══════════════════════════════════════════
    Item {
        x: root.pad
        y: 15
        width: root.width - root.pad * 2
        height: 22

        Text {
            visible: !root.askRestart
            anchors.verticalCenter: parent.verticalCenter
            text: "Sound"
            color: root.txt
            font.family: Theme.fontSans
            font.pixelSize: 14
            font.weight: Font.DemiBold
            font.letterSpacing: 0.14
        }

        // The action you take when PipeWire misbehaves -- Rescan's twin.
        // As wide as its longer word, so it does not resize under the
        // pointer when it says Restarting…
        Btn {
            visible: !root.askRestart
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            label: Sound.restarting ? "Restarting…" : "Restart"
            kind: "ghost"
            dim: true
            fontPx: 11
            hpad: 11
            implicitHeight: 22
            implicitWidth: Math.max(104, longest.advanceWidth + hpad * 2)
            enabled: !Sound.restarting
            onClicked: root.askRestart = true
            TextMetrics { id: longest; text: "Restarting…"; font.family: Theme.fontMono; font.pixelSize: 11; font.letterSpacing: 11 * 0.05 }
        }

        // RESTART ASKS ONCE, IN PLACE: it tears down every stream. Cancel
        // last, where Restart was -- buttons act on press, so a double
        // click must land on Cancel, not on the act.
        Text {
            visible: root.askRestart
            anchors.left: parent.left
            anchors.right: goBtn.left
            anchors.rightMargin: 10
            anchors.verticalCenter: parent.verticalCenter
            elide: Text.ElideRight
            text: "Restart audio? Sound stops for a second."
            color: root.txt2
            font.family: Theme.fontSans
            font.pixelSize: 12
        }
        Btn {
            id: goBtn
            visible: root.askRestart
            anchors.right: noBtn.left
            anchors.rightMargin: 12
            anchors.verticalCenter: parent.verticalCenter
            kind: "danger"
            label: "Restart"
            fontPx: 11
            hpad: 11
            implicitHeight: 22
            onClicked: { root.askRestart = false; Sound.restart(); }
        }
        Btn {
            id: noBtn
            visible: root.askRestart
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            kind: "quiet"
            label: "Cancel"
            fontPx: 11
            hpad: 11
            implicitHeight: 22
            onClicked: root.askRestart = false
        }
    }

    // ═══ THE BODY ═══════════════════════════════════════════
    // One scroll with the sections inside it, as Wi-Fi's list is. At
    // three outputs, a mic and an app it does not scroll; a fourth device
    // must not push Playing now out of the panel.
    Flickable {
        id: list
        x: root.pad
        y: 45
        // 8 px wider than the content, so the labels' Test can run its hover
        // box 7 px past the content edge, as the mock-up's does, unclipped.
        width: root.width - root.pad * 2 + 8
        height: root.height - 14 - y
        clip: true
        contentWidth: width
        contentHeight: col.height
        boundsBehavior: Flickable.StopAtBounds
        interactive: contentHeight > height

        Column {
            id: col
            width: list.width - 8
            // The labels' Test runs 5 px above the label's own box.
            topPadding: 5

            // ── OUTPUT ──────────────────────────────────────
            Label {
                text: "Output"
                act: Sound.sink === null ? ""
                   : Sound.muted(Sound.sink) ? "Unmute to test"
                   : Sound.toneRunning ? "Stop" : "Test"
                onActivated: root.testOut()
            }
            Item { width: 1; height: 6 }
            Slider { visible: Sound.sink !== null; node: Sound.sink; glyph: "vol-fill" }
            Repeater {
                model: ScriptModel { values: Sound.sinks }
                delegate: DevRow { keyPrefix: "o:" }
            }
            Empty { visible: Sound.sinks.length === 0; text: "No output device." }

            // ── INPUT ───────────────────────────────────────
            Item { width: 1; height: 13 }
            Label {
                text: "Input"
                act: Sound.source === null ? ""
                   : Sound.muted(Sound.source) ? "Unmute to test"
                   : Sound.micTesting ? "Stop"
                   : Sound.noInput ? "No input" : "Test"
                onActivated: root.testIn()
            }
            Item { width: 1; height: 6 }
            Slider { visible: Sound.source !== null; node: Sound.source; glyph: "mic-fill" }

            // THE SLOT IS 0 UNTIL TEST RUNS. At rest a meter reads as a
            // control you have failed to use (audio.md), so it is not drawn
            // and takes no room; pressing Test slides it open under the
            // slider, and it closes when the test ends.
            Item {
                id: slot
                width: parent.width
                height: Sound.micTesting ? 8 : 0
                clip: true
                visible: height > 0
                Behavior on height {
                    enabled: Anim.enabled
                    NumberAnimation { duration: Anim.ms(Anim.travel); easing.type: Easing.BezierSpline; easing.bezierCurve: Anim.drawer }
                }
                // Under the slider's track, not the row: 39 in, 63 from the end.
                Item {
                    x: 39
                    width: parent.width - 39 - 63
                    height: 4
                    clip: true
                    // The last tenth is the clip zone, painted in the trough so
                    // the meter shows where too loud IS before it gets there.
                    Rectangle { width: parent.width * 0.9; height: 4; color: Qt.rgba(1, 1, 1, 0.10) }
                    Rectangle { x: parent.width * 0.9; width: parent.width * 0.1; height: 4; color: Qt.alpha(Theme.danger, 0.40) }
                    Rectangle { width: parent.width * Sound.micLevel / 100; height: 4; color: Qt.rgba(233 / 255, 238 / 255, 237 / 255, 0.82) }
                }
            }

            Repeater {
                model: ScriptModel { values: Sound.sources }
                delegate: DevRow { keyPrefix: "i:" }
            }
            Empty { visible: Sound.sources.length === 0; text: "No microphone connected." }

            // ── PLAYING NOW ─────────────────────────────────
            // While something plays, the user's pick: an empty section is a
            // heading over nothing.
            Item { width: 1; height: 13; visible: Sound.streams.length > 0 }
            Label { text: "Playing now"; visible: Sound.streams.length > 0 }
            Item { width: 1; height: 6; visible: Sound.streams.length > 0 }
            Repeater {
                model: ScriptModel { values: Sound.streams }
                delegate: AppRow {}
            }
        }
    }

    // The thumb, drawn only when there is something to scroll, in the
    // gutter right of the content -- WifiPanel.qml's, at the same place.
    Rectangle {
        visible: list.contentHeight > list.height + 1
        x: list.x + col.width + 7
        y: list.y + list.visibleArea.yPosition * list.height
        width: 5
        height: Math.max(20, list.visibleArea.heightRatio * list.height)
        radius: 3
        color: Qt.rgba(1, 1, 1, 0.14)
    }

    // The keyboard cursor scrolls into view when the list is taller than
    // the panel; rows already in view do not move.
    Timer {
        id: reveal
        interval: 1
        onTriggered: {
            let item = null;
            for (let i = 0; i < col.children.length; i++)
                if (col.children[i].rowKey === root.cursor) item = col.children[i];
            if (!item || list.contentHeight <= list.height) return;
            let y = list.contentY;
            if (item.y + item.height > y + list.height) y = item.y + item.height - list.height;
            else if (item.y < y) y = item.y;
            list.contentY = Math.max(0, Math.min(y, list.contentHeight - list.height));
        }
    }

    // ═══ PIECES ═════════════════════════════════════════════

    // A section label, and at its right end the section's Test: a glyph
    // and the word, in the label's own capitals. `act` is the word; empty
    // draws nothing (no device, nothing to test).
    component Label: Item {
        id: l
        property alias text: sec.text
        property string act: ""
        signal activated()
        width: parent ? parent.width : 0
        height: 14

        Section {
            id: sec
            width: parent.width
            lineEnd: actBox.visible ? actBox.x - 8 : width
        }
        // 7 px of box past the text on both sides, so the word's ink ends
        // on the content edge and the hover box runs past it.
        WordBtn {
            id: actBox
            visible: l.act !== ""
            x: parent.width + 7 - width
            y: -5
            // "No input" is a result, not a thing to press again.
            enabled: l.act !== "No input"
            glyph: l.act === "Stop" ? "stop-fill" : l.act === "Test" ? "play-fill" : l.act === "No input" ? "" : "vol-fill"
            word.text: l.act
            word.color: !enabled ? Theme.danger : hovered ? root.txt : root.txt2
            word.font.family: Theme.fontCaps
            word.font.pixelSize: Theme.capsPx
            word.font.weight: Theme.capsWeight
            word.font.letterSpacing: Theme.capsTrack
            word.font.capitalization: Font.AllUppercase
            onClicked: l.activated()
        }
    }

    // A word you press, with no tile until the pointer is on it: the
    // labels' Test and the row's Switch to high quality. Smaller than a
    // Btn on purpose -- it lives inside a label line or a row.
    component WordBtn: Rectangle {
        id: w
        property string glyph: ""
        property alias word: wt
        readonly property alias hovered: wm.containsMouse
        signal clicked()
        width: wr.implicitWidth + 14
        height: 24
        radius: 5
        color: wm.containsMouse && enabled ? Qt.rgba(1, 1, 1, 0.06) : Qt.rgba(1, 1, 1, 0)
        Behavior on color { enabled: Anim.enabled; ColorAnimation { duration: Anim.ms(Anim.hover) } }
        Row {
            id: wr
            x: 7
            anchors.verticalCenter: parent.verticalCenter
            spacing: 5
            Icon {
                anchors.verticalCenter: parent.verticalCenter
                visible: w.glyph !== ""
                name: w.glyph === "" ? "x" : w.glyph
                size: 12
                color: wt.color
            }
            Text {
                id: wt
                anchors.verticalCenter: parent.verticalCenter
                font.family: Theme.fontMono
                font.pixelSize: 11
            }
        }
        MouseArea {
            id: wm
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: w.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
            onPressed: w.clicked()
        }
    }

    component Empty: Text {
        width: parent ? parent.width : 0
        height: 36
        leftPadding: 9
        verticalAlignment: Text.AlignVCenter
        color: root.txt2
        font.family: Theme.fontMono
        font.pixelSize: 11
    }

    // A glyph that can be off: the drawing at 35 % and the slash over it at
    // full ink, the set's own off-state rule. → Icons.qml
    component Glyph: Item {
        property string name: "x"
        property bool off: false
        property color color: root.txt2
        property real size: 14
        implicitWidth: size
        implicitHeight: size
        Icon { name: parent.name; size: parent.size; color: parent.color; opacity: parent.off ? 0.35 : 1 }
        Icon { name: "slash"; size: parent.size; color: parent.color; visible: parent.off }
    }

    // ── THE SLIDER — BLOCK ───────────────────────────────────
    // A 20 px bar that fills, no knob. Light fill: mint marks state, and
    // the mint name already says which device is in use. Muted keeps its
    // level -- the fill goes grey and the number says Muted. The glyph is
    // the mute button. `inline` is an app row's: no side padding.
    component Slider: Item {
        id: s
        property var node: null
        property string glyph: "vol-fill"
        property bool inline: false
        readonly property color fill: Qt.rgba(233 / 255, 238 / 255, 237 / 255, 0.82)

        // While the pointer holds the bar the bar shows the pointer, not
        // PipeWire's echo of it, which arrives a round trip later.
        property real dragV: -1
        readonly property real v: dragV >= 0 ? dragV : Sound.level(node)
        readonly property bool muted: dragV < 0 && Sound.muted(node)

        width: parent ? (inline ? parent.width - x : parent.width) : 0
        height: inline ? 24 : 36

        Rectangle {
            id: gb
            x: s.inline ? 0 : 5
            anchors.verticalCenter: parent.verticalCenter
            width: 24
            height: 24
            radius: 6
            color: gm.containsMouse ? Qt.rgba(1, 1, 1, 0.08) : Qt.rgba(1, 1, 1, 0)
            Behavior on color { enabled: Anim.enabled; ColorAnimation { duration: Anim.ms(Anim.hover) } }
            Glyph {
                anchors.centerIn: parent
                name: s.glyph
                off: s.muted
                color: gm.containsMouse ? root.txt : root.txt2
            }
            MouseArea {
                id: gm
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onPressed: Sound.toggleMute(s.node)
            }
        }

        Text {
            id: readout
            x: s.width - 9 - width
            anchors.verticalCenter: parent.verticalCenter
            width: 44
            horizontalAlignment: Text.AlignRight
            text: s.muted ? "Muted" : Math.round(s.v * 100) + "%"
            color: root.txt2
            font.family: Theme.fontMono
            font.pixelSize: 11
        }

        Rectangle {
            id: track
            x: gb.x + 24 + (s.inline ? 8 : 10)
            anchors.verticalCenter: parent.verticalCenter
            width: readout.x - (s.inline ? 8 : 10) - x
            height: 20
            radius: 6
            color: Qt.rgba(1, 1, 1, 0.09)

            // The fill's left corners are the track's; its right edge is cut
            // square, which a Rectangle's own radius cannot draw.
            Item {
                width: track.width * Math.min(1, s.v)
                height: track.height
                clip: true
                Rectangle {
                    width: track.width
                    height: track.height
                    radius: track.radius
                    color: s.muted ? Qt.rgba(1, 1, 1, 0.26) : s.fill
                }
            }

            MouseArea {
                anchors.fill: parent
                anchors.leftMargin: -6
                anchors.rightMargin: -6
                cursorShape: Qt.PointingHandCursor
                preventStealing: true
                function at(mx) { return Math.max(0, Math.min(1, (mx - 6) / track.width)); }
                onPressed: mouse => { s.dragV = at(mouse.x); Sound.setLevel(s.node, s.dragV); }
                onPositionChanged: mouse => { if (pressed) { s.dragV = at(mouse.x); Sound.setLevel(s.node, s.dragV); } }
                onReleased: s.dragV = -1
                onCanceled: s.dragV = -1
                onWheel: wheel => {
                    Sound.setLevel(s.node, Math.round(Sound.level(s.node) * 100 + (wheel.angleDelta.y > 0 ? 5 : -5)) / 100);
                    wheel.accepted = true;
                }
            }
        }
    }

    // A device: its kind, its short name, mint when it is the one in use.
    // One press makes it the one in use; there is nothing to open.
    component DevRow: Rectangle {
        id: r
        required property var modelData
        property string keyPrefix: "o:"
        readonly property string rowKey: keyPrefix + modelData.id
        readonly property bool act: Sound.isDefault(modelData)
        readonly property bool isCursor: root.cursor === rowKey
        readonly property bool call: act && Sound.callQuality(modelData)

        width: parent ? parent.width : 0
        height: 36
        radius: 7
        color: isCursor ? Theme.panelCursor : hit.containsMouse ? Theme.panelHover : Qt.rgba(1, 1, 1, 0)
        border.width: isCursor ? 1 : 0
        border.color: root.ringOnCursor
        Behavior on color { enabled: Anim.enabled; ColorAnimation { duration: Anim.ms(Anim.hover) } }

        MouseArea {
            id: hit
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onPressed: { root.cursor = r.rowKey; Sound.makeDefault(r.modelData); }
        }

        Icon {
            x: 9 + (16 - width) / 2
            anchors.verticalCenter: parent.verticalCenter
            name: Sound.icon(r.modelData)
            size: 15
            color: r.act ? Theme.accent : root.txt2
            Behavior on color { enabled: Anim.enabled; ColorAnimation { duration: Anim.ms(Anim.hover) } }
        }
        Text {
            x: 34
            anchors.verticalCenter: parent.verticalCenter
            width: (r.call ? callRow.x - 12 : r.width - 9) - x
            elide: Text.ElideRight
            text: Sound.label(r.modelData)
            color: r.act ? Theme.accent : root.txt
            font.family: Theme.fontSans
            font.pixelSize: 13
            Behavior on color { enabled: Anim.enabled; ColorAnimation { duration: Anim.ms(Anim.hover) } }
        }

        // CALL QUALITY, ON THE ROW: what it is on, then what pressing does.
        Row {
            id: callRow
            visible: r.call
            anchors.right: parent.right
            anchors.rightMargin: 7
            anchors.verticalCenter: parent.verticalCenter
            spacing: 8
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: "On call quality"
                color: root.txt2
                font.family: Theme.fontMono
                font.pixelSize: 11
            }
            WordBtn {
                anchors.verticalCenter: parent.verticalCenter
                word.text: "Switch to high quality"
                word.color: root.txt
                word.font.letterSpacing: 0.42
                onClicked: Sound.highQuality(r.modelData)
            }
        }
    }

    // An app that is playing: its name, then its own slider. The row is
    // not a button -- the slider is the control.
    component AppRow: Rectangle {
        id: a
        required property var modelData
        readonly property string rowKey: "a:" + modelData.id
        readonly property bool isCursor: root.cursor === rowKey

        width: parent ? parent.width : 0
        height: 36
        radius: 7
        color: isCursor ? Theme.panelCursor : Qt.rgba(1, 1, 1, 0)
        border.width: isCursor ? 1 : 0
        border.color: root.ringOnCursor

        Icon {
            x: 9 + (16 - width) / 2
            anchors.verticalCenter: parent.verticalCenter
            name: Sound.appIcon(a.modelData)
            size: 15
            color: root.txt2
        }
        Text {
            x: 34
            width: 150
            anchors.verticalCenter: parent.verticalCenter
            elide: Text.ElideRight
            text: Sound.appName(a.modelData)
            color: root.txt
            font.family: Theme.fontSans
            font.pixelSize: 13
        }
        Slider {
            x: 193
            anchors.verticalCenter: parent.verticalCenter
            inline: true
            node: a.modelData
            glyph: "vol-fill"
        }
    }
}
