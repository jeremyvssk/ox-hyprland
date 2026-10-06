// ═══════════════════════════════════════════════════════════════
// TIME AND DATE — ONE control, stacked.
//
// They open one panel, so two adjacent buttons was two hover targets
// for one action, and it was also two type systems meeting at one
// baseline. Settled.
//
// THE CENTRING BUG THIS FILE EXISTS TO NOT REPEAT: the date carries
// .16em of tracking, and tracking is applied AFTER the last glyph too.
// That hangs a blank cell off the right end, so a centred line is
// pulled left by half of it and the two lines look misaligned even
// though the box is dead centre. The fix is to shift the date right by
// half its own trailing track -- see dateShift. It is not a nudge; it
// is the exact amount that was added.
// ═══════════════════════════════════════════════════════════════

import Quickshell
import QtQuick

MouseArea {
    id: root

    // The bar's own font. Nerd Font is NOT required for anything here
    // -- these are digits and latin letters, no glyphs in the private
    // use area. The icons are drawn as paths, not typed as characters,
    // which is what keeps a stranger's clone from rendering tofu.
    readonly property string mono: "JetBrainsMono Nerd Font"

    // COMPACT DROPS THE DATE, and the constraint is height, not
    // width. The compact face is two stacked lines -- five dots over
    // the time -- inside the same 38 px body: 10 for the dots, 2 of
    // gap and 17 for the time is 29, and a third line costs another
    // 14. There is no room, and a bar that has to shrink its type to
    // fit is a bar that has stopped being readable.
    //
    // Dropping it is also the right answer rather than the cheap one.
    // Compact exists to answer the two things the bar can say without
    // being asked -- what time it is and where you are -- and the
    // date is neither.
    property bool compactMode: false

    // FORCED ROUNDING, and it is worth knowing about. The design doc
    // says 12.5 px and 8.5 px, which are CSS pixels and may be
    // fractional. Qt's font.pixelSize is an INT. The alternative is
    // font.pointSize, which is a real -- but pointSize is converted
    // through the screen's logical DPI, so the bar would render a
    // different size on a machine with a different DPI. That is
    // exactly the class of "works on the machine it was built on" bug
    // day 5 exists to remove, so the integer is the right trade: 13
    // and 9 instead of 12.5 and 8.5.
    //
    // THE DATE IS 10 PX SANS SEMIBOLD, since 2026-09-13. "SUN 13" at 9 px
    // mono broke up on the live glass -- the doc's 8.5 was drawn by a
    // browser, which renders small type heavier than Qt -- and 10 px mono
    // still read as grey mush. Tracked capitals are sans now, everywhere:
    // see fontCaps in Theme.qml. 13 + 2 + 10 still stands inside the 38.
    readonly property int dateSize: 10
    readonly property real dateTracking: 1
    readonly property real dateShift: dateTracking / 2

    implicitWidth: compactMode
                   ? timeText.implicitWidth + 8
                   : Math.max(timeText.implicitWidth, dateText.implicitWidth + dateTracking) + 18

    // In Normal the control is the full height of the bar and its one
    // or two lines sit in the middle of it. In Compact it is a line in
    // a stack, so its box is the line -- and the caller is free to
    // give it a taller box than that, which is what the compact face
    // does: the hit band runs from under the dots to the island's
    // bottom edge, so the target is 20 px tall rather than 13. The
    // text stays where the stack put it because the box grows
    // DOWNWARD from the top anchor below.
    implicitHeight: compactMode ? timeText.implicitHeight : Theme.islandHeight

    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    // The press is the island's: it grows the body into the calendar.

    // One clock, ticking on the minute boundary rather than on a
    // 1000 ms timer that drifts. A bar clock that changes a second
    // late twice an hour is a bar clock nobody trusts.
    property date now: new Date()
    Timer {
        interval: 1000
        running: true
        repeat: true
        onTriggered: root.now = new Date()
    }

    Column {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: root.compactMode ? parent.top : undefined
        anchors.verticalCenter: root.compactMode ? undefined : parent.verticalCenter
        spacing: 2

        Text {
            id: timeText
            anchors.horizontalCenter: parent.horizontalCenter
            text: Qt.formatDateTime(root.now, "HH:mm")
            font.family: root.mono
            font.pixelSize: 13
            font.weight: Font.Medium
            // Tabular figures, so 11:11 and 00:00 are the same width
            // and the module never changes size. A content-hugging
            // centred island re-centres if it does.
            font.features: ({ "tnum": 1 })
            color: Theme.textPrimary
        }

        Text {
            id: dateText
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.horizontalCenterOffset: root.dateShift
            visible: !root.compactMode
            text: Qt.formatDateTime(root.now, "ddd dd").toUpperCase()
            font.family: Theme.fontCaps
            font.weight: Theme.capsWeight
            font.pixelSize: root.dateSize
            font.letterSpacing: root.dateTracking
            color: Theme.textPrimary
            opacity: 0.85
        }
    }

    // HOVER IS COLOUR ONLY, and that is the live bar's own law: hover
    // is transient, so it is the one thing allowed to reach ink
    // without breaking the brightness law.
    opacity: containsMouse ? 1.0 : 0.88
    Behavior on opacity {
        enabled: Anim.enabled
        NumberAnimation { duration: Anim.ms(Anim.hover) }
    }
}
