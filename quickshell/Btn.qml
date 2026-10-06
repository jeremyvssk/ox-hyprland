// ═══════════════════════════════════════════════════════════════
// BTN — the panels' one button kit. Every panel uses this file, so
// "every button matches" (2026-09-15) is one definition, not a promise.
//
// A button is the size of its word. The LOOK is Text (Datum Panels,
// Bluetooth round two dock, 2026-09-18, "Text, everywhere"): a button is
// its word until the pointer is on it, and only Join is ever filled.
// `kind` is what it is made of:
//   solid   Join. Mint, and the only filled thing in a box.
//   ghost   a word in the ink colour; a 5% white tile under the pointer.
//           `dim` greys the word until then: Scan, Disconnect, Restart.
//   quiet   Forget under Join, Cancel: grey, a 6% tile under the pointer.
//   danger  the Forget / Disconnect / Restart that actually does it: the
//           word in the error colour, its tile tinted with it. No outline.
// Every kind has the mock-up's 6 px corner. A word keeps 7 px each side
// (Text's padding); Join keeps the kit's 16, because a filled button
// with 7 is a blob with a word jammed in it -- the one place this kit
// departs from the mock-up.
// ═══════════════════════════════════════════════════════════════

import QtQuick

Rectangle {
    id: b
    property string label: ""
    property string kind: "ghost"
    property bool dim: false
    property int fontPx: 11
    property int hpad: kind === "solid" ? 16 : 7
    signal clicked()

    implicitWidth: t.implicitWidth + hpad * 2
    implicitHeight: 30
    radius: 6
    // A disabled button does not light up under the pointer: Scanning…
    // did, and a lit button asks to be pressed.
    readonly property bool lit: m.containsMouse && enabled
    color: kind === "solid" ? (lit ? Qt.rgba(124 / 255, 192 / 255, 170 / 255, 1) : Theme.accent)
         : !lit ? Qt.rgba(1, 1, 1, 0)
         : kind === "danger" ? Qt.alpha(Theme.danger, 0.13)
         : kind === "quiet" ? Qt.rgba(1, 1, 1, 0.06)
         : Theme.panelGhost
    scale: m.pressed ? 0.985 : 1

    Behavior on color { enabled: Anim.enabled; ColorAnimation { duration: Anim.ms(Anim.hover) } }
    Behavior on scale { enabled: Anim.enabled; NumberAnimation { duration: Anim.ms(Anim.press) } }

    Text {
        id: t
        anchors.centerIn: parent
        text: b.label
        font.family: Theme.fontMono
        font.pixelSize: b.fontPx
        font.letterSpacing: b.fontPx * 0.05
        font.weight: b.kind === "solid" ? Font.Medium : Font.Normal
        color: b.kind === "solid" ? "#04100E"
             : b.kind === "danger" ? Theme.danger
             : (b.kind === "quiet" || b.dim) ? (b.lit ? Theme.textPrimary : Theme.textDim)
             : Theme.textPrimary
        // 0.6, not 0.4: a disabled button here is one saying what it is
        // busy with (Scanning…, Restarting…), and that word is there to be read.
        opacity: b.enabled ? 1 : 0.6
    }

    MouseArea {
        id: m
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: b.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
        onPressed: b.clicked()      // respond on press, not on release
    }
}
