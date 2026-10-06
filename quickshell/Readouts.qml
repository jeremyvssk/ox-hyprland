// ═══════════════════════════════════════════════════════════════
// THE READOUT RUN — three numbers, on the clock's bottom line.
//
// This is the whole of what Full adds, and it adds no surface. The
// run arrives on the line the stacked clock already uses -- the
// clock sets its date on 26.25, these sit on 26.0 -- inside a body
// that stays 38 px tall. So the bar never grows, the exclusive zone
// never becomes a question, and no window is moved or covered. The
// shelf (a 22 px shelf under the row) and the tongue (260 px of
// glass hanging over whatever is underneath) were both retired for
// exactly that, and measured: Inline needs 685 px in 620, Fitted 664
// in 620, Two rows 620 in 620.
//
// ── SYSINFO.SH'S SPACING LAW, PORTED RATHER THAN REINVENTED ──
// The waybar drawer this replaces had three rules, and they are the
// only reason the run reads as one line rather than as three labels
// that happen to be near each other:
//
//     a number sits ONE cell after its label, always, whatever it reads
//     groups are separated by TWO cells, never three
//     ALL the slack is spent at the END of the run
//
// A cell is one advance of the bar's own monospace font, MEASURED
// rather than written down. The drawer's cell was 232/28 = 8.286 px
// at 13 px; copying that number here would be silently wrong the day
// the size or the font changes, and the failure would be a run that
// still draws and no longer lines up. TextMetrics asks the font.
//
// ── WHERE THE SLACK GOES, AND THE MISTAKE IT IS WORTH NOT
//    MAKING TWICE ─────────────────────────────────────────────
// Something has to absorb the difference between `100` and `8`, and
// the only question is where. The obvious answer -- give every
// number a fixed three-cell box of its own -- was built here first,
// and it is wrong for the reason sysinfo.sh writes down at length,
// having shipped it and taken it back out:
//
//     a label and its number are the ONE pair on this readout that
//     has to hold together
//
// Pad each number and the slack lands inside a group. The gap after
// `8` becomes four cells while the gap between groups is two, so the
// group boundary it was supposed to be subordinate to is now the
// SMALLER gap, and the run stops reading as one line. Captured and
// looked at, which is the only way that was ever going to be caught.
//
// So every number sits hard against its label, one cell, always, and
// the groups are two cells apart on every frame. The slack is spent
// OUTSIDE the run, never inside a group.
//
// CENTRED IN ITS BOX, SINCE 2026-09-30. It used to be anchored to the
// box's left edge, spending all the slack at the end -- and at
// 5 / 32 / 100 that is three empty cells, so the run's ink sat 11 px
// left of the dots above it (measured: ink centre 1709, dots 1719).
// A line under the workspace row reads as centred on it or as wrong.
// The price: a number gaining a digit moves the run half a cell, not
// the numbers after it a whole one. Still no animation, so nothing
// the eye is reading slides.
//
// THE BOX IS WHAT MUST NOT CHANGE WIDTH, NOT THE NUMBERS. It is
// centred on the island, so a box that grew by a cell would move the
// whole run half a cell -- which is the re-centring the drawer's own
// CELLS constant exists to prevent, met from the other side. Inside
// it, a number gaining a digit does shift the numbers after it by
// one cell. sysinfo.sh shipped exactly that, and the never-ship rule
// it is weighed against -- "a number the user is reading must not
// travel" -- is about a number ANIMATING into place, which is why
// the run below arrives on opacity and never slides.
//
// ONE THING IS NOT INHERITED: sysinfo.sh clamps CPU and RAM to 99,
// and says why -- 100 would make the readout 29 cells, which means a
// rebuilt frame table for an animation made of monospace spaces.
// There is no frame table here. A pegged CPU reads 100.
//
// ── THE BATTERY IS WATCHED. THE OTHER TWO CANNOT BE ──────────
// UPower pushes, so the battery is a binding and a dead reading
// would be stale rather than blank. CPU and RAM have no bus to
// listen to anywhere and are the shell's only polled numbers --
// that split is Sys.qml's, stated there, and it is the reason the
// battery is not in it.
//
// No MouseArea. This is a readout, not a control: there is nothing
// it could open that the modules it sits between do not already
// open, and a control that names no action is the thing
// design-system.md forbids.
// ═══════════════════════════════════════════════════════════════

import Quickshell.Services.UPower
import QtQuick

Item {
    id: root

    // The bar's own font, and the same one the clock uses -- the two
    // lines are the same type system or they are not two lines of one
    // thing. No glyph here is in the private use area; the icons are
    // drawn as paths.
    readonly property string mono: "JetBrainsMono Nerd Font"

    // ONE CELL, FROM THE FONT ITSELF.
    readonly property real cell: oneCell.advanceWidth

    TextMetrics {
        id: oneCell
        font.family: root.mono
        font.pixelSize: Theme.readoutSize
        text: "0"
    }

    // The widest a number on this run can read. Asked of the font
    // rather than multiplied out, because a monospace font is only
    // monospace until someone points the theme at one that is not.
    TextMetrics {
        id: widest
        font.family: root.mono
        font.pixelSize: Theme.readoutSize
        text: "1".repeat(Theme.readoutDigits)
    }

    readonly property int groups: run.visibleChildren.length

    // ── THE BOX ──────────────────────────────────────────────
    // Counted from the format and nowhere else, which is the rule
    // sysinfo.sh puts its own CELLS constant under:
    //
    //     glyph + one cell + up to three digits     per group
    //     two cells                                 per boundary
    //
    // The glyph's width is its height: Icons.qml draws cpu, ram and
    // bat on a 16 x 16 grid, so Icon's implicitWidth rounds to the
    // size it was given.
    implicitWidth: groups * (Theme.readoutGlyph + cell + widest.advanceWidth)
                   + Math.max(0, groups - 1) * cell * 2
    implicitHeight: run.implicitHeight
    width: implicitWidth
    height: implicitHeight

    Row {
        id: run
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.verticalCenter: parent.verticalCenter

        // Two cells between groups. Never three: three is a 3:1 ratio
        // against the one-cell gap inside a group, which does not read
        // as "three separate things", it reads as three things that
        // have drifted apart.
        spacing: root.cell * 2

        // ── ONE GROUP: a drawn label, one cell, a number ─────
        // The glyph IS the label, so it takes the label's colour --
        // dim against the number's ink. That is the two colours
        // sysinfo.sh wrote as Pango markup because one GTK label
        // cannot hold two; here they are two items, which is cheaper
        // and says the same thing.
        component Group: Row {
            id: grp
            property string glyph: "x"
            property int value: 0

            spacing: root.cell

            Icon {
                name: grp.glyph
                size: Theme.readoutGlyph
                color: Theme.textDim
                anchors.verticalCenter: parent.verticalCenter
            }

            Text {
                text: grp.value
                font.family: root.mono
                font.pixelSize: Theme.readoutSize
                font.features: ({ "tnum": 1 })
                color: Theme.textPrimary
                anchors.verticalCenter: parent.verticalCenter
            }
        }

        Group { glyph: "cpu"; value: Sys.cpu }
        Group { glyph: "ram"; value: Sys.ram }

        // ALL THREE IN PERCENT, which is the reason they can share a
        // run at all. Sys.qml settled RAM the same way and for the
        // same reason: 9.2G was a different unit sitting in a column
        // of percentages, and the eye reads a column before it reads
        // a unit.
        //
        // On a machine with no battery the group is not drawn, the
        // box counts two groups, and the run is still centred. An
        // empty meter reads as a control that has broken; the space
        // is not reserved for a reading that is never coming.
        Group {
            glyph: "bat"
            value: Math.round(UPower.displayDevice.percentage * 100)
            visible: UPower.displayDevice.isLaptopBattery
        }
    }
}
