// ═══════════════════════════════════════════════════════════════
// THE BLUETOOTH PANEL — what the island's body holds for the
// Bluetooth glyph.
//
// 620 x 438 under the bar's 38, the body Wi-Fi and Sound grow into, with
// no background, blur or edge of its own. → WifiPanel.qml, Island.qml
//
// Built from Datum Panels, Bluetooth rounds one and two, with the user's
// dock picks (2026-09-16, round two's 2026-09-18):
//   Kit      Track · Flush rows · Plain cursor · Rounded hover · Sans + mono · motion on
//   Round 2  a click CONNECTS OR DISCONNECTS (pairs, for a nearby device) ·
//            a chevron at the right opens the box · a CARD EACH for connected
//            devices · Scan PINNED TO THE BOTTOM · Stop while it runs
//   List     filled device icon · battery glyph + percent, red at 20 % ·
//            Nearby not drawn before a scan
//   Open row the box holds the auto-connect switch · Disconnect right away ·
//            big digits · card box · well field
//   Buttons  Solid · Stacked · Text · Med
// Asked for on top, 2026-09-18: a nearby device's box holds Remove from
// list under Pair, or the box only repeated what a click on the row does.
// Numbers were read off the mock-up's computed boxes (headless Brave),
// half pixels of type rounded up, and they are Wi-Fi's: 36 px rows, the
// card-box's 4 / 10 / 12 frame, 30 + 4 + 26 stacked buttons, the card's
// 13 / 12 insets.
//
// ── WHAT IS DIFFERENT FROM WI-FI ─────────────────────────────
// Several devices connect at once, so there is a card for EACH, stacked
// 6 apart, and the list below holds only what is not connected -- so a
// click in the list can only connect, never drop the headphones you are
// wearing. There is no signal, so the fan's slot holds the KIND of
// device, and the card's right side is the battery. Pairing asks for a code, not a
// password, and the asking is bt-agent.py's (see Bt.qml): the box shows
// whatever BlueZ asked -- compare a code, type one on the device, enter a
// PIN -- where Wi-Fi shows its password field.
//
// ── WHAT MOVES ───────────────────────────────────────────────
// Gated by the motion skill, and all of it is Wi-Fi's:
//   the switch knobs      180 ms drawer   (the radio, and auto-connect)
//   an opened row         180 ms drawer   glides into view
//   the body swap         90 out / 160 in radio on <-> off
//   the row's verb        130 ms fade     as the pointer or cursor arrives
// Nothing else. A device that connects leaves the list for a card in one
// step (the mock-up's "the list moves once"), Scan <-> Stop is a word,
// rows arriving under Nearby are a list being read, and the code's
// digits light up in place.
// ═══════════════════════════════════════════════════════════════

import Quickshell
import Quickshell.Bluetooth
import QtQuick

// A plain Item, not a FocusScope: WifiPanel.qml says why.
Item {
    id: root

    property bool open: false
    signal closeRequested()

    width: Theme.widthNormal
    height: Theme.panelDepth

    readonly property int pad: 17
    readonly property color txt: Theme.textPrimary
    readonly property color txt2: Theme.textDim
    // The mock-up's outlines over their fills, composited -- WifiPanel.qml,
    // OUTLINES ON A FILL.
    readonly property color edgeOnCard: Qt.alpha(Theme.glassEdge, 0.12)
    readonly property color ringOnCursor: Qt.rgba(1, 1, 1, 0.186)
    readonly property color ringOnBox: Qt.rgba(1, 1, 1, 0.20)

    // ── PANEL STATE ──────────────────────────────────────────
    // Keyed by address, never held in a row: a row is a delegate, and it
    // is destroyed when its device changes section (a pairing finishing)
    // or leaves range. The open box, the prompt and the words it earned
    // all have to survive that.
    property string openAddr: ""
    property string cursorAddr: ""
    property string forgetAddr: ""
    property var busy: ({})        // addr -> "pairing" | "connecting" | "disconnecting"
    property var notes: ({})       // addr -> { text, err }
    property var cancelled: ({})   // addr -> true: we stopped it, so its failure is not news
    property var prompt: null      // { addr, kind, code, entered }: what BlueZ is asking
    property string pin: ""
    property bool scanned: false   // a scan ran in this open, so Nearby is drawn
    property var hidden: ({})      // addr -> true: removed from the list; a scan must not bring it back

    // Maps are replaced, never edited in place, so bindings see the change.
    function withKey(m, k, v) {
        const c = Object.assign({}, m);
        if (v === undefined) delete c[k]; else c[k] = v;
        return c;
    }
    function setNote(a, text, err) { notes = withKey(notes, a, text === "" ? undefined : { text: text, err: err }); }

    function isMine(d) { return d.paired || d.bonded || d.trusted || d.connected; }
    // What a row is doing, as one word: our own verbs, or Bt.qml's own
    // reconnect after the radio comes back, which is a connect too.
    function doingOf(d) { return busy[d.address] || (d.state === BluetoothDeviceState.Connecting ? "connecting" : ""); }

    readonly property var cards: Bt.mine.filter(d => d.connected)
    readonly property var listed: Bt.mine.filter(d => !d.connected)
    readonly property var nearbyShown: scanned || Bt.scanning ? Bt.nearby.filter(d => !hidden[d.address]) : []
    readonly property var order: listed.concat(nearbyShown).map(d => d.address)

    // Connected: the device leaves the list for its card, so its box has
    // nothing left to say -- Wi-Fi's joined().
    onCardsChanged: if (openAddr !== "" && cards.some(d => d.address === openAddr)) closeBox()

    // The keyboard is never left with nobody -- WifiPanel.qml.
    Connections {
        target: root.Window.window
        function onActiveFocusItemChanged() {
            const w = root.Window.window;
            if (root.open && (!w.activeFocusItem || w.activeFocusItem === w.contentItem))
                root.takeFocus();
        }
    }
    function takeFocus() { Qt.callLater(() => root.forceActiveFocus()); }

    onOpenChanged: {
        if (open) {
            root.forceActiveFocus();
        } else {
            Bt.release();
            openAddr = ""; cursorAddr = ""; forgetAddr = ""; pin = ""; prompt = null;
            busy = ({}); notes = ({}); cancelled = ({}); hidden = ({}); scanned = false;
            list.contentY = 0;
        }
    }

    // A device that left takes its box, its cursor and its question with it.
    // Asked of BlueZ's whole list, not of `order`: a pairing that finishes
    // moves the device from Nearby to My devices, and the two lists update
    // one after the other -- for an instant it is in neither, and checking
    // `order` closed the box it was being paired in (measured on the fake).
    Connections {
        target: Bt
        function onDevicesChanged() {
            const here = a => Bt.byAddress(a) !== null;
            if (root.openAddr !== "" && !here(root.openAddr)) { root.openAddr = ""; root.forgetAddr = ""; root.pin = ""; }
            if (root.cursorAddr !== "" && !here(root.cursorAddr)) root.cursorAddr = "";
        }
    }

    // ── THE VERBS ────────────────────────────────────────────
    // A box that closes on a pairing ends it: the question it may ask
    // next would have nowhere to be shown. One box is open at a time.
    function openBox(a) {
        if (openAddr === a) return;
        closeBox();
        openAddr = a;
        reveal.restart();
    }
    function closeBox() {
        if (openAddr === "") return;
        if (busy[openAddr] === "pairing") cancelPairing(openAddr);
        openAddr = ""; forgetAddr = ""; pin = "";
        takeFocus();
    }
    // The chevron, and → / ← on the keyboard.
    function toggleRow(a) {
        cursorAddr = a;
        if (openAddr === a) closeBox(); else openBox(a);
    }

    // A PRESS ON THE ROW, or Enter on the cursor: one step, the one the
    // row's verb names. A stranger is paired, in its box, because pairing
    // may ask a question; a device of yours connects -- or, mid-connect,
    // stops. Its box closes, since what it offered was that same press.
    function press(d) {
        const a = d.address, doing = doingOf(d);
        cursorAddr = a;
        if (!isMine(d)) { openBox(a); if (doing !== "pairing") pairWith(d); return; }
        if (doing === "connecting") unlink(d, true);
        else if (doing === "disconnecting") return;
        else if (d.connected) unlink(d, false);
        else { if (openAddr === a) closeBox(); link(d); }
    }

    function pairWith(d) {
        setNote(d.address, "", false);
        cancelled = withKey(cancelled, d.address, undefined);
        busy = withKey(busy, d.address, "pairing");
        Bt.pair(d);
    }
    function cancelPairing(a) {
        const d = Bt.byAddress(a);
        cancelled = withKey(cancelled, a, true);
        if (prompt && prompt.addr === a && prompt.kind !== "show") Bt.answer("no");
        prompt = null;
        pin = "";
        if (d) Bt.cancelPair(d);
    }
    function link(d) {
        setNote(d.address, "", false);
        cancelled = withKey(cancelled, d.address, undefined);
        busy = withKey(busy, d.address, "connecting");
        Bt.link(d);
    }
    // Disconnect right away (the user's pick): connecting again is one press.
    // Also how a connect in flight is stopped -- BlueZ has no cancel for it.
    function unlink(d, stopping) {
        if (stopping) cancelled = withKey(cancelled, d.address, true);
        else busy = withKey(busy, d.address, "disconnecting");
        Bt.unlink(d);
    }
    function forget(d) {
        forgetAddr = "";
        openAddr = "";
        d.forget();
        takeFocus();
    }
    // A nearby device you do not want: gone from BlueZ's cache, and kept
    // out of the list until the panel closes -- a scan still running would
    // otherwise find it again a second later.
    function removeNearby(d) {
        hidden = withKey(hidden, d.address, true);
        closeBox();
        d.forget();
    }
    function answerCode() {
        if (!prompt) return;
        Bt.answer("yes");
        prompt = null;
    }
    function submitPin() {
        if (!prompt) return;
        if (pin === "") { fieldFocus.restart(); return; }
        if (prompt.kind === "passkey" && !/^[0-9]{1,6}$/.test(pin)) {
            setNote(prompt.addr, "The code is up to six digits.", true);
            fieldFocus.restart();
            return;
        }
        setNote(prompt.addr, "", false);
        Bt.answer("value " + pin);
        prompt = null;
        pin = "";
        takeFocus();
    }

    // ── WHAT BLUEZ SAID ──────────────────────────────────────
    // Failures are said in the open box, in words, where the person who
    // pressed the button is already looking. BlueZ's names are the
    // reliable part; its messages are wire jargon ("br-connection-page-
    // timeout") and only ever matched, never shown.
    function pairWords(e) {
        switch (e.error) {
        case "AuthenticationFailed":   return "Pairing failed. Check the code and try again.";
        case "AuthenticationRejected": return "The device refused to pair.";
        case "AuthenticationTimeout":  return "The device stopped answering.";
        case "AuthenticationCanceled":
        case "Canceled":
        case "Rejected":               return "The device cancelled pairing.";
        case "ConnectionAttemptFailed": return "Couldn't reach it. Is it in pairing mode?";
        case "InProgress":             return "Bluetooth is busy. Try again in a moment.";
        case "NotReady":               return "Bluetooth isn't ready yet.";
        case "UnknownObject":
        case "DoesNotExist":           return "It's no longer nearby. Scan again.";
        }
        return "Couldn't pair.";
    }
    function linkWords(e) {
        const m = (e.message || "").toLowerCase();
        if (e.error === "NotReady") return "Bluetooth isn't ready yet.";
        if (e.error === "InProgress") return "Bluetooth is busy. Try again in a moment.";
        // It asked to pair on a Connect: it has lost the pairing its row
        // still shows, and only pairing again brings it back.
        if (/^Authentication/.test(e.error || "") || /authentication/.test(m)) return "It has forgotten this computer. Forget it here, then pair again.";
        if (/page-timeout|host is down|timed? ?out|abort/.test(m)) return "Couldn't reach it. Is it on and nearby?";
        if (/refused|rejected/.test(m)) return "The device refused the connection.";
        if (/profile-unavailable|protocol not available/.test(m)) return "It has nothing this computer can connect to.";
        return "Couldn't connect.";
    }

    Connections {
        target: Bt
        function onEvent(e) {
            const a = e.address || "";
            if (e.ev === "ask" || e.ev === "show") {
                // Not a pairing started here -- a Connect that BlueZ turned
                // into one. There is no box asking, so say no now rather
                // than leave BlueZ waiting out its timeout.
                if (a === "" || root.busy[a] !== "pairing") {
                    if (e.ev === "ask") Bt.answer("no");
                    return;
                }
                root.prompt = { addr: a, kind: e.ev === "show" ? "show" : e.kind, code: e.code || "", entered: e.entered === undefined ? -1 : e.entered };
                if (root.openAddr !== a) { root.openAddr = a; root.cursorAddr = a; }
                reveal.restart();
                if (e.kind === "pin" || e.kind === "passkey") { root.pin = ""; fieldFocus.restart(); }
            } else if (e.ev === "withdrawn") {
                root.prompt = null;
            } else if (e.ev === "done") {
                const was = root.busy[a];
                const stopped = root.cancelled[a] === true;
                if (e.verb === "pair") {
                    if (was !== "pairing") return;
                    root.busy = root.withKey(root.busy, a, undefined);
                    if (root.prompt && root.prompt.addr === a) { root.prompt = null; root.pin = ""; }
                    if (e.ok || e.error === "AlreadyExists") {
                        // Trusted, so it comes back on its own tomorrow -- the
                        // switch in the box says so and can take it back.
                        const d = Bt.byAddress(a);
                        if (d) { d.trusted = true; root.link(d); }
                    } else if (stopped) {
                        root.cancelled = root.withKey(root.cancelled, a, undefined);
                    } else {
                        root.setNote(a, root.pairWords(e), true);
                    }
                } else if (e.verb === "connect") {
                    if (was !== "connecting") return;
                    root.busy = root.withKey(root.busy, a, undefined);
                    if (e.ok || e.error === "AlreadyConnected") root.setNote(a, "", false);
                    else if (stopped) root.cancelled = root.withKey(root.cancelled, a, undefined);
                    else {
                        // The click that connects leaves the box closed, and
                        // the words are said in it -- so it opens to say them.
                        // Not over another open box: that one may be mid-pairing,
                        // and the words wait here until this box is opened.
                        root.setNote(a, root.linkWords(e), true);
                        if (root.open && (root.openAddr === "" || root.openAddr === a)) {
                            root.cursorAddr = a;
                            root.openBox(a);
                        }
                    }
                } else if (e.verb === "disconnect") {
                    if (was === "disconnecting") root.busy = root.withKey(root.busy, a, undefined);
                }
            } else if (e.ev === "gone" || e.ev === "fatal") {
                // The agent died or never started: nothing in flight will be
                // answered. Said on each box that was waiting.
                for (const k in root.busy)
                    if (root.open) root.setNote(k, "Bluetooth's helper stopped. Try again.", true);
                root.busy = ({});
                root.prompt = null;
            }
        }
    }

    // ── THE RADIO, AND THE BODY SWAP ─────────────────────────
    // WifiPanel.qml's: the switch answers the press, and the reconcile puts
    // it back to the truth if the adapter never follows (rfkill held, a
    // denied write).
    property bool wantOn: Bt.on
    property bool shownOn: true
    Connections {
        target: Bt
        function onOnChanged() { root.wantOn = Bt.on; }
    }
    Timer { id: reconcile; interval: 3000; onTriggered: root.wantOn = Bt.on }

    function toggleRadio() {
        wantOn = !wantOn;
        Bt.setPower(wantOn);
        reconcile.restart();
    }

    Component.onCompleted: shownOn = wantOn
    onWantOnChanged: if (wantOn !== shownOn) swap.restart()

    SequentialAnimation {
        id: swap
        ParallelAnimation {
            NumberAnimation { target: body; property: "opacity"; to: 0; duration: Anim.ms(Anim.fade) }
            NumberAnimation { target: body; property: "y"; to: -3; duration: Anim.ms(Anim.fade) }
        }
        ScriptAction {
            script: {
                root.shownOn = root.wantOn;
                root.openAddr = ""; root.forgetAddr = ""; root.pin = ""; root.prompt = null;
                root.scanned = false; root.hidden = ({});
                body.y = 5;
            }
        }
        ParallelAnimation {
            NumberAnimation {
                target: body; property: "opacity"; to: 1; duration: Anim.ms(Anim.swapIn)
                easing.type: Easing.BezierSpline; easing.bezierCurve: Anim.easeOut
            }
            NumberAnimation {
                target: body; property: "y"; to: 0; duration: Anim.ms(Anim.swapIn)
                easing.type: Easing.BezierSpline; easing.bezierCurve: Anim.easeOut
            }
        }
    }

    // ── THE KEYBOARD ─────────────────────────────────────────
    // ↑↓ move, Enter does what a click on the row does, → opens the row's
    // box and ← closes it (the chevron's keys), Escape backs out one step:
    // the Forget question, the box (ending a pairing), then the panel.
    Keys.onPressed: event => {
        if (event.key === Qt.Key_Escape) {
            if (forgetAddr !== "") forgetAddr = "";
            else if (openAddr !== "") closeBox();
            else root.closeRequested();
            event.accepted = true;
        } else if ((event.key === Qt.Key_Right || event.key === Qt.Key_Left) && cursorAddr !== "" && shownOn) {
            if (event.key === Qt.Key_Right) openBox(cursorAddr);
            else if (openAddr === cursorAddr) closeBox();
            event.accepted = true;
        } else if ((event.key === Qt.Key_Down || event.key === Qt.Key_Up) && shownOn && order.length > 0) {
            const i = order.indexOf(cursorAddr);
            const d = event.key === Qt.Key_Down ? 1 : -1;
            cursorAddr = order[i < 0 ? (d > 0 ? 0 : order.length - 1) : Math.max(0, Math.min(order.length - 1, i + d))];
            reveal.restart();
            if (!root.activeFocus) root.forceActiveFocus();
            event.accepted = true;
        } else if ((event.key === Qt.Key_Return || event.key === Qt.Key_Enter) && cursorAddr !== "" && shownOn) {
            const d = Bt.byAddress(cursorAddr);
            if (d) press(d);
            event.accepted = true;
        }
    }

    // ═══ THE HEAD ═══════════════════════════════════════════
    Item {
        x: root.pad
        y: 15
        width: root.width - root.pad * 2
        height: 22

        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: "Bluetooth"
            color: root.txt
            font.family: Theme.fontSans
            font.pixelSize: 14
            font.weight: Font.DemiBold
            font.letterSpacing: 0.14
        }

        Switch {
            id: sw
            visible: Bt.adapter !== null
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            on: root.wantOn
            onToggled: root.toggleRadio()
        }
    }

    // ═══ THE BODY ═══════════════════════════════════════════
    Item {
        id: body
        width: root.width
        height: root.height

        // ── OFF, OR NO ADAPTER ───────────────────────────────
        // No adapter is said only once BlueZ has had its chance to answer
        // (Bt.adapter is null before that too).
        Column {
            visible: Bt.adapter !== null ? !root.shownOn : settled.done
            anchors.horizontalCenter: parent.horizontalCenter
            y: 42 + (387 - height) / 2
            spacing: 7

            Icon {
                anchors.horizontalCenter: parent.horizontalCenter
                name: "bt-off"
                size: 20
                color: root.txt2
                opacity: 0.8
            }
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: Bt.adapter === null ? "No Bluetooth adapter." : "Bluetooth is off."
                color: root.txt2
                font.family: Theme.fontMono
                font.pixelSize: 12
            }
            Text {
                visible: Bt.adapter !== null
                anchors.horizontalCenter: parent.horizontalCenter
                text: "Turn Bluetooth on to see devices."
                color: root.txt2
                opacity: 0.75
                font.family: Theme.fontMono
                font.pixelSize: 11
            }
        }

        // ── ON ───────────────────────────────────────────────
        // A card for each connected device at Wi-Fi's y, 6 apart; with none,
        // Wi-Fi's one grey line in their place. Then both sections, and Scan
        // pinned under it all.
        //
        // THE CARDS SCROLL WITH THE LIST. They sat above it, as Wi-Fi's one
        // card does, and every card took 68 px from the list: four connected
        // devices left it one row, and five left it none at all (measured,
        // fake BlueZ). At rest the picture is the same -- the list starts at
        // the cards' y and they are its first items.
        Item {
            anchors.fill: parent
            visible: root.shownOn && Bt.adapter !== null

            Text {
                visible: root.cards.length === 0
                x: root.pad
                y: 40
                text: "Nothing connected"
                color: root.txt2
                font.family: Theme.fontMono
                font.pixelSize: 11
            }

            Flickable {
                id: list
                x: root.pad
                y: root.cards.length > 0 ? 46 : 70
                width: root.width - root.pad * 2
                // 44 above the bottom margin is the Scan row's -- ScanRow.qml.
                height: root.height - 14 - 44 - y
                clip: true
                contentWidth: width
                contentHeight: col.height
                boundsBehavior: Flickable.StopAtBounds

                Behavior on contentY {
                    id: glide
                    enabled: false
                    NumberAnimation {
                        duration: Anim.ms(Anim.travel)
                        easing.type: Easing.BezierSpline
                        easing.bezierCurve: Anim.drawer
                    }
                }

                Column {
                    id: col
                    width: list.width

                    Repeater {
                        model: ScriptModel { values: root.cards }
                        delegate: DevCard {}
                    }
                    Item {
                        visible: root.cards.length > 0
                        width: 1
                        // the last card's own 6, plus 7: Wi-Fi's 13 under its card
                        height: 7
                    }

                    // Everything yours is on a card: the section has nothing
                    // to hold, so it is not drawn.
                    Section { id: mineLabel; text: "My devices"; visible: root.listed.length > 0 || Bt.mine.length === 0 }
                    Item { width: 1; height: 6; visible: mineLabel.visible }
                    Repeater {
                        id: mineRep
                        model: ScriptModel { values: root.listed }
                        delegate: DevRow {}
                    }
                    Empty {
                        visible: Bt.mine.length === 0
                        text: "No devices yet."
                    }

                    // Not drawn before a scan (the user's pick): an empty
                    // section reads as something failing to load. Nor while
                    // a scan has found nothing yet -- the Scan row already
                    // says it is looking.
                    Item { width: 1; height: 13; visible: nearbyLabel.visible && mineLabel.visible }
                    Section {
                        id: nearbyLabel
                        text: "Nearby devices"
                        visible: (root.scanned || Bt.scanning) && (root.nearbyShown.length > 0 || !Bt.scanning)
                    }
                    Item { width: 1; height: 6; visible: nearbyLabel.visible }
                    Repeater {
                        id: nearRep
                        model: ScriptModel { values: root.nearbyShown }
                        delegate: DevRow {}
                    }
                    Empty {
                        visible: nearbyLabel.visible && root.nearbyShown.length === 0
                        text: "Nothing new nearby."
                    }
                }
            }

            // The thumb, only when there is something to scroll.
            Rectangle {
                visible: list.contentHeight > list.height + 1
                x: list.x + list.width + 7
                y: list.y + list.visibleArea.yPosition * list.height
                width: 5
                height: Math.max(20, list.visibleArea.heightRatio * list.height)
                radius: 3
                color: Qt.rgba(1, 1, 1, 0.14)
            }

            // Scan, and Stop while it runs: a scan slows connecting down, so
            // it must be stoppable, and a button that stops something says
            // Stop. It goes with the body, so it is not drawn with the radio
            // off -- the switch turns the radio on, not this.
            ScanRow {
                x: root.pad
                y: root.height - 14 - height
                width: root.width - root.pad * 2
                label: "Scan for new devices"
                busyLabel: "Looking for devices…"
                busyGlyph: "bt"
                busy: Bt.scanning
                stopLabel: "Stop"
                onScan: { root.scanned = true; Bt.scan(true); }
                onStop: Bt.scan(false)
            }
        }
    }

    Timer { id: settled; interval: 3000; running: true; property bool done: false; onTriggered: done = true }

    // ── AN OPENED ROW SCROLLS INTO VIEW ──────────────────────
    // WifiPanel.qml's, row for row: the box's bottom 2 px inside the list,
    // or its top if it is taller than the list; rows in view do not move.
    Timer {
        id: reveal
        interval: 1
        onTriggered: {
            col.forceLayout();
            let item = null;
            for (const rep of [mineRep, nearRep])
                for (let i = 0; i < rep.count; i++) {
                    const it = rep.itemAt(i);
                    if (it && it.addr === root.cursorAddr) item = it;
                }
            if (!item) return;
            const top = item.y, bottom = item.y + item.height;
            let y = list.contentY;
            if (item.height > list.height) y = top + 2;
            else if (bottom > y + list.height) y = bottom - list.height;
            else if (top < y) y = top;
            y = Math.max(0, Math.min(y, col.height - list.height));
            if (Math.abs(y - list.contentY) < 0.5) return;
            glide.enabled = Anim.enabled;
            list.contentY = y;
            glide.enabled = false;
        }
    }

    function revealLater() { reveal.restart(); }
    function focusFieldLater() { fieldFocus.restart(); }
    Timer {
        id: fieldFocus
        interval: 1
        onTriggered: {
            for (const rep of [mineRep, nearRep])
                for (let i = 0; i < rep.count; i++) {
                    const it = rep.itemAt(i);
                    if (it && it.addr === root.openAddr) it.focusField();
                }
        }
    }

    // ═══ PIECES ═════════════════════════════════════════════

    component Empty: Text {
        width: parent ? parent.width : 0
        height: 36
        leftPadding: 9
        verticalAlignment: Text.AlignVCenter
        color: root.txt2
        font.family: Theme.fontMono
        font.pixelSize: 11
    }

    // Mono 11 in the panel's grey, with a name in the ink colour -- the
    // Forget question's grammar, used by every sentence in the box.
    component Say: Text {
        property string before: ""
        property string name: ""
        property string after: ""
        width: parent ? parent.width : 0
        wrapMode: Text.Wrap
        textFormat: Text.StyledText
        text: before + "<font color=\"" + root.txt + "\">"
              + name.replace(/&/g, "&amp;").replace(/</g, "&lt;") + "</font>" + after
        color: root.txt2
        font.family: Theme.fontMono
        font.pixelSize: 11
        lineHeight: 1.1
    }

    // ── THE BATTERY ──────────────────────────────────────────
    // A drawn cell and the percent beside it (Battery + %, the user's
    // pick): the mock-up's SVG, box for box -- outline at 55 %, the charge
    // 2 px inside it, the nub. Red at 20 % and below, glyph and word both.
    component Battery: Row {
        id: bat
        property real level: 0
        property bool big: false
        readonly property int pct: Math.round(level * 100)
        readonly property int w: big ? 20 : 16
        readonly property int h: big ? 10 : 8
        readonly property color ink: pct <= 20 ? Theme.danger : big ? root.txt : root.txt2
        spacing: big ? 8 : 6

        Item {
            anchors.verticalCenter: parent.verticalCenter
            width: bat.w + 2
            height: bat.h
            Rectangle {
                width: bat.w
                height: bat.h
                radius: 2
                color: "transparent"
                border.width: 1
                border.color: Qt.alpha(bat.ink, 0.55)
            }
            Rectangle {
                x: 2; y: 2
                width: Math.max(1, Math.round((bat.w - 4) * bat.level))
                height: bat.h - 4
                radius: 1
                color: bat.ink
            }
            Rectangle {
                x: bat.w
                y: bat.h / 2 - 1.5
                width: 1.5
                height: 3
                radius: 0.5
                color: Qt.alpha(bat.ink, 0.55)
            }
        }
        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: bat.pct + "%"
            color: bat.ink
            font.family: Theme.fontMono
            font.pixelSize: bat.big ? 15 : 11
            font.letterSpacing: bat.big ? -0.3 : 0
        }
    }

    // ── A CONNECTED DEVICE'S CARD ────────────────────────────
    // Wi-Fi's card, tight: its kind in mint, Connected over the name, and
    // at the right the battery and Disconnect -- right away, the user's
    // pick, because connecting again is one click on the row it becomes.
    // Trust and Forget are the row's box, once it is disconnected.
    // 68 tall, the card's 62 and the 6 before the next: the gap is the
    // card's own, because a Column's spacing would land between every row
    // under the cards too.
    component DevCard: Item {
        id: c
        required property var modelData
        readonly property var dev: modelData
        readonly property string doing: root.doingOf(dev)

        width: parent ? parent.width : 0
        height: 68

        Rectangle {
            width: c.width
            height: 62
            radius: 11
            color: Theme.panelCard
            border.width: 1
            border.color: root.edgeOnCard

            Icon {
                x: 14 + (20 - width) / 2
                anchors.verticalCenter: parent.verticalCenter
                name: Bt.kindIcon(c.dev)
                size: 20
                color: Theme.accent
            }
            Rectangle { x: 45; y: 16.5; width: 5; height: 5; radius: 2.5; color: Theme.accent }
            Text {
                x: 56
                y: 12
                height: 14
                verticalAlignment: Text.AlignVCenter
                text: "Connected"
                color: Theme.accent
                font.family: Theme.fontCaps
                font.pixelSize: Theme.capsPx
                font.weight: Theme.capsWeight
                font.letterSpacing: Theme.capsTrack
                font.capitalization: Font.AllUppercase
            }
            Text {
                x: 45
                y: 29
                width: cardRight.x - 16 - x
                elide: Text.ElideRight
                text: c.dev.name
                color: root.txt
                font.family: Theme.fontSans
                font.pixelSize: 17
                font.letterSpacing: -0.34
            }

            Row {
                id: cardRight
                anchors.right: parent.right
                anchors.rightMargin: 14
                anchors.verticalCenter: parent.verticalCenter
                spacing: 14
                Battery {
                    visible: c.dev.batteryAvailable
                    anchors.verticalCenter: parent.verticalCenter
                    big: true
                    level: c.dev.battery
                }
                Btn {
                    anchors.verticalCenter: parent.verticalCenter
                    label: "Disconnect"
                    kind: "ghost"
                    dim: true
                    fontPx: 11
                    hpad: 11
                    implicitHeight: 22
                    enabled: c.doing !== "disconnecting"
                    onClicked: root.unlink(c.dev, false)
                }
            }
        }
    }

    // ── ONE ROW, AND THE BOX IT GROWS INTO ───────────────────
    component DevRow: Item {
        id: r
        required property var modelData
        readonly property var dev: modelData
        readonly property string addr: dev.address
        readonly property bool mine: root.isMine(dev)
        readonly property bool isOpen: root.openAddr === addr && root.shownOn
        readonly property bool isCursor: root.cursorAddr === addr
        // Bt.qml's own reconnect after the radio comes back is a connect too:
        // the row says so, and its button stops it rather than starting a second.
        readonly property string doing: root.doingOf(dev)
        readonly property var ask: root.prompt && root.prompt.addr === addr ? root.prompt : null
        readonly property var note: root.notes[addr]
        readonly property bool asking: root.forgetAddr === addr && mine
        readonly property bool act: dev.connected

        // What the box is showing, as one word.
        readonly property string mode: asking ? "forget"
            : mine ? "device"
            : doing !== "pairing" ? "pair"
            : ask ? ask.kind
            : "wait"
        readonly property bool typing: mode === "pin" || mode === "passkey"
        // What a press on the row will do, as the word shown for it. None
        // while pairing: the box is open and says what is happening.
        readonly property string verb: doing === "pairing" || doing === "disconnecting" ? ""
            : !mine ? "Pair"
            : doing === "connecting" ? "Cancel"
            : act ? "Disconnect" : "Connect"

        function focusField() { if (typing) field.forceActiveFocus(); }
        Component.onCompleted: if (isOpen && typing) root.focusFieldLater()
        // A box grows after it opened -- the code arrives, a note appears --
        // and the reveal measured it before its contents were laid out, so
        // Pair sat below the fold (measured). It glides again on every height.
        onHeightChanged: if (isOpen && isCursor) root.revealLater()

        width: parent ? parent.width : 0
        height: isOpen ? box.height + 4 : 36

        Rectangle {
            id: box
            y: r.isOpen ? 2 : 0
            width: r.width
            height: r.isOpen ? 36 + det.height : 36
            // WifiPanel.qml's box: flush until the pointer or the cursor is
            // on it (Rounded hover, the same 7 px corner as the cursor); open,
            // the card-box, and the cursor lifts the box's own edge.
            radius: r.isOpen ? 11 : 7
            color: r.isOpen ? Theme.panelCard
                 : r.isCursor ? Theme.panelCursor
                 : hit.containsMouse ? Theme.panelHover
                 : Qt.rgba(1, 1, 1, 0)
            border.width: r.isOpen || r.isCursor ? 1 : 0
            border.color: r.isOpen ? (r.isCursor ? root.ringOnBox : root.edgeOnCard) : root.ringOnCursor
            Behavior on color { enabled: Anim.enabled; ColorAnimation { duration: Anim.ms(Anim.hover) } }

            MouseArea {
                id: hit
                width: parent.width
                height: 36
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onPressed: root.press(r.dev)
            }

            // The kind of device, where Wi-Fi draws its fan.
            Icon {
                x: 9 + (16 - width) / 2
                anchors.verticalCenter: hit.verticalCenter
                name: Bt.kindIcon(r.dev)
                size: 15
                color: r.act ? Theme.accent : root.txt2
                Behavior on color { enabled: Anim.enabled; ColorAnimation { duration: Anim.ms(Anim.hover) } }
            }

            Text {
                x: 34
                anchors.verticalCenter: hit.verticalCenter
                width: right.x - 9 - x
                elide: Text.ElideRight
                text: r.dev.name
                color: r.act ? Theme.accent : root.txt
                font.family: Theme.fontSans
                font.pixelSize: 13
                Behavior on color { enabled: Anim.enabled; ColorAnimation { duration: Anim.ms(Anim.hover) } }
            }

            Row {
                id: right
                anchors.right: parent.right
                anchors.rightMargin: 3      // the chevron's tile reaches 6 px into the 9
                anchors.verticalCenter: hit.verticalCenter
                spacing: 9

                // What it is doing. Its battery is on its card: only a
                // connected device reports one, and a connected device is
                // not in the list.
                Text {
                    visible: text !== ""
                    anchors.verticalCenter: parent.verticalCenter
                    text: r.doing === "pairing" && !r.ask ? "Pairing…"
                        : r.doing === "connecting" ? "Connecting…"
                        : r.doing === "disconnecting" ? "Disconnecting…"
                        : ""
                    color: root.txt2
                    font.family: Theme.fontMono
                    font.pixelSize: 11
                }
                // THE ROW SAYS WHAT A CLICK DOES -- under the pointer or the
                // keyboard cursor, and only then. Kept in the layout at 0 so
                // the name does not re-elide as the pointer crosses it.
                Text {
                    visible: r.verb !== ""
                    anchors.verticalCenter: parent.verticalCenter
                    text: r.verb
                    opacity: hit.containsMouse || chevHit.containsMouse || r.isCursor ? 1 : 0
                    color: root.txt2
                    font.family: Theme.fontMono
                    font.pixelSize: 11
                    font.letterSpacing: 0.33
                    Behavior on opacity { enabled: Anim.enabled; NumberAnimation { duration: Anim.ms(Anim.hover) } }
                }
                // The chevron is the box's own button: the row's press is
                // the verb, so the box needs a target of its own.
                Rectangle {
                    width: 24
                    height: 24
                    radius: 6
                    color: chevHit.containsMouse ? Qt.rgba(1, 1, 1, 0.09) : Qt.rgba(1, 1, 1, 0)
                    Behavior on color { enabled: Anim.enabled; ColorAnimation { duration: Anim.ms(Anim.hover) } }
                    Icon {
                        anchors.centerIn: parent
                        name: "chev"
                        size: 14
                        color: chevHit.containsMouse ? root.txt : root.txt2
                        rotation: r.isOpen ? 180 : 0
                    }
                    MouseArea {
                        id: chevHit
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onPressed: root.toggleRow(r.addr)
                    }
                }
            }

            // ── WHAT THE BOX HOLDS ───────────────────────────
            Column {
                id: det
                visible: r.isOpen
                x: 12
                y: 36
                width: parent.width - 24
                spacing: 10
                topPadding: meta.visible ? 2 : 4
                // A quiet button last has its own air; the frame gives it back.
                bottomPadding: (actions.visible && second.visible) || r.typing ? 6 : 12

                Text {
                    id: meta
                    visible: r.note !== undefined
                    width: parent.width
                    wrapMode: Text.Wrap
                    text: r.note !== undefined ? r.note.text : ""
                    color: r.note !== undefined && r.note.err ? Theme.danger : root.txt2
                    font.family: Theme.fontMono
                    font.pixelSize: 11
                }

                Say {
                    visible: r.mode === "wait"
                    before: "Pairing with "; name: r.dev.name; after: "…"
                }
                Say {
                    visible: r.mode === "confirm"
                    before: "Check that "; name: r.dev.name; after: " shows this code."
                }
                Say {
                    visible: r.mode === "allow"
                    before: "Pair with "; name: r.dev.name; after: "? It has no code to compare."
                }
                Say {
                    visible: r.mode === "show"
                    before: "Type this code on "; name: r.dev.name; after: ", then press Enter."
                }
                Say {
                    visible: r.mode === "pin"
                    before: "Enter the PIN for "; name: r.dev.name; after: ". Many car kits use 0000."
                }
                Say {
                    visible: r.mode === "passkey"
                    before: "Enter the code shown on "; name: r.dev.name; after: "."
                }

                // BIG DIGITS: comparing six digits across two screens is the
                // whole task. Typed ones light up as BlueZ reports each key.
                Row {
                    visible: (r.mode === "confirm" || r.mode === "show") && r.ask !== null
                    height: 26
                    Repeater {
                        model: {
                            const c = r.ask ? r.ask.code : "";
                            return (c.length === 6 ? c.slice(0, 3) + " " + c.slice(3) : c).split("");
                        }
                        Text {
                            required property string modelData
                            required property int index
                            // digits typed so far; the space is not a digit
                            readonly property int nth: index > 3 ? index - 1 : index
                            text: modelData
                            color: r.ask && r.ask.kind === "show" && r.ask.entered >= 0 && nth >= r.ask.entered
                                   ? Qt.alpha(root.txt2, 0.55) : root.txt
                            font.family: Theme.fontMono
                            font.pixelSize: 24
                            font.letterSpacing: 3.36
                            height: 26
                            verticalAlignment: Text.AlignVCenter
                        }
                    }
                }

                // LET IT CONNECT ON ITS OWN -- BlueZ's `trusted`. A trusted
                // headset reconnects by itself when it is turned on.
                Item {
                    visible: r.mode === "device"
                    width: parent.width
                    height: 22
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: "Let it connect on its own"
                        color: root.txt2
                        font.family: Theme.fontMono
                        font.pixelSize: 11
                    }
                    Switch {
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        on: r.dev.trusted
                        onToggled: r.dev.trusted = !r.dev.trusted
                    }
                }

                // The PIN, and Pair at the end of its line -- Wi-Fi's password
                // row. Shown, not dotted: a pairing code is not a secret.
                Row {
                    visible: r.typing
                    width: parent.width
                    height: 37
                    spacing: 8

                    Rectangle {
                        width: parent.width - 8 - pairKey.width
                        height: parent.height
                        radius: 8
                        color: Theme.panelWell

                        TextInput {
                            id: field
                            x: 12
                            width: parent.width - 24
                            anchors.verticalCenter: parent.verticalCenter
                            clip: true
                            maximumLength: r.mode === "passkey" ? 6 : 16
                            inputMethodHints: r.mode === "passkey" ? Qt.ImhDigitsOnly : Qt.ImhNone
                            text: root.pin
                            color: root.txt
                            selectionColor: Qt.alpha(Theme.accent, 0.35)
                            selectedTextColor: root.txt
                            font.family: Theme.fontMono
                            font.pixelSize: 12
                            selectByMouse: true
                            onTextEdited: {
                                root.pin = text;
                                if (r.note !== undefined && r.note.err) root.setNote(r.addr, "", false);
                            }
                            // Taken, not left to onAccepted -- WifiPanel.qml says why.
                            Keys.onReturnPressed: event => { root.submitPin(); event.accepted = true; }
                            Keys.onEnterPressed: event => { root.submitPin(); event.accepted = true; }
                            Keys.onEscapePressed: event => { root.toggleRow(r.addr); event.accepted = true; }

                            cursorDelegate: Rectangle {
                                width: 1
                                height: 14
                                color: Theme.accent
                                visible: field.activeFocus
                                SequentialAnimation on opacity {
                                    running: field.activeFocus
                                    loops: Animation.Infinite
                                    PropertyAction { value: 1 }
                                    PauseAnimation { duration: 550 }
                                    PropertyAction { value: 0 }
                                    PauseAnimation { duration: 550 }
                                }
                            }

                            Text {
                                visible: field.text === ""
                                anchors.verticalCenter: parent.verticalCenter
                                text: r.mode === "passkey" ? "Code" : "PIN"
                                color: root.txt2
                                font: field.font
                            }
                        }
                    }

                    Btn {
                        id: pairKey
                        kind: "solid"
                        label: "Pair"
                        implicitHeight: 37
                        onClicked: root.submitPin()
                    }
                }

                // The act over the quiet one, stacked, full width. Which act
                // depends on what the device is doing; a button names what
                // pressing it does, never what the device is busy with.
                Column {
                    id: actions
                    visible: r.mode !== "forget"
                    width: parent.width
                    spacing: 4

                    Btn {
                        visible: !r.typing
                        width: parent.width
                        enabled: r.doing !== "disconnecting"
                        kind: r.mode === "pair" || r.mode === "confirm" || r.mode === "allow"
                              || (r.mode === "device" && !r.act && r.doing === "") ? "solid" : "ghost"
                        label: r.mode === "wait" || r.mode === "show" ? "Cancel"
                             : r.mode !== "device" ? "Pair"
                             : r.doing === "connecting" ? "Cancel"
                             : r.act ? "Disconnect" : "Connect"
                        onClicked: {
                            if (r.mode === "pair") root.pairWith(r.dev);
                            else if (r.mode === "wait" || r.mode === "show") root.cancelPairing(r.addr);
                            else if (r.mode === "confirm" || r.mode === "allow") root.answerCode();
                            else if (r.doing === "connecting") root.unlink(r.dev, true);
                            else if (r.act) root.unlink(r.dev, false);
                            else root.link(r.dev);
                        }
                    }
                    // Forget under a device of yours; Remove from list under a
                    // stranger's Pair -- without it the box only repeated what a
                    // click on the row already does (2026-09-18).
                    Btn {
                        id: second
                        visible: r.mode === "device" || r.mode === "pair" || r.mode === "confirm" || r.mode === "allow" || r.typing
                        width: parent.width
                        implicitHeight: 26
                        kind: "quiet"
                        label: r.mode === "device" ? "Forget" : r.mode === "pair" ? "Remove from list" : "Cancel"
                        onClicked: {
                            if (r.mode === "device") root.forgetAddr = r.addr;
                            else if (r.mode === "pair") root.removeNearby(r.dev);
                            else root.cancelPairing(r.addr);
                        }
                    }
                }

                // FORGET ASKS ONCE, IN PLACE: undoing it means pairing again.
                // Cancel last, where Forget was -- buttons act on press.
                Item {
                    visible: r.mode === "forget"
                    width: parent.width
                    height: 30

                    Text {
                        anchors.left: parent.left
                        anchors.right: dangerBtn.left
                        anchors.rightMargin: 8
                        anchors.verticalCenter: parent.verticalCenter
                        elide: Text.ElideRight
                        textFormat: Text.StyledText
                        text: "Forget <font color=\"" + root.txt + "\">" + r.dev.name.replace(/&/g, "&amp;").replace(/</g, "&lt;")
                              + "</font>? You will have to pair it again."
                        color: root.txt2
                        font.family: Theme.fontMono
                        font.pixelSize: 11
                    }
                    Btn {
                        id: dangerBtn
                        anchors.right: cancelBtn.left
                        anchors.rightMargin: 8
                        anchors.verticalCenter: parent.verticalCenter
                        kind: "danger"
                        label: "Forget"
                        onClicked: root.forget(r.dev)
                    }
                    Btn {
                        id: cancelBtn
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        kind: "quiet"
                        label: "Cancel"
                        onClicked: root.forgetAddr = ""
                    }
                }
            }
        }
    }
}
