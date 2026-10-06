// ═══════════════════════════════════════════════════════════════
// THE WI-FI PANEL — what the island's body holds when it is grown.
//
// This is the part below the bar: 620 x 438, which with the bar's own
// 38 is the 620 x 476 Datum Panels shipped. It draws no background,
// no blur and no edge of its own -- the glass is the island's, and a
// panel with its own surface would be the second object the whole
// series was about removing. → Island.qml, shell.qml
//
// EVERY NUMBER HERE IS READ OFF THE SHIPPED MOCK-UP, not eyeballed:
// Datum Panels rev 10 was rendered headless and each element's box,
// type and colour dumped from the computed styles. Where CSS had a
// half pixel of type (12.5, 10.5) this rounds UP, for the reason
// Clock.qml gives at length: font.pixelSize is an int, and pointSize
// would render a different size on a different screen.
//
// THE SHIPPED SET, so a later pass knows what is a decision and not a
// default: Track switch · Flush rows · Plain cursor · Sans + mono ·
// Known / Other groups · Wi-Fi fan · percent shown · no saved marker ·
// filled padlock · an opened row GROWS into a card-box · the field is
// a well · Solid Join, flat · Join over Forget, stacked · text
// buttons, medium · Scan pinned to the bottom · card: no icon.
// → Datum Panels §11
//
// CHANGED 2026-09-15, by request: the download meter is gone. The card's
// right side is the signal (fan + percent), its details are labelled
// columns (band, security, address), and link rate's slot is Disconnect,
// which asks once in place the way Forget does.
//
// CHANGED 2026-09-18, by request: Rescan left the header for Bluetooth's
// pinned row (ScanRow.qml) -- "Scan for new networks" under the list,
// "Looking for networks…" while NetworkManager scans, and what the scan
// found at its right end. The buttons became Text (Btn.qml).
//
// ── WHAT MOVES, AND WHAT DOES NOT ────────────────────────────
// Gated by the motion skill; frequency first. Opening the panel is
// occasional, and the island owns that motion (the body's height).
// Inside it, three things move and nothing else does:
//   the switch knob     180 ms drawer   -- the control you pressed
//   an opened row       180 ms drawer   -- scrolled into view, so the
//                                          box you opened is not below
//                                          the fold (round nine's bug)
//   the body swap       90 out / 160 in -- radio on <-> off, rare
// Rows do not animate open. The mock-up that was tested and signed off
// does not, and the list is text you are reading.
// ═══════════════════════════════════════════════════════════════

import Quickshell
import Quickshell.Networking
import QtQuick
import QtQuick.Shapes

// A plain Item, NOT a FocusScope. A scope that is given focus hands it
// straight back to whichever child held it last -- here the password
// field, hidden a moment earlier -- so after Escape closed a row the
// keyboard went into an invisible field and the next Escape did nothing.
// Measured: activeFocusItem was the QQuickTextInput. As an Item, taking
// focus means the panel itself has it.
Item {
    id: root

    // Set by the island: true while the body is grown (or growing).
    property bool open: false
    signal closeRequested()

    width: Theme.widthNormal
    height: Theme.panelDepth

    readonly property int pad: 17
    readonly property color txt: Theme.textPrimary
    readonly property color txt2: Theme.textDim
    readonly property color edge: Theme.glassEdge
    // OUTLINES ON A FILL. The mock-up drew a box's outline over its
    // fill, so the two whites added up; a QML Rectangle draws its border
    // INSTEAD of the fill under it. The same numbers therefore came out
    // dimmer here -- the keyboard cursor's ring measured 30 on a 24 fill
    // live against 57 on 33 in the mock-up, and read as no outline at
    // all. These are the mock-up's pairs composited: 1-(1-fill)(1-ring).
    readonly property color edgeOnCard: Qt.alpha(Theme.glassEdge, 0.12)   // .085 over .035
    readonly property color ringOnCursor: Qt.rgba(1, 1, 1, 0.186)         // .11 over .085
    readonly property color ringOnBox: Qt.rgba(1, 1, 1, 0.20)             // .17 over .035
    readonly property int capsPx: Theme.capsPx       // tracked capitals; see Section.qml
    readonly property real capsTrack: Theme.capsTrack

    // ── PANEL STATE ──────────────────────────────────────────
    // All of it lives here, keyed by SSID, and none of it in a row.
    // A row is a delegate and a delegate can be destroyed under you --
    // its network leaves range, or is saved or forgotten from outside and
    // changes group. The open box, the
    // typed key and the error it earned all have to survive that, which
    // is exactly the focus-loss bug eww's panel had from the other side.
    property string openSsid: ""
    property string cursorSsid: ""
    property string confirmSsid: ""
    property bool askDisconnect: false
    property string psk: ""
    property var needKey: ({})     // ssid -> true: saved, but the secret is missing or wrong
    property var notes: ({})       // ssid -> { text, err }
    property var rank: ({})        // ssid -> position; see rerank()
    property var fresh: ({})       // ssid -> true: joining a network that had no profile
    property var cancelled: ({})   // ssid -> true: its join was cancelled; its failure is not news
    property string returnTo: ""   // the network we were on when a join started
    property string waitFor: ""    // Join pressed on a remembered row; joins when the scan finds it

    Binding { target: Wifi; property: "scanning"; value: root.open }

    // THE KEYBOARD IS NEVER LEFT WITH NOBODY. A row is a delegate, and
    // it is destroyed when its network moves between Known and Other
    // (saved or forgotten from outside, a remembered row turning live) or
    // leaves range. If its field had the keyboard, focus goes with it to no item
    // at all, and Escape stops closing the panel. So whenever the window's
    // focus lands on nothing while the panel is open, the panel takes it.
    Connections {
        target: root.Window.window
        function onActiveFocusItemChanged() {
            const w = root.Window.window;
            if (root.open && (!w.activeFocusItem || w.activeFocusItem === w.contentItem))
                root.takeFocus();
        }
    }

    onOpenChanged: {
        if (open) {
            rerank();
            searching.restart();
            cardUp = Wifi.active !== null;
            lastActive = Wifi.active ? Wifi.active.name : "";
            root.forceActiveFocus();
        } else {
            openSsid = ""; cursorSsid = ""; confirmSsid = ""; psk = ""; askDisconnect = false;
            notes = ({}); needKey = ({}); cancelled = ({}); returnTo = ""; waitFor = "";
            list.contentY = 0;
        }
    }

    // ── THE LIST DOES NOT RE-SORT UNDER YOU ──────────────────
    // Sorted strongest first, but only when the SET of networks changes,
    // when the panel opens, and when a row closes -- never because a
    // signal moved two percent. A list that reorders itself while the
    // pointer is travelling to a row delivers the click to its
    // neighbour. The percent still updates in place.
    function rerank() {
        const a = allNets.slice().sort((x, y) => y.signalStrength - x.signalStrength);
        const r = {};
        a.forEach((n, i) => r[n.name] = i);
        rank = r;
    }
    onAllNetsChanged: {
        // A network that left range takes its open box and its cursor
        // with it; nothing is left pointing at a row that is gone.
        const listed = s => allNets.some(n => n.name === s);
        if (openSsid !== "" && !listed(openSsid)) { openSsid = ""; confirmSsid = ""; psk = ""; }
        if (cursorSsid !== "" && !listed(cursorSsid)) cursorSsid = "";
        if (waitFor !== "") {
            const live = netNamed(waitFor);
            if (live) { waitFor = ""; join(live); }
            else if (!listed(waitFor)) waitFor = "";
        }
        if (openSsid === "") rerank();
    }
    function byRank(a, b) {
        const ra = root.rank[a.name], rb = root.rank[b.name];
        return (ra === undefined ? 1e9 : ra) - (rb === undefined ? 1e9 : rb);
    }

    // The live networks, and while the opening scan runs, the ones
    // remembered from last time that it has not found yet. A remembered
    // row is a plain object with the same fields; the same object for the
    // whole scan, so its row is not re-created. → Wifi.qml, remembered
    readonly property var ghosts: Wifi.stale ? Wifi.remembered.filter(g => !netNamed(g.name)) : []
    readonly property var allNets: Wifi.nets.concat(ghosts)
    // A network is on the card or in the list, never both -- and while
    // the card is held through a join, the network it was showing stays
    // off the list too. It is disconnected for those seconds, and listing
    // it pushed every row down a line and pulled them back up when it
    // rejoined (frames, 2026-09-15).
    function onCard(n) { return n.connected || (cardUp && !Wifi.active && n.name === lastActive); }
    readonly property var knownNets: allNets.filter(n => saved(n) && !onCard(n)).sort(byRank)
    readonly property var otherNets: allNets.filter(n => !saved(n) && !onCard(n)).sort(byRank)
    readonly property var order: knownNets.concat(otherNets).map(n => n.name)

    function netNamed(s) {
        for (const n of Wifi.nets) if (n.name === s) return n;
        return null;
    }

    // SAVED, AS THE PERSON SEES IT. NetworkManager writes a profile the
    // moment a first join starts and the panel deletes it if the join
    // fails, so `known` flips true and back within one attempt -- and the
    // row flew to Known, its box swapped the field for Join + Forget, then
    // both came back ("the panel starts jumping", 2026-09-15). A network
    // on its first join is not saved until it has joined.
    function saved(n) { return n.known && fresh[n.name] !== true; }

    // Not active, locked, and nothing saved -- or saved and the last
    // attempt said the secret was missing. Everything else joins silently.
    function needsKey(n) {
        return !n.connected && Wifi.locked(n) && (!saved(n) || needKey[n.name] === true);
    }

    // The maps above are replaced, never edited in place, so bindings see
    // the change. `flag` is that copy for the ssid -> true ones.
    function flag(m, s, on) {
        const c = Object.assign({}, m);
        if (on) c[s] = true; else delete c[s];
        return c;
    }

    function setNote(s, text, err) {
        const m = Object.assign({}, notes);
        if (text === "") delete m[s]; else m[s] = { text: text, err: err };
        notes = m;
    }

    // ── THE VERBS ────────────────────────────────────────────
    function toggleRow(s) {
        confirmSsid = "";
        psk = "";
        cursorSsid = s;
        if (openSsid === s) {
            openSsid = "";
            rerank();
            takeFocus();
            return;
        }
        openSsid = s;
        reveal.restart();
    }

    // Closing a row hides the field that may be holding the keyboard, so
    // the panel takes it back -- after the row has closed, once the field
    // is gone, so nothing is left to hand it anywhere else. Why the panel
    // is an Item and not a FocusScope is at the top of this file.
    function takeFocus() { Qt.callLater(() => root.forceActiveFocus()); }

    function join(n) {
        if (n.stateChanging) return;
        const withKey = needsKey(n);
        // Join with an empty field is not a join -- NetworkManager would
        // only come back with "needs its password". The field gets the
        // keyboard instead.
        if (withKey && psk === "") { focusField.restart(); return; }
        // A key NetworkManager would refuse is refused HERE, before the
        // join drops the network you are on. → Wifi.keyProblem
        const problem = withKey ? Wifi.keyProblem(n, psk) : "";
        if (problem !== "") { setNote(n.name, problem, true); focusField.restart(); return; }
        setNote(n.name, "", false);
        // A remembered row has nothing to join yet. It reads Joining… with
        // Cancel, and onAllNetsChanged joins it the moment the scan finds it.
        if (n.ghost) { waitFor = n.name; return; }
        cancelled = flag(cancelled, n.name, false);
        returnTo = Wifi.active && Wifi.active !== n ? Wifi.active.name : "";
        if (!n.known) fresh = flag(fresh, n.name, true);
        if (withKey) n.connectWithPsk(psk);
        else n.connect();
    }

    // A JOIN THAT DID NOT HAPPEN PUTS YOU BACK, whether it was cancelled
    // or it failed. The radio has one association, so trying a network
    // left the one you were on; this activates it again. Asked for
    // explicitly, not left to NetworkManager's autoconnect -- which here
    // once chose HUAWEI_B628_FCF3, another saved network that wanted a
    // password. With nothing to go back to, a cancel stops the device
    // (`network.disconnect()` is a no-op on a join still waiting for its
    // password -- measured) and a failure leaves NetworkManager alone.
    //
    // And a first join that did not happen saves nothing: NetworkManager
    // wrote the profile when the join started, so a typo would leave a
    // saved network that can never join. `fresh` is cleared once the
    // profile is actually gone (onKnownChanged below), so the row stays
    // under Other the whole time. → saved()
    function giveUp(n, stopIfNowhere) {
        const back = returnTo !== n.name ? netNamed(returnTo) : null;
        returnTo = "";
        if (back) back.connect(); else if (stopIfNowhere) Wifi.stop();
        if (fresh[n.name]) { if (n.known) n.forget(); else fresh = flag(fresh, n.name, false); }
    }

    function cancel(n) {
        if (waitFor === n.name) { waitFor = ""; return; }
        cancelled = flag(cancelled, n.name, true);
        setNote(n.name, "", false);
        giveUp(n, true);
    }

    function forget(n) {
        confirmSsid = "";
        openSsid = "";
        needKey = flag(needKey, n.name, false);
        n.forget();
        takeFocus();
    }

    // Failure is said in the open box, in words, where the person who
    // pressed Join is already looking. nmcli's "Secrets were required,
    // but not provided" is NetworkManager explaining our own request
    // back to us; these are what it means.
    function failed(n, reason) {
        const s = n.name;
        if (cancelled[s]) { cancelled = flag(cancelled, s, false); return; }
        if (reason === ConnectionFailReason.NoSecrets) {
            if (!fresh[s]) needKey = flag(needKey, s, true);
            setNote(s, psk !== "" ? "Wrong password." : "This network needs its password.", true);
            psk = "";
        } else if (reason === ConnectionFailReason.WifiAuthTimeout) {
            setNote(s, "The network didn't answer.", true);
        } else if (reason === ConnectionFailReason.WifiNetworkLost) {
            setNote(s, "The network is out of range.", true);
        } else {
            setNote(s, "Couldn't join.", true);
        }
        giveUp(n, false);
        if (openSsid === s) focusField.restart();
    }

    // Joined: the network leaves the list for the card, so its box has
    // nothing left to say.
    function joined(n) {
        const s = n.name;
        setNote(s, "", false);
        fresh = flag(fresh, s, false);
        needKey = flag(needKey, s, false);
        if (openSsid === s) { openSsid = ""; psk = ""; rerank(); takeFocus(); }
    }

    // One listener per network, NOT per row: a row can be destroyed
    // mid-connect (see PANEL STATE) and the answer must still land.
    Instantiator {
        model: ScriptModel { values: Wifi.nets }
        delegate: Connections {
            required property var modelData
            target: modelData
            function onConnectionFailed(reason) { root.failed(modelData, reason); }
            function onConnectedChanged() { if (modelData.connected) root.joined(modelData); }
            function onKnownChanged() { if (!modelData.known) root.fresh = root.flag(root.fresh, modelData.name, false); }
        }
    }

    // ── THE CARD LEAVES LATE ─────────────────────────────────
    // Joining another network drops the one you are on first -- the radio
    // has one association -- so for the length of the attempt (a wrong
    // key is ~10 s, the handshake's timeout) nothing is connected. The
    // card used to vanish at once and come back after, and the list under
    // the pointer jumped up by the card's height and down again. Now the
    // card stays while the device is busy connecting or disconnecting,
    // and leaves only after 1.5 s of it being idle with nothing connected
    // -- which bridges the gap between a failed attempt and the rejoin of
    // the network you were on. It still ARRIVES at once, and a panel that
    // opens with nothing connected does not grow a card for an attempt.
    property bool cardUp: false
    property string lastActive: ""   // what the card said last; while it is held, not a row
    readonly property bool deviceBusy: Wifi.device !== null
        && (Wifi.device.state === ConnectionState.Connecting
            || Wifi.device.state === ConnectionState.Disconnecting)
    function syncCard() {
        if (Wifi.active) { cardUp = true; cardGrace.stop(); lastActive = Wifi.active.name; }
        else if (cardUp && !deviceBusy) cardGrace.restart();
    }
    onDeviceBusyChanged: syncCard()
    Timer { id: cardGrace; interval: 1500; onTriggered: if (!Wifi.active && !root.deviceBusy) root.cardUp = false }
    Connections {
        target: Wifi
        function onActiveChanged() { root.askDisconnect = false; root.syncCard(); }
    }

    // ── THE RADIO, AND THE BODY SWAP ─────────────────────────
    // The switch answers the press, not NetworkManager: `wantOn` flips
    // the instant it is pressed and the service catches up. If the
    // service never does -- rfkill, a denied call -- the reconcile puts
    // the switch back to the truth rather than leaving it lying.
    property bool wantOn: Wifi.radioOn
    property bool shownOn: true
    Connections {
        target: Wifi
        function onRadioOnChanged() { root.wantOn = Wifi.radioOn; }
    }
    Timer { id: reconcile; interval: 3000; onTriggered: root.wantOn = Wifi.radioOn }

    function toggleRadio() {
        wantOn = !wantOn;
        Wifi.setRadio(wantOn);
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
                root.openSsid = ""; root.confirmSsid = ""; root.psk = "";
                if (root.shownOn) searching.restart();   // a radio just on has scanned nothing yet
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
    // No hints are drawn for any of it -- a panel is not a place to
    // teach shortcuts (§5.6). ↑↓ move, Enter opens and closes a row,
    // Escape backs out one step at a time: the question, the row, then
    // the panel.
    Keys.onPressed: event => {
        if (event.key === Qt.Key_Escape) {
            if (askDisconnect) askDisconnect = false;
            else if (confirmSsid !== "") confirmSsid = "";
            else if (openSsid !== "") toggleRow(openSsid);
            else root.closeRequested();
            event.accepted = true;
        } else if ((event.key === Qt.Key_Down || event.key === Qt.Key_Up) && shownOn && order.length > 0) {
            const i = order.indexOf(cursorSsid);
            const d = event.key === Qt.Key_Down ? 1 : -1;
            const j = i < 0 ? (d > 0 ? 0 : order.length - 1)
                            : Math.max(0, Math.min(order.length - 1, i + d));
            cursorSsid = order[j];
            reveal.restart();
            // An arrow is list navigation even from inside the field: the
            // keyboard comes back to the list, or Enter would join the open
            // row while the cursor sits on another one.
            if (!root.activeFocus) root.forceActiveFocus();
            event.accepted = true;
        } else if ((event.key === Qt.Key_Return || event.key === Qt.Key_Enter) && cursorSsid !== "" && shownOn) {
            toggleRow(cursorSsid);
            event.accepted = true;
        }
    }

    // ═══ THE HEAD ═══════════════════════════════════════════
    Item {
        id: head
        x: root.pad
        y: 15
        width: root.width - root.pad * 2
        height: 22

        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: "Wi-Fi"
            color: root.txt
            font.family: Theme.fontSans
            font.pixelSize: 14
            font.weight: Font.DemiBold
            font.letterSpacing: 0.14
        }

        Switch {
            id: sw
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

        // ── OFF ──────────────────────────────────────────────
        Column {
            visible: !root.shownOn
            anchors.horizontalCenter: parent.horizontalCenter
            y: 42 + (387 - height) / 2
            spacing: 7

            Icon {
                anchors.horizontalCenter: parent.horizontalCenter
                name: "wifi-off"
                size: 20
                color: root.txt2
                // 0.5 in the mock-up, where the glyph was a solid font
                // shape. This one draws its arcs at 35% already, and at
                // half again they vanished and left a lone slash.
                opacity: 0.8
            }
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: "Wi-Fi is off."
                color: root.txt2
                font.family: Theme.fontMono
                font.pixelSize: 12
            }
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: "Turn Wi-Fi on to see networks."
                color: root.txt2
                opacity: 0.75
                font.family: Theme.fontMono
                font.pixelSize: 11
            }
        }

        // ── ON ───────────────────────────────────────────────
        Item {
            anchors.fill: parent
            visible: root.shownOn

            // With no connection the card is NOT DRAWN -- an empty
            // readout reads as a control you are allowed to press -- and
            // the list takes the space.
            Card {
                id: card
                x: root.pad
                y: 46
                visible: root.cardUp
            }

            Text {
                visible: !root.cardUp
                x: root.pad
                y: 40
                text: "Not connected"
                color: root.txt2
                font.family: Theme.fontMono
                font.pixelSize: 11
            }

            Flickable {
                id: list
                x: root.pad
                y: card.visible ? card.y + card.height + 13 : 70
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

                    Section { text: "Known networks"; visible: root.knownNets.length > 0 }
                    Item { width: 1; height: 6; visible: root.knownNets.length > 0 }
                    Repeater {
                        id: knownRep
                        model: ScriptModel { values: root.knownNets }
                        delegate: NetRow {}
                    }
                    Item { width: 1; height: 13; visible: root.knownNets.length > 0 }

                    // While the list is still filling, the Scan row already
                    // says "Looking for networks…", so an empty Other is not
                    // drawn at all -- a label over nothing reads as broken.
                    Section { text: "Other networks"; visible: root.otherNets.length > 0 || !root.filling }
                    Item { width: 1; height: 6; visible: root.otherNets.length > 0 || !root.filling }
                    Repeater {
                        id: otherRep
                        model: ScriptModel { values: root.otherNets }
                        delegate: NetRow {}
                    }

                    // Said once the scan is over, not left blank: "there is
                    // nothing here" must not look like "still scanning".
                    Text {
                        visible: root.otherNets.length === 0 && !root.filling
                        x: 9
                        height: 36
                        verticalAlignment: Text.AlignVCenter
                        text: "No other networks in range."
                        color: root.txt2
                        font.family: Theme.fontMono
                        font.pixelSize: 11
                    }
                }
            }

            // WHAT RESCAN DID, said where it was pressed: one line for 4 s
            // once the scan is over ("rescan button doesn't indicate if
            // something was rescanned or not", 2026-09-13). Not drawn with
            // the radio off -- it goes with the body, and the switch is
            // what turns the radio on.
            ScanRow {
                x: root.pad
                y: root.height - 14 - height
                width: root.width - root.pad * 2
                label: "Scan for new networks"
                busyLabel: "Looking for networks…"
                busyGlyph: "wifi"
                busy: root.filling
                note: Wifi.scanResult
                noteErr: Wifi.scanResult === "Scan failed"
                onScan: Wifi.rescan(true)
            }

            // The thumb. Drawn only when there is something to scroll,
            // in the gutter the mock-up gave it, outside the rows' box.
            Rectangle {
                visible: list.contentHeight > list.height + 1
                x: list.x + list.width + 7
                y: list.y + list.visibleArea.yPosition * list.height
                width: 5
                height: Math.max(20, list.visibleArea.heightRatio * list.height)
                radius: 3
                color: Qt.rgba(1, 1, 1, 0.14)
            }
        }
    }

    Timer { id: searching; interval: 4000 }
    readonly property bool filling: searching.running || Wifi.scanBusy

    // ── AN OPENED ROW SCROLLS INTO VIEW ──────────────────────
    // Round nine's bug: open the last network and its box lands below
    // the fold, and you scroll to find the thing you just asked for. So
    // the list glides until the box's bottom sits 2 px (its own margin)
    // inside the list -- or, if the box is taller than the list, its top
    // does. Rows that are already in view do not move at all.
    //
    // A timer and not a direct call because the box has to have been
    // laid out at its open height before it can be measured.
    Timer {
        id: reveal
        interval: 1
        onTriggered: {
            col.forceLayout();
            let item = null;
            for (const rep of [knownRep, otherRep])
                for (let i = 0; i < rep.count; i++) {
                    const it = rep.itemAt(i);
                    if (it && it.ssid === root.cursorSsid) item = it;
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

    function focusFieldLater() { focusField.restart(); }
    Timer {
        id: focusField
        interval: 1
        onTriggered: {
            for (const rep of [knownRep, otherRep])
                for (let i = 0; i < rep.count; i++) {
                    const it = rep.itemAt(i);
                    if (it && it.ssid === root.openSsid) it.focusField();
                }
        }
    }

    // ═══ PIECES ═════════════════════════════════════════════

    // Section, Btn and Switch are their own files now (Section.qml,
    // Btn.qml, Switch.qml): Sound and Bluetooth use the same kit.

    // THE WI-FI FAN. Icons.qml's "wifi" verbatim -- three arcs and the
    // dot -- with the arcs the signal has not earned drawn at 26%. Every
    // arc is drawn at every reading, so the ink is one width and the SSID
    // column cannot move. It is strokes, not the solid wedge network.md
    // retired. Cropped to the drawing's own ink (0.8 2.6 14.4 11.8) so
    // `size` px wide means that many px of fan: 16 in a row, 20 on the card.
    component Fan: Item {
        id: f
        property real sig: 0
        property real size: 16
        property color ink: Qt.rgba(210 / 255, 216 / 255, 215 / 255, 1)
        readonly property int lit: sig >= 0.75 ? 3 : sig >= 0.5 ? 2 : sig >= 0.25 ? 1 : 0
        readonly property real k: size / 14.4
        readonly property color dimInk: Qt.alpha(ink, 0.26)
        width: size
        height: 11.8 * k

        Shape {
            preferredRendererType: Shape.CurveRenderer
            transformOrigin: Item.TopLeft
            scale: f.k
            x: -0.8 * f.k
            y: -2.6 * f.k
            width: 16
            height: 16
            ShapePath {
                strokeColor: f.lit >= 1 ? f.ink : f.dimInk
                strokeWidth: 1.4; fillColor: "transparent"; capStyle: ShapePath.RoundCap
                PathSvg { path: "M6.4 11.1a3.5 3.5 0 0 1 3.2 0" }
            }
            ShapePath {
                strokeColor: f.lit >= 2 ? f.ink : f.dimInk
                strokeWidth: 1.4; fillColor: "transparent"; capStyle: ShapePath.RoundCap
                PathSvg { path: "M4 8.4a7.2 7.2 0 0 1 8 0" }
            }
            ShapePath {
                strokeColor: f.lit >= 3 ? f.ink : f.dimInk
                strokeWidth: 1.4; fillColor: "transparent"; capStyle: ShapePath.RoundCap
                PathSvg { path: "M1.6 5.6a11 11 0 0 1 12.8 0" }
            }
            ShapePath {
                strokeWidth: -1
                fillColor: f.ink
                PathSvg { path: "M 7.25 13.4 A 0.75 0.75 0 1 0 8.75 13.4 A 0.75 0.75 0 1 0 7.25 13.4 Z" }
            }
        }
    }

    // ── THE CONNECTED CARD ───────────────────────────────────
    // Connected · the SSID, and the signal on the right where the download
    // figure was · a hairline · band, security and address as labelled
    // columns, and Disconnect at the end of that line. The meter, its bars
    // and "last 60s" were removed 2026-09-15; the link rate went with them
    // (it was the "866 Mb/s link" nobody could read as a speed).
    //
    // While the card is held through a join (THE CARD LEAVES LATE) it
    // says what is happening instead -- "Joining" and the network being
    // tried, or "Not connected" for the 1.5 s before it goes -- and draws
    // no reading: a signal and an address for a connection that does not
    // exist would be a reading nobody took.
    //
    // DISCONNECT ASKS ONCE, IN PLACE -- Forget's grammar, the question in
    // the line it replaces, so nothing moves.
    component Card: Rectangle {
        id: c
        width: root.width - root.pad * 2
        height: 108
        radius: 11
        color: Theme.panelCard
        border.width: 1
        border.color: root.edgeOnCard

        readonly property var net: Wifi.active
        readonly property var joining: net ? null : Wifi.nets.find(n => n.state === ConnectionState.Connecting) || null

        Rectangle { visible: c.net !== null; x: 13; y: 16.5; width: 5; height: 5; radius: 2.5; color: Theme.accent }
        Text {
            x: c.net ? 24 : 13
            y: 12
            height: 14
            verticalAlignment: Text.AlignVCenter
            text: c.net ? "Connected" : c.joining ? "Joining" : "Not connected"
            color: c.net ? Theme.accent : root.txt2
            font.family: Theme.fontCaps
            font.pixelSize: root.capsPx
            font.weight: Theme.capsWeight
            font.letterSpacing: root.capsTrack
            font.capitalization: Font.AllUppercase
        }
        Text {
            x: 13
            y: 29
            width: (signal.visible ? signal.x - 16 : c.width - 13) - x
            elide: Text.ElideRight
            text: c.net ? c.net.name : c.joining ? c.joining.name : root.lastActive
            color: c.net ? root.txt : root.txt2
            font.family: Theme.fontSans
            font.pixelSize: 17
            font.letterSpacing: -0.34
        }

        // The signal: the list's own fan, larger, and the percent beside it.
        Row {
            id: signal
            visible: c.net !== null
            x: c.width - 13 - width
            y: 21
            height: 24
            spacing: 8
            Fan {
                anchors.verticalCenter: parent.verticalCenter
                size: 20
                sig: c.net ? c.net.signalStrength : 0
            }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: c.net ? Math.round(c.net.signalStrength * 100) + "%" : ""
                color: root.txt
                font.family: Theme.fontMono
                font.pixelSize: 15
                font.letterSpacing: -0.3
            }
        }

        Rectangle {
            visible: c.net !== null
            x: 13
            y: 59
            width: c.width - 26
            height: 1
            color: root.edge
        }

        // The details. A column is as wide as its label or its value,
        // whichever is longer, and one that has nothing to say (no band
        // read yet, DHCP still out) is not drawn.
        Row {
            visible: c.net !== null && !root.askDisconnect
            x: 13
            y: 69
            spacing: 30
            Repeater {
                model: [["Band", Wifi.band],
                        ["Security", c.net ? Wifi.security(c.net) : ""],
                        ["Address", Wifi.address]].filter(f => f[1] !== "")
                Column {
                    required property var modelData
                    spacing: 3
                    Text {
                        text: modelData[0]
                        color: root.txt2
                        font.family: Theme.fontCaps
                        font.pixelSize: root.capsPx
                        font.weight: Theme.capsWeight
                        font.letterSpacing: root.capsTrack
                        font.capitalization: Font.AllUppercase
                    }
                    Text {
                        text: modelData[1]
                        color: root.txt
                        font.family: Theme.fontMono
                        font.pixelSize: 11
                    }
                }
            }
        }
        Btn {
            visible: c.net !== null && !root.askDisconnect
            x: c.width - 13 - width
            y: 70
            label: "Disconnect"
            kind: "ghost"
            dim: true
            onClicked: root.askDisconnect = true
        }

        Item {
            visible: c.net !== null && root.askDisconnect
            x: 13
            y: 70
            width: c.width - 26
            height: 30
            Text {
                anchors.left: parent.left
                anchors.right: leave.left
                anchors.rightMargin: 8
                anchors.verticalCenter: parent.verticalCenter
                elide: Text.ElideRight
                textFormat: Text.StyledText
                text: "Disconnect from <font color=\"" + root.txt + "\">"
                      + (c.net ? c.net.name : "").replace(/&/g, "&amp;").replace(/</g, "&lt;")
                      + "</font>?"   // a 32-byte SSID still fits beside both buttons; a second sentence did not
                color: root.txt2
                font.family: Theme.fontMono
                font.pixelSize: 11
            }
            // CANCEL IS WHERE DISCONNECT WAS. Buttons act on press, so the
            // second click of a double-click lands on whatever replaced the
            // first; with Disconnect in that spot the question was skipped.
            Btn {
                id: leave
                anchors.right: stay.left
                anchors.rightMargin: 8
                anchors.verticalCenter: parent.verticalCenter
                kind: "danger"
                label: "Disconnect"
                onClicked: { root.askDisconnect = false; Wifi.stop(); }
            }
            Btn {
                id: stay
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                kind: "quiet"
                label: "Cancel"
                onClicked: root.askDisconnect = false
            }
        }
    }

    // ── ONE ROW, AND THE BOX IT GROWS INTO ───────────────────
    component NetRow: Item {
        id: r
        required property var modelData
        readonly property var net: modelData
        readonly property string ssid: net.name
        readonly property bool isOpen: root.openSsid === ssid && root.shownOn
        readonly property bool isCursor: root.cursorSsid === ssid
        readonly property bool wantsKey: root.needsKey(net)
        readonly property bool busy: net.stateChanging || net.state === ConnectionState.Connecting || root.waitFor === ssid
        readonly property var note: root.notes[ssid]
        readonly property bool asking: root.confirmSsid === ssid

        function focusField() { if (wantsKey) field.forceActiveFocus(); }

        onIsOpenChanged: if (isOpen && wantsKey) root.focusFieldLater()
        onWantsKeyChanged: if (isOpen && wantsKey) root.focusFieldLater()
        // Re-created while open (it moved between Known and Other): the
        // field is new, so it is given the keyboard again.
        Component.onCompleted: if (isOpen && wantsKey) root.focusFieldLater()

        width: parent ? parent.width : 0
        height: isOpen ? box.height + 4 : 36

        Rectangle {
            id: box
            y: r.isOpen ? 2 : 0
            width: r.width
            height: r.isOpen ? 36 + det.height : 36
            // Closed: flush -- nothing until the pointer or the cursor is
            // on it, and then the same 7 px corner for both: the hover was
            // a square band under a rounded cursor, two objects for one
            // row (Datum Panels, Hover: Rounded, 2026-09-16). Open: the card-box, one outline, and inside it the
            // cursor belongs to the BOX (a brighter edge), because a ring
            // on the row plus the box's own edge is two outlines around
            // one object.
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
                onPressed: root.toggleRow(r.ssid)
            }

            Fan {
                x: 9
                y: (36 - height) / 2
                sig: r.net.signalStrength
            }

            Text {
                x: 34
                anchors.verticalCenter: hit.verticalCenter
                width: right.x - 9 - x
                elide: Text.ElideRight
                text: r.ssid
                color: root.txt
                font.family: Theme.fontSans
                font.pixelSize: 13
            }

            Row {
                id: right
                anchors.right: parent.right
                anchors.rightMargin: 9
                anchors.verticalCenter: hit.verticalCenter
                spacing: 9

                Icon {
                    visible: Wifi.locked(r.net)
                    anchors.verticalCenter: parent.verticalCenter
                    name: "lock-fill"
                    size: 13
                    color: root.txt2
                }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    width: 29
                    horizontalAlignment: Text.AlignRight
                    text: Math.round(r.net.signalStrength * 100) + "%"
                    color: root.txt2
                    font.family: Theme.fontMono
                    font.pixelSize: 11
                }
                Icon {
                    anchors.verticalCenter: parent.verticalCenter
                    name: "chev"
                    size: 14
                    color: root.txt2
                    rotation: r.isOpen ? 180 : 0
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
                // Forget under Join is a quiet button with its own 5 px of
                // air, so the box's bottom margin gives that back.
                bottomPadding: actions.visible && forgetBtn.visible && !r.asking ? 6 : 12

                // ONE LINE, AND ONLY WHAT THE ROW CANNOT SAY. The row is
                // already under Known (saved) and already carries a
                // padlock (locked), so the line is the security FLAVOUR on
                // a network you are about to type a key for -- or, when
                // there is one, what just happened.
                Text {
                    id: meta
                    readonly property bool status: r.note !== undefined || r.busy
                    visible: status || !root.saved(r.net)
                    width: parent.width
                    elide: Text.ElideRight
                    text: r.note !== undefined ? r.note.text
                        : r.busy ? "Joining…"
                        : Wifi.security(r.net)
                    color: r.note !== undefined && r.note.err ? Theme.danger : root.txt2
                    font.family: status ? Theme.fontMono : Theme.fontCaps
                    font.pixelSize: status ? 11 : root.capsPx
                    font.weight: status ? Font.Normal : Theme.capsWeight
                    font.letterSpacing: status ? 0 : root.capsTrack
                    font.capitalization: status ? Font.MixedCase : Font.AllUppercase
                }

                // The key, and Join at the end of its line -- not under it.
                Row {
                    visible: r.wantsKey && !r.asking
                    width: parent.width
                    height: 37
                    spacing: 8

                    Rectangle {
                        width: parent.width - 8 - joinKey.width
                        height: parent.height
                        radius: 8
                        color: Theme.panelWell

                        TextInput {
                            id: field
                            x: 12
                            width: parent.width - 24
                            anchors.verticalCenter: parent.verticalCenter
                            clip: true
                            echoMode: TextInput.Password
                            passwordCharacter: "•"
                            text: root.psk
                            color: root.txt
                            selectionColor: Qt.alpha(Theme.accent, 0.35)
                            selectedTextColor: root.txt
                            font.family: Theme.fontMono
                            font.pixelSize: 12
                            selectByMouse: true
                            onTextEdited: {
                                root.psk = text;
                                if (r.note !== undefined && r.note.err) root.setNote(r.ssid, "", false);
                            }
                            // Enter is TAKEN here, not left to onAccepted: TextInput
                            // emits accepted and then ignores the key, so it went on
                            // to the panel's Enter -- which closed the row the join
                            // had just started in (measured 2026-09-15: the error
                            // landed on a box that was no longer open).
                            Keys.onReturnPressed: event => { if (text !== "" && !r.busy) root.join(r.net); event.accepted = true; }
                            Keys.onEnterPressed: event => { if (text !== "" && !r.busy) root.join(r.net); event.accepted = true; }
                            Keys.onEscapePressed: event => { root.toggleRow(r.ssid); event.accepted = true; }

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
                                text: "Password"
                                color: root.txt2
                                font: field.font
                            }
                        }
                    }

                    // While a join is in flight the button's action is to
                    // stop it -- a button names what pressing it does, never
                    // what the app is busy with.
                    Btn {
                        id: joinKey
                        kind: "solid"
                        label: r.busy ? "Cancel" : "Join"
                        implicitHeight: 37
                        onClicked: r.busy ? root.cancel(r.net) : root.join(r.net)
                    }
                }

                // Join over Forget, stacked, full width. Emitted in the
                // order you read them; Forget is quiet because Join is solid.
                Column {
                    id: actions
                    visible: !r.asking && (!r.wantsKey || root.saved(r.net))
                    width: parent.width
                    spacing: 4

                    Btn {
                        visible: !r.wantsKey
                        width: parent.width
                        kind: "solid"
                        label: r.busy ? "Cancel" : "Join"
                        onClicked: r.busy ? root.cancel(r.net) : root.join(r.net)
                    }
                    Btn {
                        id: forgetBtn
                        visible: root.saved(r.net)
                        width: parent.width
                        implicitHeight: 26
                        kind: "quiet"
                        label: "Forget"
                        onClicked: root.confirmSsid = r.ssid
                    }
                }

                // FORGET ASKS ONCE, IN PLACE. It is the only thing in the
                // panel you cannot take back from the panel, so the question
                // replaces the buttons -- nothing new appears elsewhere and
                // nothing below the box moves further than the box does.
                Item {
                    visible: r.asking
                    width: parent.width
                    height: 30

                    Text {
                        anchors.left: parent.left
                        anchors.right: dangerBtn.left
                        anchors.rightMargin: 8
                        anchors.verticalCenter: parent.verticalCenter
                        elide: Text.ElideRight
                        textFormat: Text.StyledText
                        text: "Forget <font color=\"" + root.txt + "\">" + r.ssid.replace(/&/g, "&amp;").replace(/</g, "&lt;")
                              + "</font>? The saved password goes with it."
                        color: root.txt2
                        font.family: Theme.fontMono
                        font.pixelSize: 11
                    }
                    // The act, then Cancel at the end -- the Disconnect
                    // question's order, where Cancel has to be last. → Card
                    Btn {
                        id: dangerBtn
                        anchors.right: cancelBtn.left
                        anchors.rightMargin: 8
                        anchors.verticalCenter: parent.verticalCenter
                        kind: "danger"
                        label: "Forget"
                        onClicked: root.forget(r.net)
                    }
                    Btn {
                        id: cancelBtn
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        kind: "quiet"
                        label: "Cancel"
                        onClicked: root.confirmSsid = ""
                    }
                }
            }
        }
    }
}
