// ═══════════════════════════════════════════════════════════════
// SCAN ROW — "Scan for new devices", pinned under a panel's list.
//
// Datum Panels, Bluetooth round two, Scan: Pinned to the bottom (the
// user's pick 2026-09-17, and for Wi-Fi 2026-09-18: "the bottom isn't
// empty"). Row-shaped, so it reads as the list's last word rather than as
// a toolbar; pinned, so a scan that finds things grows the list ABOVE it
// and the row never moves under the pointer that is about to press Stop.
//
// 40 tall: a hairline and 3 px of air, then a 36 px row -- the list's own
// row height, with the glyph in the icon column and the words where the
// names start. The panel leaves 4 px above it; that is the mock-up's 44.
//
// While it runs the row is not a button (pressing it again would do
// nothing): it says what it is doing, and `stopLabel` -- when there is
// a way to stop -- is the one thing on it you can press. A Wi-Fi scan
// cannot be stopped, so Wi-Fi passes none.
// ═══════════════════════════════════════════════════════════════

import QtQuick

Item {
    id: s

    property string label: ""
    property string busyLabel: ""
    property string busyGlyph: "bt"
    property bool busy: false
    property string stopLabel: ""
    // A short result at the right after a scan someone pressed for.
    property string note: ""
    property bool noteErr: false
    signal scan()
    signal stop()

    width: parent ? parent.width : 0
    height: 40

    Rectangle { width: s.width; height: 1; color: Theme.glassEdge }

    Rectangle {
        y: 4
        width: s.width
        height: 36
        radius: 7
        color: hit.containsMouse && !s.busy ? Theme.panelHover : Qt.rgba(1, 1, 1, 0)
        Behavior on color { enabled: Anim.enabled; ColorAnimation { duration: Anim.ms(Anim.hover) } }

        readonly property color ink: hit.containsMouse && !s.busy ? Theme.textPrimary : Theme.textDim

        MouseArea {
            id: hit
            anchors.fill: parent
            hoverEnabled: true
            enabled: !s.busy
            cursorShape: Qt.PointingHandCursor
            onPressed: s.scan()
        }

        Icon {
            x: 9 + (16 - width) / 2
            anchors.verticalCenter: parent.verticalCenter
            name: s.busy ? s.busyGlyph : "plus"
            size: 14
            color: parent.ink
        }
        Text {
            x: 34
            anchors.verticalCenter: parent.verticalCenter
            width: (stopBtn.visible ? stopBtn.x : noteText.visible ? noteText.x : parent.width) - 9 - x
            elide: Text.ElideRight
            text: s.busy ? s.busyLabel : s.label
            color: parent.ink
            font.family: Theme.fontSans
            font.pixelSize: 12
        }
        Text {
            id: noteText
            visible: !s.busy && s.note !== ""
            anchors.right: parent.right
            anchors.rightMargin: 9
            anchors.verticalCenter: parent.verticalCenter
            text: s.note
            color: s.noteErr ? Theme.danger : Theme.textDim
            font.family: Theme.fontMono
            font.pixelSize: 11
        }
        // 92 wide, the mock-up's, so a word can change under the pointer
        // without the button changing size.
        Btn {
            id: stopBtn
            visible: s.busy && s.stopLabel !== ""
            anchors.right: parent.right
            anchors.rightMargin: 7
            anchors.verticalCenter: parent.verticalCenter
            label: s.stopLabel
            kind: "ghost"
            dim: true
            fontPx: 11
            hpad: 11
            implicitHeight: 22
            implicitWidth: 92
            onClicked: s.stop()
        }
    }
}
