// ═══════════════════════════════════════════════════════════════
// MOD — one module button. An icon, and the thing it opens.
//
// HOVER IS COLOUR ONLY, and it is the live bar's own law rather than
// a taste: hover is transient, so it is the one thing allowed to
// reach full ink without breaking the brightness law that keeps the
// rest of the row quiet. The alternative -- a box behind the glyph --
// is a second rectangle on a surface whose whole idea is one
// rectangle, and on 100+/day targets it is motion you cannot switch
// off. → design-system.md, and the motion skill's first gate.
//
// NOTHING HERE MOVES. Not on hover, not on press. A module is a
// 26 px target you hit tens of times a day, which the gate puts in
// the "near-imperceptible or nothing" tier, and 620 px of bar full
// of things that each twitch when the pointer crosses them is the
// failure mode that tier exists to prevent.
//
// PRESS FIRES ON PRESS, NOT ON RELEASE -- the instant the button goes
// down, which is what every other control on this desktop does.
// ═══════════════════════════════════════════════════════════════

import QtQuick

MouseArea {
    id: root

    property string icon: "x"
    property string tip: ""
    // The script this runs. It is one of the five eww toggles, because
    // day 2 ports NO popups: each module reads a real value and, when
    // clicked, runs the script waybar already runs. → Actions.qml
    property string script: ""
    property string dir: Actions.scripts

    // 15 px of glyph in a 26 px button, which is the set's own
    // reference size -- these were drawn on a 16 px grid to be read
    // at 15. → Icons.qml
    property real glyph: 15
    property int padLeft: 7
    property int padRight: 7

    implicitWidth: padLeft + glyphItem.implicitWidth + padRight
    implicitHeight: 26

    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    onPressed: if (script !== "") Actions.run(script, dir)

    Icon {
        id: glyphItem
        name: root.icon
        size: root.glyph
        x: root.padLeft
        anchors.verticalCenter: parent.verticalCenter
        color: root.containsMouse ? Theme.textPrimary : Theme.textDim
        Behavior on color {
            enabled: Anim.enabled
            ColorAnimation { duration: Anim.ms(Anim.hover) }
        }
    }
}
