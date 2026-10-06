// ═══════════════════════════════════════════════════════════════
// A WATCHED READING — one subscription, one reader, no timer.
//
// This is rule 4 of the desktop, as an object: FAST-MOVING READINGS
// ARE WATCHED, NOT POLLED. It exists because two of the bar's glyphs
// were built believing there was no native service to bind: Quickshell
// 0.3.1 ships Pipewire, UPower, Notifications, SystemTray, Mpris, Polkit,
// Pam and Greetd under Services/, and BlueZ and NetworkManager are not
// there. THEY ARE ONE DIRECTORY UP -- Quickshell/Bluetooth and
// Quickshell/Networking -- which was missed. Networking was probed
// against the live NetworkManager on 2026-09-13 and the Wi-Fi panel
// binds it (Wifi.qml); Bluetooth was probed on 2026-09-16 and the
// Bluetooth glyph and panel bind it (Bt.qml). What is left here is the
// Network glyph's nmcli reading, and the only question is whether it is
// ASKED on a timer or TOLD by the bus. Told.
//
// ── THE SHAPE ────────────────────────────────────────────────
// Two processes, never one:
//
//   `subscribe`  runs forever and its OUTPUT IS A CLOCK. What a line
//                says does not matter beyond `relevant`; that a line
//                arrived is the whole message. Give it the command you
//                mean -- the kernel leash below is added here, once,
//                rather than remembered at each call site.
//   `reading`    is a one-shot that answers "so what is it now", and
//                it is the only thing that ever produces a value.
//
// Splitting them is what lets the reading stay the SAME reader the
// rest of the desktop uses. It was written for bt-snapshot.sh, then the
// single BlueZ reader by contract, where a bar that parsed the bus itself
// would have been a second definition of the truth. → bluetooth.md
//
// ── WHY A BURST IS NOT A SEQUENCE OF STATES ──────────────────
// Bringing a headset up emits Connected, then ServicesResolved, then a
// pile of per-profile churn -- a dozen signals over about a second,
// most of them describing a half-finished connect. Reading on each one
// draws every intermediate state, which is exactly the "old icon, then
// new, then old again" complaint bt-watch.sh was written to kill.
//
// So a burst is COALESCED: the reading fires once the source has been
// quiet for `settleMs`, from final state. The intermediate frames are
// never drawn at all, rather than drawn and then corrected.
//
// ── AND ONE READ AFTER THAT ──────────────────────────────────
// BlueZ occasionally reports a device connected before its profiles
// are up and settles a moment later, which is a change that arrives
// with no signal after it to notice. `confirmMs` is one extra read
// once the burst is over. It is the same belt-and-braces read
// bt-watch.sh does for the same reason, and it is cheap: both readers
// behind this de-duplicate.
//
// ── A DEAD WATCHER READS AS STALE, NOT BLANK ─────────────────
// If the subscription dies -- bluetoothd restarts, NetworkManager
// restarts, the bus goes away -- the last value STAYS ON THE BAR and
// the subscription is retried. It does not blank, and it does not
// invent a state: "the bus did not answer" and "the answer is off"
// are different facts, and every reader on this desktop that conflated
// them shipped a bug. → bluetooth.md, the "Adapter unavailable" that
// was a JSON dumper. Holding is also what makes the failure legible:
// a frozen reading is a symptom you can recognise, a blank one looks
// like a bar that was always going to be like that.
//
// The consumer decides what is unparseable and simply does not assign
// -- the signal below hands over stdout and nothing else.
// ═══════════════════════════════════════════════════════════════

import Quickshell.Io
import QtQuick

Item {
    id: root

    // The subscription. Must be a command that runs until killed and
    // writes a line when something changes.
    property var subscribe: []

    // The one-shot. Must print the whole state and exit.
    property var reading: []

    // Which subscription lines are worth a read. `null` means all of
    // them; a regex means the rest are noise. An advertising Bluetooth
    // device emits a PropertiesChanged per beacon, and refreshing on
    // those would be worse than the polling this replaces.
    property var relevant: null

    // 250 ms of silence ends a burst; one more read 1 s later. Both
    // are bt-watch.sh's numbers, measured there, and there is no
    // reason for this bar to hold a second opinion about how long a
    // BlueZ connect takes to stop talking.
    property int settleMs: 250
    property int confirmMs: 1000

    // How long to wait before re-subscribing after the source exits.
    property int retryMs: 2000

    // stdout of `reading`, once per settled burst. Assign from it or
    // ignore it -- ignoring is what holds the last value.
    signal answered(string out)

    // False means the bar is showing the last thing it was told rather
    // than the current state. Nothing draws this yet; it is what a
    // stale-state indicator would read, and it is the property to bind
    // if one is ever wanted.
    readonly property bool watching: sub.running

    // ── THE LEASH, AND IT IS NOT DECORATION ──────────────────
    // MEASURED: Quickshell 0.3.1 does not kill a Process when the
    // shell exits. A `sleep` started by a shell that is then TERMed is
    // still running, reparented to init, with nothing left to stop it.
    //
    // What makes that INTERMITTENT rather than permanent is the
    // nastiest part. A subscription usually dies anyway, at the next
    // line it writes, because the read end of its pipe went with the
    // shell -- so most restarts look clean. It is the QUIET moments
    // that leak: an abandoned gdbus on a Bluetooth stack with nothing
    // to say sits there for hours, which is bt-watch.sh's orphan trap
    // in its own words, and two of them were caught doing exactly that
    // during this build. A leak you only get when the bus is quiet is
    // one that will never reproduce when you go looking for it.
    //
    // setpriv asks the KERNEL to do it: PR_SET_PDEATHSIG, set after
    // the fork and before the exec, so the child is signalled the
    // moment its parent dies -- including a SIGKILL the bar could not
    // have handled itself. Verified both ways: a bare `sleep` under a
    // killed shell survives as ppid 1, the same sleep behind setpriv
    // does not. `Component.onDestruction` was tried first and does not
    // run at all on the way out, which is why this is not QML.
    //
    // The one-shot below is deliberately NOT leashed: it exits on its
    // own in well under a second, and a leash on it would be a line of
    // explanation buying nothing.
    Process {
        id: sub
        command: ["setpriv", "--pdeathsig", "TERM", "--"].concat(root.subscribe)
        running: true
        stdout: SplitParser {
            onRead: line => {
                if (root.relevant === null || root.relevant.test(line))
                    settle.restart();
            }
        }
        // Not an error path -- a bus restart is a normal thing for a
        // laptop to do. Re-subscribe and re-read, because whatever
        // happened while nobody was listening is exactly what the bar
        // is now wrong about.
        onExited: retry.restart()
    }

    Process {
        id: get
        command: root.reading
        stdout: StdioCollector {
            onStreamFinished: root.answered(text)
        }
    }

    // Never two at once. A read that is still running has not yet told
    // us anything, so starting a second one buys a fresher answer only
    // if the first is wedged -- and `confirm` is already the retry.
    function now() {
        if (!get.running) get.running = true;
    }

    Timer {
        id: settle
        interval: root.settleMs
        onTriggered: { root.now(); confirm.restart(); }
    }

    Timer {
        id: confirm
        interval: root.confirmMs
        onTriggered: root.now()
    }

    Timer {
        id: retry
        interval: root.retryMs
        onTriggered: { sub.running = true; root.now(); }
    }

    // The first frame is right rather than empty-then-right. Both
    // subscriptions below also announce themselves on connect, so this
    // is belt and braces -- and it is what makes a reading correct on
    // a machine where the bus has nothing to say for hours.
    Component.onCompleted: root.now()
}
