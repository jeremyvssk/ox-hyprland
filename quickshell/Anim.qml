pragma Singleton

// ═══════════════════════════════════════════════════════════════
// ANIM — the kill switch, the frame budget, and the three curves.
//
// Written on day 1 for one reason: `enabled` is cheap now and
// impossible across forty call sites later. Every duration in this
// shell reads through here, so `Anim.enabled = false` is a real
// setting and not a promise.
//
// The output is 100 Hz. A duration is not a feeling, it is a frame
// count -- 10.0 ms a frame. 220 ms is 22 frames. See
// motion.md §1.
// ═══════════════════════════════════════════════════════════════

import Quickshell

Singleton {
    // Day 4 key: animation speed. false makes every duration 0 and
    // every Behavior a straight assignment -- nothing breaks, the
    // bar just stops moving.
    property bool enabled: true

    // Slow-motion multiplier, for looking at a curve rather than
    // feeling it. 4 is what the rig used. Never ships as anything
    // but 1.
    property real scale: 1.0

    function ms(d) { return enabled ? Math.round(d * scale) : 0 }

    // ── THE CURVES ───────────────────────────────────────────
    // A CSS cubic-bezier(a,b,c,d) is [a, b, c, d, 1, 1] verbatim.
    // Never ease-in on UI: it starts slow at exactly the moment the
    // user is watching.
    readonly property var easeOut: [0.23, 1, 0.32, 1, 1, 1]
    readonly property var easeInOut: [0.77, 0, 0.175, 1, 1, 1]
    readonly property var drawer: [0.32, 0.72, 0, 1, 1, 1]

    // ── DURATIONS ────────────────────────────────────────────
    readonly property int hover: 130         // 13 frames
    readonly property int press: 120         // 12 frames
    readonly property int density: 220       // 22 frames -- see below
    readonly property int panel: 220         // the shutter drop
    readonly property int fade: 90           // 9 frames, content only

    // ── THE PANEL'S INSIDE ───────────────────────────────────
    // `travel` is the drawer curve's short form: the switch knob
    // crossing its track, and an opened row gliding into view. Both are
    // a thing moving a few dozen px to a place you are about to look,
    // which is the 180 end of the drawer range. `swapIn` is the body
    // arriving after the radio flips -- out on `fade`, in on this, the
    // same 90 / 160 pair the Datum Panels mock-up shipped with.
    readonly property int travel: 180        // 18 frames, drawer
    readonly property int swapIn: 160        // 16 frames, easeOut

    // ── THE MAXIMISE RISE, AND WHY IT IS ITS OWN PAIR ────────
    // Normal -> Full. Deliberately NOT `panel`, and deliberately not
    // the drawer curve either. The panel is 220 ms on the drawer
    // curve because a panel is a SURFACE ARRIVING -- it should take
    // its time and settle. This is a 160 px block moving 6 px inside
    // a bar that stays exactly where it was. Borrowing the panel's
    // timing would make a shrug look like an event.
    //
    // The gate puts it there on frequency: maximising is tens of
    // times a day, which is the "near-imperceptible" tier -- short,
    // small, gone before you have decided to look at it. 6 px over
    // 16 frames is 0.38 px a frame, far under the strobe threshold,
    // so it reads as a slide rather than as a step.
    //
    // They are written here rather than reused from `panel` so that
    // nobody later tidies two numbers that mean different things
    // into one.
    readonly property int maximise: 160      // 16 frames, easeOut

    // THE CONTAINER MOVES; THE NUMBER INSIDE IT DOES NOT. The
    // never-ship list's entry is "a number the user is reading must
    // not travel", so the readouts do not slide into place -- they
    // arrive on opacity alone, on the line they will live on, 40 ms
    // after the block has started to move, landing with it.
    //
    // Closing is not the reverse. The numbers leave FIRST, with no
    // delay, so the line empties and then closes rather than closing
    // on top of live text.
    readonly property int readoutIn: 120     // after readoutDelay
    readonly property int readoutDelay: 40
    readonly property int readoutOut: 130

    // ── WHY DENSITY IS 220 AND NOT LONGER ────────────────────
    // The island is centred, so collapsing 620 -> 118 moves each edge
    // 251 px sideways. Measured against the strobe threshold (past
    // ~18 px a frame, dragged text and a 1 px hairline strobe rather
    // than travel):
    //
    //     curve         160ms   220ms   300ms
    //     drawer        63.6    47.1    34.5   px / frame
    //     ease-out      65.1    48.1    35.6
    //     ease-in-out   70.0    53.6    39.7
    //
    // There is NO duration inside the 300 ms ceiling that keeps this
    // travel under the threshold -- the drawer curve needs 590 ms,
    // which is twice the ceiling. So the ceiling is not the thing to
    // move.
    //
    // What the threshold actually governs is CONTENT BEING DRAGGED
    // across a static field. The bar's own edge is exempt for the
    // same reason the panel open is exempt at 82 px/frame: the moving
    // edge IS the object, and an edge sweeping reads as an edge.
    //
    // So the rule this shell follows, and day 2 must not break:
    //
    //     THE GLASS MAY TRAVEL. THE CONTENT MAY NOT.
    //
    // Modules cross-fade out before the collapse and the compact face
    // fades in when it lands. Nothing with a glyph in it ever moves
    // sideways at 47 px a frame. Animate the glass; position modules
    // on x and hold them still while it moves.
    //
    // The keyboard trigger (SUPER+ALT+B) fires the same state
    // change as the corner click, and one state change cannot have
    // two motions. The "keyboard-initiated is a disqualifier" rule is
    // about frequency -- it exists for the launcher at hundreds of
    // opens a day. Density is occasional on either trigger.
}
