// ═══════════════════════════════════════════════════════════════
// THE SEARCH PANEL — what the island's body holds for the mark.
//
// 620 x 438 under the bar's 38, the same body Wi-Fi and Sound grow into,
// with no background, blur or edge of its own. → WifiPanel.qml
//
// Built from Datum Panels, Search round one, with the values off the
// user's dock screenshots (2026-09-16); geometry read off the mock-up's
// computed boxes, half pixels of type rounded up:
//   Kit         Flush rows · Plain cursor · Rounded hover · Sans + mono · motion on
//   Field       in the panel · title size · no clear button · a category is a chip in the field
//   Categories  tabs with All · Alt + digit printed · ghost look
//   Results     Recent, then All apps · app icon · generic name only when it matched ·
//               matched letters bold · Enter on the cursor row, and the row says what it does
//   Alt hint    "Show keys" at the end of the tabs toggles one line of keys under them
//               (the user's pick when asked, 2026-09-16; an (i) until 2026-09-18)
//
// It is the one panel you type into before you look, so the FIELD HAS THE
// KEYBOARD from the frame the panel opens, and every key is handled here:
// ↑↓ move, Enter opens the cursor row, Esc closes, Alt+1…6 pick a
// category (again to drop it), Backspace on an empty field takes the
// category chip off. A click on a row opens it; a click on a tab filters.
//
// ── WHAT MOVES ───────────────────────────────────────────────
// Gated by the motion skill: nothing of its own but the caret. The open is the body's.
// A launcher is opened hundreds of times a day, and the list changes on
// every key -- a list that animated to its new order would always be
// showing the previous one. Row hover and tab colour take the kit's
// 130 ms; the caret blinks -- see the field.
// ═══════════════════════════════════════════════════════════════

import QtQuick

Item {
    id: root

    property bool open: false
    signal closeRequested()
    // Any key, a tab, or the open: the caret goes solid and starts over.
    signal woke()

    width: Theme.widthNormal
    height: Theme.panelDepth

    readonly property int pad: 17
    readonly property color txt: Theme.textPrimary
    readonly property color txt2: Theme.textDim
    // The mock-up's outline over the cursor's fill, composited -- see
    // WifiPanel.qml, OUTLINES ON A FILL.
    readonly property color ringOnCursor: Qt.rgba(1, 1, 1, 0.186)

    // The chip in the field. A typed `:dev` filters too, and wins while it
    // is there; a tab or Alt+digit takes the typed token out and sets this.
    property string cat: ""
    property int cursor: 0
    // The keys line ("Show keys"). Not reset on open: it is a preference, not a
    // search, and it stays how you left it until the bar restarts.
    property bool hints: false

    readonly property var parsed: Apps.splitToken(field.text)
    readonly property string activeCat: parsed.tok !== "" ? parsed.tok : cat
    readonly property bool idle: parsed.text === "" && activeCat === ""

    // ── THE LIST ─────────────────────────────────────────────
    // One array of entries, labels and rows mixed, because a ListView has
    // one model. `k` is a row's index among rows only -- what the cursor
    // counts in, so the labels are never a stop for ↑↓.
    readonly property var ranked: Apps.rank(parsed.text, activeCat)
    readonly property var entries: {
        const out = [];
        let k = 0;
        const push = r => out.push({ label: "", r: r, k: k++ });
        if (idle) {
            // Recent is your five most-used; All apps is every app A–Z, the
            // five included, so the second group is a list you can scan.
            const recent = ranked.filter(r => Apps.use(r.app) > 0).slice(0, 5);
            if (recent.length > 0) {
                out.push({ label: "Recent", first: true });
                recent.forEach(push);
            }
            out.push({ label: "All apps", first: recent.length === 0 });
            ranked.slice().sort((x, y) => x.app.name.toLowerCase() < y.app.name.toLowerCase() ? -1 : 1).forEach(push);
        } else {
            ranked.forEach(push);
        }
        return out;
    }
    readonly property var rows: entries.filter(e => e.label === "")

    function reset() {
        field.text = "";
        cat = "";
        cursor = 0;
        list.positionViewAtBeginning();
    }

    onOpenChanged: {
        if (open) {
            reset();
            field.forceActiveFocus();
            woke();
            Apps.opened();
        }
    }

    // A changed query or filter starts the list at its top.
    function refiltered() {
        cursor = 0;
        list.positionViewAtBeginning();
    }

    function pickCat(tok) {
        const had = parsed.tok !== "";
        if (had) field.text = field.text.replace(/:[A-Za-z]*/g, " ").replace(/\s{2,}/g, " ").trim();
        cat = (!had && cat === tok) ? "" : tok;
        refiltered();
        woke();
    }

    function openRow(k) {
        const e = rows[k];
        if (!e) return;
        Apps.launch(e.r.app);
        root.closeRequested();
    }

    function moveCursor(d) {
        if (rows.length === 0) return;
        cursor = Math.max(0, Math.min(rows.length - 1, cursor + d));
        // The first row of a group brings its label with it.
        const i = entries.indexOf(rows[cursor]);
        if (i > 0 && entries[i - 1].label !== "") list.positionViewAtIndex(i - 1, ListView.Contain);
        list.positionViewAtIndex(i, ListView.Contain);
    }

    function verb(app) {
        const ws = Apps.windows[app.file];
        return ws ? "Go to workspace " + ws : "Open";
    }

    // ═══ THE FIELD IS THE HEAD ══════════════════════════════
    // There is no title row: an empty field says what the panel is, and a
    // typed one is the title.
    Item {
        id: head
        x: root.pad
        y: 15
        width: root.width - root.pad * 2
        height: 28

        Icon {
            x: 2
            anchors.verticalCenter: parent.verticalCenter
            name: "search"
            size: 17
            color: root.txt2
        }

        // A CATEGORY IS A CHIP IN THE FIELD, and what you type goes after
        // it. eww wrote `:media` into a GtkEntry that left the caret in
        // front of it, and `kit` landed as `kit:media` (launcher.md).
        Rectangle {
            id: chip
            visible: root.cat !== "" && root.parsed.tok === ""
            x: 29
            anchors.verticalCenter: parent.verticalCenter
            width: chipText.implicitWidth + 16
            height: 19
            radius: 6
            color: Qt.alpha(Theme.accent, 0.15)
            Text {
                id: chipText
                anchors.centerIn: parent
                text: Apps.catLabel(root.cat)
                color: Theme.accent
                font.family: Theme.fontMono
                font.pixelSize: 11
                font.letterSpacing: 11 * 0.04
            }
        }

        TextInput {
            id: field
            x: chip.visible ? chip.x + chip.width + 8 : 29
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width - x - infoBtn.width
            color: root.txt
            font.family: Theme.fontSans
            font.pixelSize: 16
            selectionColor: Qt.alpha(Theme.accent, 0.35)
            selectedTextColor: root.txt
            clip: true
            focus: true

            // THE CARET BLINKS, and a custom delegate does not do that on
            // its own: Qt only blinks its default caret, so this one was
            // lit solid (measured, 16 samples over 1.6 s). The field has
            // the keyboard the whole time the panel is open, so the blink
            // is what says "type here". On/off, never a fade -- the accent
            // does not pulse (motion skill). Solid while you type or
            // arrow, and solid again after ~10 s untouched, the way GTK
            // stops (gtk-cursor-blink-timeout), so an open panel does not
            // nag. The rate is the platform's; 0 there means no blink.
            cursorDelegate: Rectangle {
                id: caret
                width: 1
                color: Theme.accent
                visible: field.cursorVisible && lit
                property bool lit: true
                property int flips: 0
                Timer {
                    id: blink
                    interval: Qt.styleHints.cursorFlashTime / 2
                    repeat: true
                    // An even count, so it always stops lit.
                    running: field.cursorVisible && Anim.enabled && interval > 0 && caret.flips < 20
                    onTriggered: { caret.lit = !caret.lit; caret.flips++; }
                }
                Connections {
                    target: root
                    function onWoke() { caret.lit = true; caret.flips = 0; blink.restart(); }
                }
            }

            onTextChanged: root.refiltered()

            Keys.onPressed: event => {
                root.woke();
                const k = event.key;
                // Alt+1…6 is the number row's KEY, not the digit it types:
                // on AZERTY that row types & é " ' ( -, and Alt+3 put a `"`
                // in the field (measured with the rig's keyboard set to fr).
                // Wayland's scan code is the evdev code + 8, so KEY_1…KEY_6
                // are 10…15 on every layout.
                const sc = event.nativeScanCode;
                const n = k >= Qt.Key_1 && k <= Qt.Key_6 ? k - Qt.Key_1
                        : sc >= 10 && sc <= 15 ? sc - 10 : -1;
                if ((event.modifiers & Qt.AltModifier) && n >= 0) {
                    root.pickCat(Apps.cats[n].tok);
                    event.accepted = true;
                } else if (k === Qt.Key_Escape) {
                    root.closeRequested();
                    event.accepted = true;
                } else if (k === Qt.Key_Down || k === Qt.Key_Up) {
                    root.moveCursor(k === Qt.Key_Down ? 1 : -1);
                    event.accepted = true;
                } else if (k === Qt.Key_PageDown || k === Qt.Key_PageUp) {
                    root.moveCursor(k === Qt.Key_PageDown ? 8 : -8);
                    event.accepted = true;
                } else if (k === Qt.Key_Return || k === Qt.Key_Enter) {
                    root.openRow(root.cursor);
                    event.accepted = true;
                } else if (k === Qt.Key_Backspace && field.text === "" && root.cat !== "") {
                    root.cat = "";
                    root.refiltered();
                    event.accepted = true;
                }
            }
        }

        // The placeholder sits 8 px after the caret, so the caret reads as
        // the start of the field rather than as the first letter of it.
        Text {
            visible: field.text === "" && !chip.visible
            x: field.x + 8
            anchors.verticalCenter: parent.verticalCenter
            text: "Search apps"
            color: root.txt2
            font.family: Theme.fontSans
            font.pixelSize: 16
        }
    }
    Rectangle {
        x: root.pad
        y: 54
        width: root.width - root.pad * 2
        height: 1
        color: Theme.glassEdge
    }

    // ═══ THE CATEGORIES — TABS WITH ALL ═════════════════════
    // The lit tab is the filter in effect, whichever way it was set: a
    // click, Alt+digit, or `:dev` typed in the field.
    //
    // The band IS the space between the field's rule (54) and the tabs'
    // own (94), and the words sit in its middle. At y 67 / 28 tall they
    // read 23 px under the upper rule and 17 over the lower one, which is
    // what looked out of place; the lit tab's underline still lands on
    // the lower rule.
    Row {
        x: root.pad
        y: 55
        height: 39

        Tab { label: "All"; digit: ""; on: root.activeCat === ""; onPicked: { if (root.activeCat !== "") root.pickCat(root.activeCat); } }
        Repeater {
            model: Apps.cats
            delegate: Tab {
                required property var modelData
                required property int index
                label: modelData.label
                digit: String(index + 1)
                on: root.activeCat === modelData.tok
                onPicked: { if (!on) root.pickCat(modelData.tok); }
            }
        }
    }

    // ═══ THE KEYS, ON ASK ═══════════════════════════════════
    // The Wi-Fi spec's rule is that a panel does not teach its shortcuts,
    // and Alt+digit is the one here nothing on screen explains: the tabs
    // print the digit but not the Alt. So the line exists, and is off
    // until asked for.
    //
    // Asked for by WORDS. It was a 13 px filled (i) alone at the end of
    // the tabs: too small to read as anything, and unlike everything else
    // on the row ("i can't see what it is", 2026-09-18). In the tabs' own
    // caps it read as a seventh category, so it sits at the empty end of
    // the field's line instead, in the mono the rows' "Open" is set in --
    // the panel's word for an action -- with its right edge on theirs.
    // It says what pressing does, so it swaps rather than turning mint:
    // the line appearing is the state.
    Item {
        id: infoBtn
        x: root.width - root.pad - width
        y: head.y
        width: keysWord.implicitWidth + 18
        height: head.height
        Text {
            id: keysWord
            anchors.centerIn: parent
            text: root.hints ? "Hide keys" : "Show keys"
            color: im.containsMouse ? root.txt : root.txt2
            font.family: Theme.fontMono
            font.pixelSize: 11
            font.letterSpacing: 11 * 0.03
            Behavior on color { enabled: Anim.enabled; ColorAnimation { duration: Anim.ms(Anim.hover) } }
        }
        MouseArea {
            id: im
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onPressed: root.hints = !root.hints
        }
    }
    Rectangle {
        x: root.pad
        y: 94
        width: root.width - root.pad * 2
        height: 1
        color: Theme.glassEdge
    }
    Text {
        visible: root.hints
        x: root.pad + 9
        y: 101
        height: 22
        verticalAlignment: Text.AlignVCenter
        text: "alt+1–6 category · ↑↓ move · enter open · esc close"
        color: root.txt2
        font.family: Theme.fontMono
        font.pixelSize: 11
    }

    // ═══ THE RESULTS ════════════════════════════════════════
    ListView {
        id: list
        x: root.pad
        y: root.hints ? 123 : 101
        width: root.width - root.pad * 2
        height: root.height - 14 - y
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        model: root.entries
        delegate: Loader {
            required property var modelData
            width: ListView.view.width
            sourceComponent: modelData.label !== "" ? labelComp : rowComp
        }
    }

    Text {
        visible: root.rows.length === 0 && Apps.list.length > 0
        x: list.x
        y: list.y
        width: list.width
        height: list.height
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
        text: "No app matches “" + root.parsed.text + "”"
              + (root.activeCat !== "" ? " in " + Apps.catLabel(root.activeCat) : "") + "."
        color: root.txt2
        font.family: Theme.fontMono
        font.pixelSize: 12
    }

    // The thumb, drawn only when there is something to scroll, in the
    // gutter right of the content -- WifiPanel.qml's, at the same place.
    Rectangle {
        visible: list.contentHeight > list.height + 1
        x: list.x + list.width + 7
        y: list.y + list.visibleArea.yPosition * list.height
        width: 5
        height: Math.max(20, list.visibleArea.heightRatio * list.height)
        radius: 3
        color: Qt.rgba(1, 1, 1, 0.14)
    }

    // ═══ PIECES ═════════════════════════════════════════════

    Component {
        id: labelComp
        Item {
            height: (parent.modelData.first ? 6 : 13) + 14 + 6
            Section {
                y: parent.parent.modelData.first ? 6 : 13
                width: parent.width
                text: parent.parent.modelData.label
            }
        }
    }

    Component {
        id: rowComp
        AppRow { entry: parent.modelData }
    }

    // A tab: the digit Alt takes, then the word. The digit is printed at
    // half the word's ink, so the word is what you read.
    component Tab: Item {
        id: t
        property string label: ""
        property string digit: ""
        property bool on: false
        signal picked()
        width: tr.implicitWidth + 20
        height: 39

        Row {
            id: tr
            x: 10
            anchors.verticalCenter: parent.verticalCenter
            spacing: 5
            Text {
                visible: t.digit !== ""
                anchors.baseline: word.baseline
                text: t.digit
                color: word.color
                opacity: 0.5
                font.family: Theme.fontMono
                font.pixelSize: 10
            }
            Text {
                id: word
                text: t.label
                color: t.on ? Theme.accent : tm.containsMouse ? root.txt : root.txt2
                font.family: Theme.fontCaps
                font.pixelSize: 10
                font.weight: Theme.capsWeight
                font.letterSpacing: Theme.capsTrack
                font.capitalization: Font.AllUppercase
                Behavior on color { enabled: Anim.enabled; ColorAnimation { duration: Anim.ms(Anim.hover) } }
            }
        }
        Rectangle {
            visible: t.on
            x: 9
            y: parent.height - 1
            width: parent.width - 18
            height: 1
            color: Theme.accent
        }
        MouseArea {
            id: tm
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onPressed: t.picked()
        }
    }

    // An app: its icon, its name, and on the cursor row what Enter does.
    // The generic name is printed only when it is why the row matched --
    // `term` finds kitty because it is a Terminal emulator, and without the
    // word the row looks like a mistake.
    component AppRow: Rectangle {
        id: r
        property var entry: null
        readonly property var app: entry.r.app
        readonly property bool isCursor: root.cursor === entry.k
        readonly property bool showGen: entry.r.where === "g" && (app.generic || "") !== ""

        height: 36
        radius: 7
        color: isCursor ? Theme.panelCursor : hit.containsMouse ? Theme.panelHover : Qt.rgba(1, 1, 1, 0)
        border.width: isCursor ? 1 : 0
        border.color: root.ringOnCursor
        Behavior on color { enabled: Anim.enabled; ColorAnimation { duration: Anim.ms(Anim.hover) } }

        function esc(s) { return s.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;"); }
        // Matched letters are bold, not mint: a match is not state.
        // The bold run is in the name's ink even inside the dim generic name.
        function marked(s, at) {
            const n = root.parsed.text.length;
            if (at < 0 || n === 0) return esc(s);
            return esc(s.slice(0, at)) + "<span style=\"font-weight:600; color:" + root.txt + "\">" + esc(s.slice(at, at + n))
                 + "</span>" + esc(s.slice(at + n));
        }

        MouseArea {
            id: hit
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onPressed: root.openRow(r.entry.k)
        }

        Image {
            id: appIcon
            x: 9
            anchors.verticalCenter: parent.verticalCenter
            width: 22
            height: 22
            sourceSize.width: 44
            sourceSize.height: 44
            source: r.app.icon ? "file://" + r.app.icon : ""
            asynchronous: true
            smooth: true
            mipmap: true
        }
        // NO ICON IS A TILE, NOT A HOLE. apps.py's fallback icon is a
        // Papirus file, so on a machine without Papirus an unresolved Icon=
        // arrives as "" -- and a path that has gone, or an svg with no Qt
        // svg plugin, fails here. A blank space before the name reads as
        // the row failing to load (measured by breaking three paths).
        Rectangle {
            visible: appIcon.status !== Image.Ready && appIcon.status !== Image.Loading
            x: 9
            anchors.verticalCenter: parent.verticalCenter
            width: 22
            height: 22
            radius: 6
            color: Theme.panelHover
            Text {
                anchors.centerIn: parent
                text: r.app.name.charAt(0).toUpperCase()
                color: root.txt2
                font.family: Theme.fontMono
                font.pixelSize: 11
            }
        }
        Text {
            x: 40
            anchors.verticalCenter: parent.verticalCenter
            width: (right.visible ? right.x - 12 : r.width - 9) - x
            elide: Text.ElideRight
            textFormat: Text.RichText
            text: r.marked(r.app.name, r.entry.r.where === "n" ? r.entry.r.at : -1)
            color: root.txt
            font.family: Theme.fontSans
            font.pixelSize: 13
        }

        Row {
            id: right
            visible: r.showGen || r.isCursor
            anchors.right: parent.right
            anchors.rightMargin: 9
            anchors.verticalCenter: parent.verticalCenter
            spacing: 6
            Text {
                visible: r.showGen
                anchors.verticalCenter: parent.verticalCenter
                textFormat: Text.RichText
                text: r.marked(r.app.generic || "", r.entry.r.at)
                color: root.txt2
                font.family: Theme.fontSans
                font.pixelSize: 12
            }
            // The word says what Enter does, not what the app is.
            Text {
                visible: r.isCursor
                anchors.verticalCenter: parent.verticalCenter
                text: root.verb(r.app)
                color: root.txt2
                font.family: Theme.fontMono
                font.pixelSize: 11
                font.letterSpacing: 11 * 0.03
            }
        }
    }
}
