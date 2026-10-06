pragma Singleton

// ═══════════════════════════════════════════════════════════════
// THEME — every value the bar's look is made of, in one place.
//
// Day 4 turns this file into datum.json: ten keys leave the source
// and a theme becomes one file rather than one edit. Nothing here is
// derived at read time for that reason -- a value that is computed
// from another value cannot be set from a config file, so the few
// that ARE derived (the gradient geometry) are computed where they
// are used, not here.
//
// The preset is SMOKED, which is your pick from the decision sheet.
// Ink and Vapour are kept as commented blocks rather than as a
// switch: a preset you cannot see is a preset nobody checks, and
// three live branches in a file this size is how the accent ends up
// meaning two things.
// ═══════════════════════════════════════════════════════════════

import Quickshell
import QtQuick

Singleton {
    // ── GEOMETRY ─────────────────────────────────────────────
    // Screen numbers become fractions on day 5; type numbers stay
    // pixels forever. 38 and 13 and 4 are type numbers -- they
    // describe a glyph at a point size, and a glyph does not get
    // bigger because the monitor did.
    readonly property int islandHeight: 38

    //   normal .... 620   six modules a side with 80 px of slack.
    //                     560 leaves 16 px of clearance in Zones,
    //                     which is one date format from a collision.
    //   compact ... 118   the two things the bar can answer without
    //                     being asked: the time, and where you are.
    readonly property int widthNormal: 620
    readonly property int widthCompact: 118

    // ── THE WORKSPACE ROW, BOTH FACES ────────────────────────
    // The row is `cell * count` wide on every frame, which is the
    // whole fix for the switching jank -- so the cell is a number
    // stated once, per face, and never derived from its contents.
    //   normal .... 5 x 32 = 160 px, 22 tall, 5 px dot, 18 x 5 marker
    //   full ...... the same row, 20 tall
    //   compact ... 5 x 18 =  90 px, 10 tall, 4 px dot, 10 x 4 marker
    readonly property int wsCell: 32
    readonly property int wsCellHeight: 22
    readonly property int wsDot: 5
    readonly property int wsMarkWidth: 18
    readonly property int wsMarkHeight: 5

    // ── THE FULL FACE: THE BLOCK GOES UP, NOTHING GETS TALLER ─
    // Full is Normal with a second line of content in it, not a
    // bigger bar: 620 x 38 either way. The dots lift onto the clock's
    // top line and the readouts land on its bottom one, so the two
    // things read across the bar at the same two heights.
    //
    // THE ENTIRE COST IS THESE TWO NUMBERS. The block's top edge goes
    // 8 -> 2 and the cell gives up 2 px of height, which buys a dot
    // centred on 12 -- the clock's top line -- and leaves the bottom
    // line free. The 5 px dot and the 18 x 5 marker are pixel-
    // identical to Normal, because both are centred IN the cell
    // rather than pinned to a hard-coded y. The click target is
    // 32 x 20 instead of 32 x 22; no module loses any air and nothing
    // is clipped.
    readonly property int wsCellHeightFull: 20
    readonly property int wsTopFull: 2

    // ── THE COMPACT FACE ─────────────────────────────────────
    // Compact is not the Normal row made narrow -- it is a different
    // arrangement of two things, and that is the only reason 118 px
    // is possible: TWO SHORT LINES BEAT ONE LONG ROW. Side by side
    // they do not fit; the stacked clock next to five dots measured
    // 128 px against a 118 px budget and the last dot was cut off by
    // the island's own edge.
    //
    // DOTS ON TOP, CLOCK UNDER THEM -- your call, and the one place
    // this build departs from the doc, which has it the other way
    // round. 90 px of dots leaves 14 px of air a side inside 118.
    readonly property int compactCell: 18
    readonly property int compactCellHeight: 10
    readonly property int compactDot: 4
    readonly property int compactMarkWidth: 10
    readonly property int compactMarkHeight: 4

    // The gap between the two lines, and where the pair starts.
    //
    // WHY IT IS NOT CENTRED. True centre is 4 px from the top (10 of
    // dots, 2 of gap and 17 of time is 29 of content in 38). The bar
    // is flush to the ceiling, so it has no visible top edge -- the
    // screen cuts it -- while the bottom has a ring, a 13 px radius
    // and the darkest stop of the gradient under it. Content centred
    // between one open side and one closed one reads high against the
    // closed one, and you saw that as the dots being pushed at the
    // ceiling. So the pair starts 3 px below true centre, and the
    // whole stack moves rather than one line of it: the two lines are
    // one object and the gap between them is not a variable.
    readonly property int compactGap: 2
    readonly property int compactTop: 7

    // ── THE READOUT LINE ─────────────────────────────────────
    // The bottom line of Full. 26 is where the text's centre sits --
    // the stacked clock puts its date on 26.25, and the two lines
    // have to read across the bar or they are not one row.
    //
    // 12 is the design's 11.5 rounded, for the reason Clock.qml sets
    // out at length: font.pixelSize is an int, and font.pointSize --
    // the real -- is converted through the screen's logical DPI, so
    // it would render a different size on a different machine. The
    // integer is the honest trade.
    //
    // THREE DIGITS IS NOT A FORMAT, IT IS THE WIDEST READING. The
    // run's BOX is counted from it -- glyph, one cell, three digits,
    // per group -- so the box never changes width and the run cannot
    // re-centre. The numbers themselves are not padded; the slack is
    // spent at the end of the run. See Readouts.qml, which has the
    // whole of why.
    readonly property int readoutSize: 12
    readonly property int readoutGlyph: 14
    readonly property int readoutBaseline: 26
    readonly property int readoutDigits: 3

    // ── THE FLARE ────────────────────────────────────────────
    // 4 px, your call: "i want 4 anyways, looks modern, 6 and 10 are
    // overkill and don't look cool."
    //
    // The trade, stated so it can be checked rather than remembered:
    // a concave arc reads about 1.4x its radius, because you see the
    // backdrop cut INTO the shape rather than the shape's corner
    // softened. So 4 reads as about 5.6 against a 13 px body corner.
    // They are not a family. That is a look -- rounded at the foot,
    // nicked at the ceiling -- and it is one number to change if you
    // decide against it.
    //
    // Your other worry -- "maybe it's too small for clicking" -- is
    // not a worry. The FILLET is 4 px; the TARGET is 18 x 15, because
    // the handle reaches 14 px INTO the body past the fillet. The
    // visible curve and the thing you hit were never the same object.
    // See Island.qml, handleWidth.
    readonly property int flare: 4

    // The body's bottom corners. The top two are against the screen
    // edge and are not corners. 13 is the Smoked preset's own radius.
    readonly property int bodyRadius: 13

    // ── GLASS: SMOKED ────────────────────────────────────────
    // "the conservative answer, and the right one if you ever put a
    // white wallpaper on." Blur does part of the legibility work;
    // opacity does the rest.
    readonly property real blurRadius: 34      // px. Ink: 46. Vapour: 62.
    readonly property real saturation: 0.72    // Ink: 0.60. Vapour: 0.50.

    readonly property color glassBase: Qt.rgba(4 / 255, 7 / 255, 7 / 255, 0.50)
    readonly property color glassTop: Qt.rgba(30 / 255, 34 / 255, 34 / 255, 0.26)
    readonly property color glassMid: Qt.rgba(10 / 255, 13 / 255, 13 / 255, 0.30)
    readonly property color glassBot: Qt.rgba(0, 0, 0, 0.56)
    readonly property color glassEdge: Qt.rgba(232 / 255, 240 / 255, 238 / 255, 0.09)
    readonly property color glassInner: Qt.rgba(1, 1, 1, 0.045)

    // ── THE PANEL ────────────────────────────────────────────
    // A panel is the island's own body, grown: the same 620, the same
    // side edges and bottom corners, 38 -> 476. This is the part below
    // the bar. It is one number because the only thing that animates
    // is the body's height. → Datum Panels rev 10, §11
    readonly property int panelDepth: 438
    // The calendar is the other panels' depth again since round five
    // (2026-09-30). Round four made it 600 so a month day held four
    // notes, because the month was where you read them; round five gave
    // reading and writing to the day page, and the user picked 438 --
    // "like the others". A five-week day is 83 x 70 now, two names
    // before "+ more". Kept as its own name so the one panel that has
    // been different can be again without a hunt.
    readonly property int calendarDepth: panelDepth

    // Sans for names you read (the title, SSIDs), mono for everything
    // that is a figure or a label -- "Sans + mono", the shipped pick.
    // The mock-ups were drawn in Inter, which is not installed here;
    // Adwaita Sans IS Inter, re-spaced for GNOME, so it is the same
    // letterforms rather than a stand-in.
    readonly property string fontSans: "Adwaita Sans"
    readonly property string fontMono: "JetBrainsMono Nerd Font"

    // TRACKED CAPITALS ARE SANS -- CONNECTED, KNOWN NETWORKS, WPA2, and the
    // date under the clock. They were mono, as the mock-up drew them, and
    // at 9-10 px JetBrains Mono has no room for its W: the middle strokes
    // meet in a grey blob ("known networks w looks cooked", 2026-09-13).
    // Rendered side by side on the panel's own ground -- mono at 10 and
    // 11, Medium and SemiBold, Qt and native rendering, DejaVu, Hack,
    // Fira, Adwaita Mono -- only mono at 12 drew a clean W, and 12 is
    // shouting for a label. Adwaita Sans SemiBold was legible at 10.
    // Figures stay mono; so do sentences in mono. Only capitals moved.
    readonly property string fontCaps: fontSans
    readonly property int capsWeight: Font.DemiBold
    readonly property int capsPx: 11
    readonly property real capsTrack: 1

    // Surfaces inside the panel, all white over the glass so they read
    // on any wallpaper the glass reads on.
    readonly property color panelCard: Qt.rgba(1, 1, 1, 0.035)    // the card, an open row's box
    readonly property color panelHover: Qt.rgba(1, 1, 1, 0.055)   // a row under the pointer
    readonly property color panelCursor: Qt.rgba(1, 1, 1, 0.085)  // a row under the keyboard
    readonly property color panelGhost: Qt.rgba(1, 1, 1, 0.05)    // a ghost button under the pointer
    readonly property color panelWell: Qt.rgba(0, 0, 0, 0.30)     // the password field
    // Forget's colour, and the one error colour. It is not the accent
    // and it never marks state; it marks the thing you cannot undo.
    readonly property color danger: "#E29187"

    // ── INK ──────────────────────────────────────────────────
    readonly property color textPrimary: Qt.rgba(230 / 255, 234 / 255, 233 / 255, 1.0)
    readonly property color textDim: Qt.rgba(141 / 255, 153 / 255, 152 / 255, 1.0)

    // THE ACCENT MARKS STATE AND NOTHING ELSE. It may cross-fade as
    // state changes. It may never travel, pulse, glow or sweep.
    // design-system.md is the source of truth; if this moves, four
    // files move with it.
    readonly property color accent: "#6AB79E"

    // ── THE OUTLINE ──────────────────────────────────────────
    // Your read was "with this outline it actually might look a bit
    // cheaper", and it is a fair one -- 9% white is just under where
    // an edge starts reading as a drawn border. What it buys is that
    // the bar keeps a silhouette when a bright window sits directly
    // behind it. On day 1 it is on, because that is the sheet answer;
    // it is one boolean either way.
    readonly property bool outline: true

    // ── THE TOP EDGE ─────────────────────────────────────────
    // BLEND paints a black ramp down the first 10 px so the bar
    // dissolves upward into the screen edge instead of drawing a
    // hairline that has nothing above it.
    //
    // It is OFF by default here, and the reason is your flare pick:
    // the ramp is 10 px deep and the fillet is 4 px tall, so Blend
    // would bury the entire curve you chose. Turn it on to see the
    // dissolve; you cannot have both at flare 4.
    readonly property bool blendTop: false
}
