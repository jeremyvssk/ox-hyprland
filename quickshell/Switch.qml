// ═══════════════════════════════════════════════════════════════
// SWITCH — the panels' one on/off control (Datum Panels: Track). Wi-Fi's
// radio, Bluetooth's radio, and Bluetooth's "Let it connect on its own".
// Pulled out of WifiPanel.qml when Bluetooth needed it twice.
//
// TRACK: the macOS capsule at its real size. The knob travels; the
// mint cross-fades and never grows out from the knob, because the
// accent may change colour and may never travel. Pressed, the knob
// stretches toward where it is going.
// ═══════════════════════════════════════════════════════════════

import QtQuick

Item {
    id: s
    property bool on: false
    signal toggled()
    implicitWidth: 38
    implicitHeight: 22

    Rectangle {
        anchors.fill: parent
        radius: 11
        color: s.on ? Theme.accent : Qt.rgba(1, 1, 1, 0.15)
        Behavior on color {
            enabled: Anim.enabled
            ColorAnimation { duration: Anim.ms(Anim.travel); easing.type: Easing.BezierSpline; easing.bezierCurve: Anim.drawer }
        }
    }
    Rectangle {
        readonly property real w: sm.pressed ? 22 : 18
        width: w
        height: 18
        y: 2
        x: s.on ? s.width - 2 - w : 2
        radius: 9
        color: s.on ? "#06110F" : "#E9EEED"
        Behavior on x {
            enabled: Anim.enabled
            NumberAnimation { duration: Anim.ms(Anim.travel); easing.type: Easing.BezierSpline; easing.bezierCurve: Anim.drawer }
        }
        Behavior on width {
            enabled: Anim.enabled
            NumberAnimation { duration: Anim.ms(Anim.press); easing.type: Easing.BezierSpline; easing.bezierCurve: Anim.easeOut }
        }
        Behavior on color {
            enabled: Anim.enabled
            ColorAnimation { duration: Anim.ms(Anim.travel) }
        }
    }
    MouseArea {
        id: sm
        anchors.fill: parent
        anchors.margins: -4
        cursorShape: Qt.PointingHandCursor
        onPressed: s.toggled()
    }
}
