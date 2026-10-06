// ═══════════════════════════════════════════════════════════════
// THE WORKSPACE ROW — five persistent cells, dots.
//
// THE ROW IS 160 px ON EVERY FRAME OF EVERY SWITCH, BY CONSTRUCTION.
// Five cells of 32, always, whatever any of them is showing. That is
// not a detail -- it is the entire fix for the switching jank, and the
// jank was never the marker. The old waybar cell was 22 wide with 5 px
// margins and GREW to 32 with 0 margins, tweening min-width,
// margin-left, margin-right and border-radius at once. The arithmetic
// (22+5+5 = 32+0+0) only cancels if all four land on the same frame,
// and they do not have to. Any mismatch left the row a few px off 160,
// which a content-hugging centred island answers by RE-CENTRING, which
// moves the clock you were reading. → waybar-island.md
//
// So: NO HORIZONTAL GEOMETRY MAY EVER JOIN A TRANSITION HERE. The
// rule used to read "no geometry property", and Full is the reason it
// now names an axis: the cell's HEIGHT is animated, 22 -> 20, and it
// is safe for the exact reason the width is not. Width feeds the
// row's own width, which feeds a re-centring; height feeds nothing.
// Nothing downstream of it can move a pixel sideways.
//
// WHY DOTS. Settled: Compact is 118 px wide and has no room for
// digits, and one marker across both faces beats two ideas for one
// concept. What you give up is glancing and reading "4" -- position
// carries the number instead, which works because the five are
// persistent and never reorder.
//
// THE CAPSULE TRAVELS, AND THAT PASSES THE GATE. A workspace switch is
// a 100+/day action, where the rule is "nothing that can move a pixel
// of LAYOUT". This moves no layout: the capsule is one absolutely
// positioned item and the row's width is fixed at 160 by construction,
// so nothing re-centres and nothing else moves. 32 px over 150 ms at
// 100 Hz is 2.1 px a frame -- an order of magnitude under the sideways
// strobe threshold, and it is a solid shape, not text.
// ═══════════════════════════════════════════════════════════════

import Quickshell
import Quickshell.Hyprland
import QtQuick

Item {
    id: root

    readonly property int count: 5

    // ── ONE ROW, TWO SIZES AND A FLAG ────────────────────────
    // Compact draws the same row smaller: 18 x 10 cells with a 4 px
    // dot and a 10 x 4 marker, against 32 x 22 with a 5 px dot and an
    // 18 x 5 marker. That is two sizes of ONE row, not two rows --
    // so it is one flag, and there is still exactly one place where a
    // dot is drawn and one place where the marker is positioned. Both
    // sets of numbers live in Theme, because on day 4 they leave the
    // source together.
    property bool compact: false

    // ── AND ONE REAL, FOR THE THIRD FACE ─────────────────────
    // 0 in Normal, 1 in Full: the cell gives up 2 px of height so the
    // dots can sit on the clock's top line and leave the bottom one
    // for the readouts. It is a real rather than a flag because it is
    // the thing that tweens -- the caller owns the Behavior, because
    // the caller is also lifting this whole row by the same 6 px on
    // the same clock, and one motion cannot have two timers.
    //
    // COMPACT IS NOT ON THIS AXIS. It reads 0 like Normal does, so
    // stepping to or from Compact never starts this animation -- the
    // branches below take the compact numbers whole, and the density
    // collapse stays the cross-fade it already was.
    property real lift: 0

    readonly property int cell:       compact ? Theme.compactCell       : Theme.wsCell
    readonly property real cellHeight: compact
        ? Theme.compactCellHeight
        : Theme.wsCellHeight + (Theme.wsCellHeightFull - Theme.wsCellHeight) * lift
    readonly property int dot:        compact ? Theme.compactDot        : Theme.wsDot
    readonly property int markWidth:  compact ? Theme.compactMarkWidth  : Theme.wsMarkWidth
    readonly property int markHeight: compact ? Theme.compactMarkHeight : Theme.wsMarkHeight

    // The row is exactly as tall as its cells and no taller. It used
    // to be the full 38 and centre its own cells inside that, which
    // is fine while it is the only thing in the centre zone -- and
    // wrong the moment it has to stack above a clock, because a 38 px
    // box cannot sit next to anything in a 38 px bar.
    width: cell * count
    height: cellHeight

    // A live binding is what makes the model populate -- Quickshell's
    // object models are lazy, and reading .values once from
    // Component.onCompleted returns an empty list. Measured: 0
    // workspaces from onCompleted, 1 from a bound property.
    readonly property var live: Hyprland.workspaces.values
    readonly property int focused: Hyprland.focusedWorkspace ? Hyprland.focusedWorkspace.id : 1

    function occupied(id) {
        for (const w of live) if (w.id === id) return true;
        return false;
    }

    // THE TRAVELLING CAPSULE. One item, one transform, and it is the
    // only thing in the row that moves.
    Rectangle {
        id: capsule
        // The clamp is insurance, not arithmetic: a marker wider
        // than its own cell laps over the neighbouring dot and then
        // reads as covering two workspaces. Measured once, at cell
        // 12 with an 18 px marker, which is how it got written down.
        width: Math.min(root.markWidth, root.cell - 2)
        height: root.markHeight
        radius: height / 2
        color: Theme.accent
        y: (root.cellHeight - height) / 2
        x: (root.focused - 1) * root.cell + (root.cell - width) / 2
        visible: root.focused >= 1 && root.focused <= root.count

        Behavior on x {
            enabled: Anim.enabled
            NumberAnimation {
                duration: Anim.ms(150)
                easing.type: Easing.BezierSpline
                easing.bezierCurve: Anim.easeOut
            }
        }
    }

    Repeater {
        model: root.count
        delegate: MouseArea {
            id: cellArea
            required property int index
            readonly property int wsId: index + 1
            readonly property bool isActive: wsId === root.focused

            x: index * root.cell
            y: 0
            width: root.cell
            height: root.cellHeight
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor

            // THE LUA FORM IS NOT OPTIONAL. This compositor's config is
            // Lua, so `dispatch workspace 3` is parsed as a Lua
            // expression, fails to compile, and is dropped -- it
            // reports an error nobody reads and the workspace does not
            // change. Measured against all three spellings; only this
            // one moves.
            onPressed: Hyprland.dispatch("hl.dsp.focus({workspace=" + wsId + "})")

            Rectangle {
                anchors.centerIn: parent
                width: root.dot; height: root.dot; radius: root.dot / 2
                // The active cell's own dot is hidden -- the capsule IS
                // the marker there, and two marks for one state reads
                // as two states.
                opacity: cellArea.isActive ? 0 : 1
                color: cellArea.containsMouse ? Theme.textPrimary
                     : root.occupied(cellArea.wsId) ? "#A7BAB6"
                     : Theme.textDim
                // Colour only. The accent marks state; it may cross-fade
                // and it may never travel, pulse or glow.
                Behavior on color {
                    enabled: Anim.enabled
                    ColorAnimation { duration: Anim.ms(Anim.hover) }
                }
                Behavior on opacity {
                    enabled: Anim.enabled
                    NumberAnimation { duration: Anim.ms(Anim.hover) }
                }
            }
        }
    }
}
