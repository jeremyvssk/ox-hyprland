pragma Singleton

// ═══════════════════════════════════════════════════════════════
// AUDIO — is the default output muted, and how loud is it.
//
// ── WHY THIS IS NOT audio-watch.sh ───────────────────────────
// The plan said reuse the watcher this desktop already runs, and
// that was the right instinct for the right reason: audio.md's whole
// finding is WATCHED, NOT POLLED -- four eww defpolls at 1 s plus the
// bar re-executing once a second, replaced by one `pactl subscribe`
// that pushes, and the panel percentage went from up-to-1000 ms late
// to 76 ms.
//
// This keeps that finding and drops the machinery under it.
// Quickshell speaks to PipeWire directly, so the chain
//
//     pactl subscribe -> shell loop -> eww var -> SIGRTMIN+4 ->
//     waybar re-exec -> wpctl round trip -> parse -> glyph
//
// becomes a property binding. No subscribe, no fifo, no signal, no
// fork, no parse. It is the same push, one process earlier.
//
// audio-watch.sh was retired on 2026-09-16, with eww's Sound panel --
// its last consumers. The panel binds the same service. → Sound.qml
//
// ── THE TRACKER IS NOT OPTIONAL ──────────────────────────────
// PipeWire objects are bound lazily. Read `.audio.muted` off a node
// nothing is tracking and you get whatever it held when it was last
// bound, updated never -- a glyph that is correct at login and wrong
// for the rest of the session. PwObjectTracker is what asks PipeWire
// to keep this node's properties live, and it is the single line
// here that has nothing visible to show for itself. → motion.md's
// rule about instruments: a binding that cannot change looks exactly
// like a value that has not changed.
//
// The default sink is a MOVING TARGET -- plugging in a headset makes
// a new node the default -- so the tracker is bound to the service's
// current answer rather than to a node captured once.
//
// ── WHAT THE BAR ACTUALLY ASKS ───────────────────────────────
// One bit: will sound come out. `muted` answers it, and so does
// having no sink at all, which is why the two collapse here rather
// than at the call site. A machine with no output device and a muted
// one are the same fact to someone glancing at a bar.
//
// NOT the level. waybar draws five glyphs for five volume bands;
// this bar draws two states, for the same reason the workspace row
// draws dots -- one marker for one concept. The level lives in the
// panel the button opens, where there is a slider to put it next to.
// ═══════════════════════════════════════════════════════════════

import Quickshell
import Quickshell.Services.Pipewire

Singleton {
    id: root

    readonly property PwNode sink: Pipewire.defaultAudioSink

    // `ready` is PipeWire's own word for "this node's properties have
    // arrived". Before it, `audio` is null and every reading off it
    // is a guess.
    readonly property bool ready: sink !== null && sink.ready && sink.audio !== null

    readonly property bool muted: !ready || sink.audio.muted

    // There is no `volume` property here on purpose. Nothing on the
    // bar draws a level -- see above -- and a property with no reader
    // is a promise about a panel that has not been ported yet.

    PwObjectTracker { objects: [Pipewire.defaultAudioSink] }
}
