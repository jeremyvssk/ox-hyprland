// ═══════════════════════════════════════════════════════════════
// THE CALENDAR PANEL — the month, and a day that takes the panel.
//
// Datum Panels, Time & Date round five (2026-09-30), built on the
// user's picks from the round-five dock:
//   Size            620 x 438, like the other panels (Theme.calendarDepth).
//   Pressing a day  one press opens the day. (Their ask.)
//   A note          up to four lines of details on the day page.
//   The week        a strip of the seven days on top of the day.
//   Clocks          not drawn.
// And what round five decided for everyone: the time is typed or
// picked and never guessed, a timed note can remind early, and a
// repeat can be weekly on your own days, every N, and end on a date.
// Round four's card is deleted -- it is why long notes did not fit.
//
// ── HOW YOU USE IT ───────────────────────────────────────────
//   The month      press a day and the day takes the panel. Press a
//                  note's name to open its day with that note ready to
//                  change. Drag a name to another day to move it.
//   The day        ‹ Month (or Esc) goes back. The week strip and the
//                  arrows step days. Every note on the day, in time
//                  order, with up to four lines of its details and one
//                  line saying when it reminds and how it repeats.
//   Writing        the line at the bottom, or just start typing. A
//                  title, then Shift+Enter for as many lines of details
//                  as you want, then Enter. "Gym every mon, wed 7:30"
//                  is read (Notes.resolve) and the line under the
//                  details says what it took. Clicking elsewhere on the
//                  day keeps what you wrote; only Esc throws it away.
//   Changing one   press it: the same editor opens in its place, with
//                  Delete, which asks first.
//   The time       type 1430, 14:30 or 9; ↑/↓ or the wheel move it by
//                  15 minutes (Shift: an hour).
//   Keys           month: arrows move the day, PageUp/PageDown the
//                  month, Home is today, Enter opens the day. Day: ←/→
//                  a day, PageUp/PageDown a week, Home today, Enter
//                  writes. Esc backs out a step.
//
// ── WHAT MOVES ───────────────────────────────────────────────
// Gated by the motion skill: nothing of its own (round five, T34).
// Opening a day, opening a note and a repeat's second line are each
// used many times a day, often from the keyboard, so they change at
// once. The open is the body's (Island.qml). A dragged note follows
// the pointer 1:1 and lands on release. Hover is the kit's 130 ms colour.
// ═══════════════════════════════════════════════════════════════

import QtQuick

// A plain Item, not a FocusScope -- WifiPanel.qml has the reason.
Item {
    id: root

    property bool open: false
    signal closeRequested()

    width: Theme.widthNormal
    height: Theme.calendarDepth

    readonly property int pad: 14
    readonly property color txt: Theme.textPrimary
    readonly property color txt2: Theme.textDim
    readonly property color body2: Qt.rgba(0.74 * txt.r + 0.26 * txt2.r, 0.74 * txt.g + 0.26 * txt2.g,
                                           0.74 * txt.b + 0.26 * txt2.b, 1)

    // ── THE VIEW ─────────────────────────────────────────────
    property string page: "month"
    property int vy: Notes.from(Notes.today).y
    property int vm: Notes.from(Notes.today).m
    property int sel: Notes.today

    readonly property int first: Notes.key(vy, vm, 1)
    readonly property int lead: (Notes.wd(first) + 6) % 7           // Monday first
    readonly property int start: first - lead
    readonly property int weeks: Math.ceil((lead + Notes.dim(vy, vm)) / 7)
    readonly property bool away: vy !== Notes.from(Notes.today).y || vm !== Notes.from(Notes.today).m

    // ── THE GRID'S GEOMETRY, STATED ONCE ─────────────────────
    // Everything that needs a day's box -- the cells and the drop under
    // a dragged note -- reads these, so they cannot drift.
    readonly property int gridTop: 48
    readonly property int gap: 2
    readonly property int dowH: 20
    readonly property real rowsTop: gridTop + dowH + gap
    readonly property real cellW: (width - pad * 2 - gap * 6) / 7
    readonly property real cellH: (height - 12 - rowsTop - gap * (weeks - 1)) / weeks
    // How many notes a day shows before "+ more": its height less the
    // padding (7) and the number line (16), in 19 px steps (17 + 2 gap).
    readonly property int cap: Math.max(1, Math.floor((cellH - 23) / 19))

    function cellX(i) { return pad + (i % 7) * (cellW + gap); }
    function cellY(i) { return rowsTop + Math.floor(i / 7) * (cellH + gap); }
    function cellAt(px, py) {
        const c = Math.floor((px - pad) / (cellW + gap)), r = Math.floor((py - rowsTop) / (cellH + gap));
        if (c < 0 || c > 6 || r < 0 || r >= weeks) return -1;
        return start + r * 7 + c;
    }

    function follow(k) { const p = Notes.from(k); vy = p.y; vm = p.m; }

    // ── THE DRAFT ────────────────────────────────────────────
    // One editor, for a new note (at the bottom of the day) and for
    // changing one (in the note's place in the list). The title and the
    // details live in their fields; everything else is here.
    property bool editing: false
    property int edId: -1               // -1: a new note
    property bool ask: false
    property int dKey: 0
    property string dTime: ""
    property int dRemind: 0
    property var dRep: Notes.rep0()
    property bool setDate: false
    property bool setTime: false
    property bool setRep: false
    // what is typed in the time and end fields, until it reads as one
    property string tq: ""
    property bool tqOn: false
    property bool tBad: false
    property string uq: ""
    property bool uqOn: false
    property bool uBad: false

    readonly property var res: Notes.resolve({ title: titleField.text, key: dKey, time: dTime, rep: dRep,
                                               setDate: setDate, setTime: setTime, setRep: setRep })
    readonly property var dayNotes: { Notes.list; return Notes.onDay(sel); }

    function draft(k, n) {
        ask = false; tqOn = false; tBad = false; uqOn = false; uBad = false;
        if (n) {
            titleField.text = n.title; bodyField.text = n.body || "";
            dKey = n.key; dTime = n.time; dRemind = n.remind; dRep = Notes.cloneRep(n.rep);
            setDate = true; setTime = true; setRep = true;
        } else {
            titleField.text = ""; bodyField.text = "";
            dKey = k; dTime = ""; dRemind = 0; dRep = Notes.rep0();
            setDate = false; setTime = false; setRep = false;
        }
    }
    function home() { root.forceActiveFocus(); }
    function focusTitle() {
        Qt.callLater(() => {
            titleField.forceActiveFocus(); titleField.cursorPosition = titleField.text.length;
            root.reveal();
        });
    }

    function openDay(k, noteId) {
        leave();
        page = "day"; sel = k; follow(k);
        if (noteId !== undefined && noteId >= 0) editNote(noteId);
        else home();
    }
    function toMonth() { leave(); page = "month"; home(); }
    function goDay(k) { leave(); sel = k; follow(k); notesList.contentY = 0; home(); }
    function startNew(ch) {
        draft(sel, null);
        titleField.text = ch || "";
        edId = -1; editing = true;
        focusTitle();
    }
    function editNote(id) {
        leave();
        const n = Notes.find(id);
        if (!n) return;
        draft(null, n);
        edId = id; editing = true;
        focusTitle();
    }
    function closeEditor() { editing = false; ask = false; edId = -1; home(); }

    // Enter, Add or Save. A new note leaves the line at the bottom
    // ready for the next one: typing starts it again.
    function save() {
        applyTime(); applyUntil();
        const r = res, body = bodyField.text.replace(/\s+$/, "");
        if (r.title === "") return closeEditor();
        const rec = { title: r.title, body: body, key: r.key, time: r.time, remind: dRemind, rep: r.rep };
        if (edId >= 0) { if (Notes.find(edId)) Notes.update(edId, rec); }
        else Notes.add(rec);
        closeEditor();
    }
    // Anything that takes you away from the editor keeps what you wrote.
    function leave() {
        if (!editing) return;
        if (!ask && titleField.text.trim() !== "") save();
        else closeEditor();
    }
    function del() {
        if (Notes.find(edId)) Notes.remove(edId);
        closeEditor();
    }

    // THE TIME FIELD. 1430, 14:30, 14.30 or 9 -- read as you type, so the
    // Remind row appears the moment there is a time; what you typed stays
    // in the field until you leave it.
    function readTime(v) {
        const m = /^(\d{1,2})(?:[:.]?(\d{2}))?$/.exec(v.trim());
        return m && +m[1] < 24 && (!m[2] || +m[2] < 60) ? Notes.pad(+m[1]) + ":" + (m[2] || "00") : null;
    }
    function typedTime(v) {
        tq = v; tqOn = true; tBad = false;
        const t = v.trim() === "" ? "" : readTime(v);
        if (t !== null) { dTime = t; setTime = true; }
    }
    function applyTime() {
        if (!tqOn) return;
        const t = tq.trim() === "" ? "" : readTime(tq);
        if (t === null) { tBad = true; return; }
        dTime = t; setTime = true; tqOn = false; tBad = false;
    }
    function stepTime(dm) {
        applyTime(); takeTime();
        const n = new Date(), base = dTime ? Notes.mins(dTime) : Math.floor((n.getHours() * 60 + n.getMinutes()) / 15) * 15;
        dTime = Notes.hm(base + (dTime ? dm : 0)); tqOn = false; tBad = false;
    }
    // THE END FIELD. dd/mm, or dd/mm/yy; empty is never.
    function applyUntil() {
        if (!uqOn) return;
        const v = uq.trim().replace(/^on\s+/i, ""), m = /^(\d{1,2})[\/.](\d{1,2})(?:[\/.](\d{2,4}))?$/.exec(v);
        if (!v) return repEdit(r => { r.until = 0; }, true);
        if (m) {
            const y = m[3] ? (+m[3] < 100 ? 2000 + (+m[3]) : +m[3]) : 0, mo = +m[2] - 1, d = +m[1];
            const k = y ? (mo >= 0 && mo < 12 && d >= 1 && d <= Notes.dim(y, mo) ? Notes.key(y, mo, d) : 0) : Notes.dm(d, mo);
            if (k) return repEdit(r => { r.until = k; }, true);
        }
        uBad = true;
    }

    // A row touched by hand takes the parser's answer as its starting
    // point, and from then on the typed words stop counting for it.
    function takeKey() { if (!setDate) { dKey = res.key; setDate = true; } return dKey; }
    function takeTime() { if (!setTime) { dTime = res.time; setTime = true; } }
    function repEdit(fn, fromUntil) {
        const r = Notes.cloneRep(setRep ? dRep : res.rep);
        fn(r);
        dRep = r; setRep = true;
        if (fromUntil) { uqOn = false; uBad = false; }
    }

    function goMonth(dir) {
        let m = vm + dir, y = vy + Math.floor(m / 12);
        m = ((m % 12) + 12) % 12;
        const d = Math.min(Notes.from(sel).d, Notes.dim(y, m));
        vy = y; vm = m; sel = Notes.key(y, m, d);
    }

    // The editor in the list is kept on screen: its title when it opens,
    // and as much of it as fits.
    function reveal() {
        if (!editing || edId < 0 || editor.parent === newSlot) return;
        const y = editor.mapToItem(notesList.contentItem, 0, 0).y;
        const want = Math.min(editor.height, notesList.height);
        if (y < notesList.contentY) notesList.contentY = Math.max(0, y - 4);
        else if (y + want > notesList.contentY + notesList.height)
            notesList.contentY = Math.max(0, Math.min(y - 4, y + want - notesList.height + 4));
    }

    // ── OPENING AND CLOSING ──────────────────────────────────
    // It opens on today's month with today picked; an editor left open
    // when the panel closed is saved, never thrown away.
    onOpenChanged: {
        if (open) {
            page = "month"; sel = Notes.today; follow(sel);
            home();
        } else {
            leave();
            editing = false;
            dragId = -1;
        }
    }
    Connections {
        target: root.Window.window
        function onActiveFocusItemChanged() {
            const w = root.Window.window;
            if (root.open && (!w.activeFocusItem || w.activeFocusItem === w.contentItem))
                Qt.callLater(() => root.forceActiveFocus());
        }
    }

    // ── THE PAGE KEYS ────────────────────────────────────────
    // A letter anywhere starts a note on the day -- from the month too,
    // which opens the picked day first: writing happens in one place.
    Keys.onPressed: event => {
        const k = event.key, mods = event.modifiers & (Qt.ControlModifier | Qt.AltModifier | Qt.MetaModifier);
        const letter = event.text.length === 1 && event.text > " " && !mods;
        if (page === "month") {
            const mv = k === Qt.Key_Left ? -1 : k === Qt.Key_Right ? 1 : k === Qt.Key_Up ? -7 : k === Qt.Key_Down ? 7 : 0;
            if (k === Qt.Key_Escape) root.closeRequested();
            else if (mods) return;
            else if (mv) { sel += mv; follow(sel); }
            else if (k === Qt.Key_PageUp || k === Qt.Key_PageDown) goMonth(k === Qt.Key_PageDown ? 1 : -1);
            else if (k === Qt.Key_Home) { sel = Notes.today; follow(sel); }
            else if (k === Qt.Key_Return || k === Qt.Key_Enter) openDay(sel);
            else if (letter) { page = "day"; startNew(event.text); }
            else return;
        } else {
            if (k === Qt.Key_Escape) toMonth();
            else if (mods) return;
            else if (k === Qt.Key_Left || k === Qt.Key_Right) goDay(sel + (k === Qt.Key_Right ? 1 : -1));
            else if (k === Qt.Key_PageUp || k === Qt.Key_PageDown) goDay(sel + (k === Qt.Key_PageDown ? 7 : -7));
            else if (k === Qt.Key_Home) goDay(Notes.today);
            else if (k === Qt.Key_Return || k === Qt.Key_Enter) startNew("");
            else if (letter) startNew(event.text);
            else return;
        }
        event.accepted = true;
    }

    // Anywhere in the body that is not a control: the editor closes,
    // keeping what was typed.
    MouseArea {
        anchors.fill: parent
        onPressed: { root.leave(); root.home(); }
    }

    // ═══ THE MONTH ══════════════════════════════════════════
    Item {
        id: monthPage
        anchors.fill: parent
        visible: root.page === "month"

        // October 2026. Its arrows are THE ARROWS, at the right edge.
        Row {
            x: root.pad
            y: 12
            height: 30
            spacing: 7
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: Notes.monthNames[root.vm]
                color: root.txt
                font.family: Theme.fontSans
                font.pixelSize: 15
                font.weight: Font.DemiBold
            }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: root.vy
                color: root.txt2
                font.family: Theme.fontSans
                font.pixelSize: 15
            }
        }

        Repeater {
            model: 7
            delegate: Text {
                required property int index
                x: root.cellX(index) + 7
                y: root.gridTop
                height: root.dowH
                verticalAlignment: Text.AlignVCenter
                text: Notes.dayNames[(index + 1) % 7].slice(0, 3)
                color: root.txt2
                font.family: Theme.fontCaps
                font.pixelSize: 9
                font.weight: Theme.capsWeight
                font.letterSpacing: 1.3
                font.capitalization: Font.AllUppercase
            }
        }

        Repeater {
            model: root.weeks * 7
            delegate: Day {}
        }
    }

    // ═══ THE DAY ════════════════════════════════════════════
    // It replaces the month in the same body. From the top: the way
    // back, the day in words, the week, the notes, the line to write on.
    Item {
        id: dayPage
        anchors.fill: parent
        visible: root.page === "day"

        readonly property int listTop: 124
        readonly property int foot: root.height - 12

        // ‹ September. The day before and after are THE ARROWS.
        Item {
            x: root.pad
            y: 12
            width: root.width - root.pad * 2
            height: 28

            Rectangle {
                x: -4
                anchors.verticalCenter: parent.verticalCenter
                width: backRow.implicitWidth + 12
                height: 26
                radius: 6
                color: bm.containsMouse ? Qt.rgba(1, 1, 1, 0.06) : Qt.rgba(1, 1, 1, 0)
                Behavior on color { enabled: Anim.enabled; ColorAnimation { duration: Anim.ms(Anim.hover) } }
                Row {
                    id: backRow
                    x: 3
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 3
                    Icon {
                        anchors.verticalCenter: parent.verticalCenter
                        name: "chev"
                        size: 14
                        rotation: 90
                        color: bm.containsMouse ? root.txt : root.txt2
                    }
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: Notes.monthNames[Notes.from(root.sel).m]
                        color: bm.containsMouse ? root.txt : root.txt2
                        font.family: Theme.fontMono
                        font.pixelSize: 11
                    }
                }
                MouseArea {
                    id: bm
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onPressed: root.toMonth()
                }
            }
        }

        // Tuesday 29 September  TODAY  3 notes
        Row {
            x: root.pad
            y: 44
            height: 24
            spacing: 10
            Text {
                id: dayTitle
                text: Notes.long(root.sel)
                color: root.txt
                font.family: Theme.fontSans
                font.pixelSize: 17
                font.weight: Font.DemiBold
            }
            Text {
                visible: root.sel === Notes.today
                anchors.baseline: dayTitle.baseline
                text: "Today"
                color: Theme.accent
                font.family: Theme.fontCaps
                font.pixelSize: 9
                font.weight: Theme.capsWeight
                font.letterSpacing: 1.4
                font.capitalization: Font.AllUppercase
            }
            Text {
                anchors.baseline: dayTitle.baseline
                text: root.dayNotes.length ? root.dayNotes.length + " note" + (root.dayNotes.length > 1 ? "s" : "") : ""
                color: root.txt2
                font.family: Theme.fontMono
                font.pixelSize: 11
            }
        }

        // THE WEEK. A dot under each day that has notes; press one to go.
        Repeater {
            model: 7
            delegate: Rectangle {
                id: wdc
                required property int index
                readonly property int k: Notes.monday(root.sel) + index
                readonly property bool has: { Notes.list; return Notes.onDay(k).length > 0; }
                x: root.cellX(index)
                y: 76
                width: root.cellW
                height: 40
                radius: 8
                color: k === root.sel ? Theme.panelCursor : wm.containsMouse ? Qt.rgba(1, 1, 1, 0.05) : Qt.rgba(1, 1, 1, 0)
                border.width: k === root.sel ? 1 : 0
                border.color: Qt.rgba(1, 1, 1, 0.11)
                Behavior on color { enabled: Anim.enabled; ColorAnimation { duration: Anim.ms(Anim.hover) } }
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    y: 4
                    text: Notes.dayNames[Notes.wd(wdc.k)].slice(0, 3)
                    color: root.txt2
                    font.family: Theme.fontCaps
                    font.pixelSize: 9
                    font.weight: Theme.capsWeight
                    font.letterSpacing: 1.2
                    font.capitalization: Font.AllUppercase
                }
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    y: 17
                    text: Notes.from(wdc.k).d
                    color: wdc.k === Notes.today ? Theme.accent : root.txt
                    font.family: Theme.fontMono
                    font.pixelSize: 12
                    font.weight: wdc.k === Notes.today ? Font.DemiBold : Font.Normal
                    font.features: ({ "tnum": 1 })
                }
                Rectangle {
                    visible: wdc.has
                    anchors.horizontalCenter: parent.horizontalCenter
                    y: 34
                    width: 3
                    height: 3
                    radius: 1.5
                    color: root.txt2
                }
                MouseArea {
                    id: wm
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onPressed: root.goDay(wdc.k)
                }
            }
        }

        // THE NOTES. In time order, untimed ones last. The note being
        // changed is replaced by the editor, in its place.
        Flickable {
            id: notesList
            x: root.pad - 8
            y: dayPage.listTop
            width: root.width - root.pad * 2 + 16
            height: Math.max(0, (root.editing && root.edId < 0 ? newSlot.y : idle.y) - 8 - y)
            contentHeight: listCol.height
            clip: true
            interactive: false
            // a note closed or deleted can leave the view past the end
            onContentHeightChanged: contentY = Math.max(0, Math.min(contentY, contentHeight - height))

            Column {
                id: listCol
                x: 8
                width: notesList.width - 16
                spacing: 2

                Repeater {
                    model: root.dayNotes
                    delegate: Item {
                        id: slot
                        required property var modelData
                        readonly property bool isEd: root.editing && root.edId === modelData.id
                        width: listCol.width
                        height: isEd ? editor.height : noteRow.height
                        onIsEdChanged: if (isEd) root.edSlot = slot
                        Component.onCompleted: if (isEd) root.edSlot = slot
                        Component.onDestruction: if (root.edSlot === slot) root.edSlot = null

                        NoteRow { id: noteRow; n: slot.modelData; visible: !slot.isEd }
                    }
                }
            }
        }

        // The line to write on. Press it, or just type.
        Rectangle {
            id: idle
            visible: !(root.editing && root.edId < 0)
            x: root.pad
            y: dayPage.foot - height
            width: root.width - root.pad * 2
            height: 38
            radius: 10
            color: Theme.panelWell
            // The page has the keyboard: a letter lands here. Said with the
            // hairline and a caret, not with a blink.
            border.width: root.activeFocus && root.page === "day" ? 1 : 0
            border.color: Qt.alpha(Theme.accent, 0.35)
            Icon {
                x: 12
                anchors.verticalCenter: parent.verticalCenter
                name: "plus"
                size: 13
                color: root.txt2
            }
            Rectangle {
                visible: root.activeFocus && root.page === "day"
                x: 33
                anchors.verticalCenter: parent.verticalCenter
                width: 1
                height: 15
                color: Theme.accent
            }
            Text {
                x: 36
                anchors.verticalCenter: parent.verticalCenter
                text: (root.dayNotes.length ? "Write a note for " : "Write the first note for ")
                      + (Math.abs(root.sel - Notes.today) <= 1 ? Notes.short(root.sel).toLowerCase() : Notes.short(root.sel))
                color: root.txt2
                font.family: Theme.fontSans
                font.pixelSize: 13
            }
            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.IBeamCursor
                onPressed: { root.leave(); root.startNew(""); }
            }
        }

        // Where a new note's editor sits: at the bottom, as tall as it
        // needs up to the point where one note of the list still shows.
        Item {
            id: newSlot
            x: root.pad
            width: root.width - root.pad * 2
            height: Math.min(editor.implicitHeight, dayPage.foot - dayPage.listTop - 60)
            y: dayPage.foot - height
        }

        // THE WHEEL, HANDLED HERE AND NOWHERE ELSE. The three scrolling
        // things on this page -- the notes, the editor, its details -- are
        // Flickables with interactive OFF: an interactive Flickable ate the
        // first press after a wheel scroll (measured: the chip under the
        // pointer never saw it, the second press did), and it would also
        // turn a drag that selects details into a scroll. So one area on
        // top takes every notch and gives it to whatever is under the
        // pointer: the time field (±15 min), then the details, then the
        // editor, then the list. Presses go straight through it.
        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.NoButton
            onWheel: wheel => {
                const d = wheel.pixelDelta.y !== 0 ? wheel.pixelDelta.y : wheel.angleDelta.y / 120 * 40;
                const over = it => {
                    if (!it.visible || !editor.visible && it !== notesList) return false;
                    const p = mapToItem(it, wheel.x, wheel.y);
                    return p.x >= 0 && p.y >= 0 && p.x < it.width && p.y < it.height;
                };
                const roll = f => { f.contentY = Math.max(0, Math.min(f.contentHeight - f.height, f.contentY - d)); };
                if (over(timeField.parent)) root.stepTime(wheel.angleDelta.y > 0 || wheel.pixelDelta.y > 0 ? 15 : -15);
                else if (over(bodyFlick) && bodyFlick.contentHeight > bodyFlick.height) roll(bodyFlick);
                else if (over(edFlick) && edFlick.contentHeight > edFlick.height) roll(edFlick);
                else if (over(notesList)) roll(notesList);
            }
        }
    }

    // ═══ THE ARROWS ═════════════════════════════════════════
    // One row for both pages, against the right edge, so Today ‹ › sit
    // on the same pixels whatever the month is called and whichever page
    // is up. They used to follow the month's name, and a name is 3 to 9
    // letters: ‹ landed anywhere from x 109 (May) to 157 (September),
    // measured 2026-10-05. On the month they step months, on the day
    // days. Today shows only when you are away from it -- a Today that is
    // always there is a button that usually does nothing -- and the row
    // grows leftward, so it moves nothing. A notes file that does not
    // parse says so at the row's left end, never on top of the arrows.
    Row {
        id: arrows
        readonly property bool day: root.page === "day"
        z: 3
        anchors.right: parent.right
        anchors.rightMargin: root.pad - 4
        y: 12
        height: 28
        spacing: 4

        Text {
            visible: Notes.broken
            anchors.verticalCenter: parent.verticalCenter
            rightPadding: 6
            text: "notes.json does not read · nothing is saved"
            color: Theme.danger
            font.family: Theme.fontMono
            font.pixelSize: 11
        }
        Btn {
            visible: arrows.day ? root.sel !== Notes.today : root.away
            anchors.verticalCenter: parent.verticalCenter
            label: "Today"
            dim: true
            implicitHeight: 26
            onClicked: {
                if (arrows.day) root.goDay(Notes.today);
                else { root.sel = Notes.today; root.follow(root.sel); root.home(); }
            }
        }
        IconBtn { anchors.verticalCenter: parent.verticalCenter; icon: "chev"; turn: 90; onClicked: arrows.day ? root.goDay(root.sel - 1) : root.goMonth(-1) }
        IconBtn { anchors.verticalCenter: parent.verticalCenter; icon: "chev"; turn: -90; onClicked: arrows.day ? root.goDay(root.sel + 1) : root.goMonth(1) }
    }

    // ═══ THE EDITOR ═════════════════════════════════════════
    // One object for writing a note and for changing one. It sits in
    // the list, in the place of the note it changes, or at the bottom
    // for a new one -- the same fields either way, so there is one
    // editor to keep right rather than two.
    property Item edSlot: null
    Rectangle {
        id: editor
        visible: root.editing && root.page === "day"
        parent: root.edId >= 0 && root.edSlot ? root.edSlot : newSlot
        width: parent ? parent.width : 0
        implicitHeight: edCol.implicitHeight + 20
        height: parent === newSlot ? newSlot.height : implicitHeight
        radius: 11
        color: Theme.panelCard
        border.width: 1
        border.color: Theme.glassEdge

        // its own air takes the press, so it does not close it
        MouseArea { anchors.fill: parent }

        Flickable {
            id: edFlick
            x: 12
            y: 10
            width: parent.width - 24
            height: parent.height - 20
            contentHeight: edCol.implicitHeight
            clip: true
            interactive: false
            function show(item) {
                const y = item.mapToItem(edCol, 0, 0).y;
                if (y < contentY) contentY = y;
                else if (y + item.height > contentY + height) contentY = y + item.height - height;
            }

            Column {
                id: edCol
                width: edFlick.width
                spacing: 6

                // the title: one line
                Item {
                    width: parent.width
                    height: 20
                    TextInput {
                        id: titleField
                        anchors.fill: parent
                        verticalAlignment: TextInput.AlignVCenter
                        color: root.txt
                        font.family: Theme.fontSans
                        font.pixelSize: 14
                        font.weight: Font.Medium
                        selectionColor: Qt.alpha(Theme.accent, 0.35)
                        selectedTextColor: root.txt
                        clip: true
                        KeyNavigation.tab: bodyField
                        KeyNavigation.backtab: root.res.rep.f !== "never" ? untilField : timeField
                        cursorDelegate: Rectangle { width: 1; color: Theme.accent; visible: titleField.cursorVisible }
                        onActiveFocusChanged: if (activeFocus) edFlick.show(parent)
                        Keys.onPressed: event => {
                            const k = event.key;
                            if (k === Qt.Key_Escape) root.closeEditor();
                            else if ((k === Qt.Key_Return || k === Qt.Key_Enter) && (event.modifiers & Qt.ShiftModifier))
                                bodyField.forceActiveFocus();
                            else if (k === Qt.Key_Return || k === Qt.Key_Enter) root.save();
                            else return;
                            event.accepted = true;
                        }
                    }
                    Text {
                        visible: titleField.text === ""
                        anchors.verticalCenter: parent.verticalCenter
                        text: "Title · Dentist friday 14:30"
                        color: root.txt2
                        font.family: Theme.fontSans
                        font.pixelSize: 14
                    }
                }

                // the details: as long as you need. Grows to eight lines,
                // then scrolls inside itself.
                Flickable {
                    id: bodyFlick
                    width: parent.width
                    height: Math.min(Math.max(19, bodyField.contentHeight), 168)
                    contentHeight: bodyField.contentHeight
                    clip: true
                    interactive: false
                    function follow(r) {
                        if (contentY >= r.y) contentY = r.y;
                        else if (contentY + height <= r.y + r.height) contentY = r.y + r.height - height;
                    }
                    TextEdit {
                        id: bodyField
                        width: bodyFlick.width
                        wrapMode: TextEdit.Wrap
                        color: root.txt
                        font.family: Theme.fontSans
                        font.pixelSize: 13
                        selectionColor: Qt.alpha(Theme.accent, 0.35)
                        selectedTextColor: root.txt
                        KeyNavigation.tab: timeField
                        KeyNavigation.backtab: titleField
                        cursorDelegate: Rectangle { width: 1; color: Theme.accent; visible: bodyField.cursorVisible }
                        onCursorRectangleChanged: bodyFlick.follow(cursorRectangle)
                        onActiveFocusChanged: if (activeFocus) edFlick.show(bodyFlick)
                        Keys.onPressed: event => {
                            const k = event.key;
                            if (k === Qt.Key_Escape) root.closeEditor();
                            else if ((k === Qt.Key_Return || k === Qt.Key_Enter) && !(event.modifiers & Qt.ShiftModifier)) root.save();
                            else return;
                            event.accepted = true;
                        }
                    }
                    Text {
                        visible: bodyField.text === ""
                        text: "Details, as much as you need · Shift+Enter"
                        color: root.txt2
                        font.family: Theme.fontSans
                        font.pixelSize: 13
                    }
                }

                // WHAT THE LINE WAS READ AS. The slot keeps its height when
                // there is nothing to say, so nothing under it jumps.
                Text {
                    width: parent.width
                    height: 15
                    elide: Text.ElideRight
                    textFormat: Text.StyledText
                    text: {
                        const r = root.res;
                        if (!r.sp.length) return "";
                        const e = s => s.replace(/&/g, "&amp;").replace(/</g, "&lt;");
                        const took = r.sp.map(s => e(titleField.text.slice(s[0], s[1]))).join(" ");
                        const out = [Notes.short(r.key)];
                        if (r.time) out.push(r.time);
                        if (r.rep.f !== "never") out.push(Notes.repText(r.rep, r.key));
                        return "Took <font color=\"" + root.txt + "\">" + took + "</font> → <font color=\"" + root.txt + "\">"
                               + e(out.join(" · ")) + "</font>";
                    }
                    color: root.txt2
                    font.family: Theme.fontMono
                    font.pixelSize: 11
                }

                Rectangle { width: parent.width; height: 1; color: Theme.glassEdge }

                // DAY
                Line {
                    lab: "Day"
                    Ch { sq: true; icon: "chev"; turn: 90; onPressed: { root.dKey = root.takeKey() - 1; } }
                    Text {
                        width: 88
                        height: 24
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                        text: Notes.short(root.res.key)
                        color: root.txt
                        font.family: Theme.fontMono
                        font.pixelSize: 11
                    }
                    Ch { sq: true; icon: "chev"; turn: -90; onPressed: { root.dKey = root.takeKey() + 1; } }
                    Ch { label: "Today"; on: root.res.key === Notes.today; onPressed: { root.dKey = Notes.today; root.setDate = true; } }
                    Ch { label: "Tomorrow"; on: root.res.key === Notes.today + 1; onPressed: { root.dKey = Notes.today + 1; root.setDate = true; } }
                }

                // TIME: typed, or one of three, or none. Nothing picks one
                // for you (round five, T31).
                Line {
                    lab: "Time"
                    Rectangle {
                        width: 70
                        height: 24
                        radius: 7
                        color: Theme.panelWell
                        border.width: root.tBad ? 1 : timeField.activeFocus ? 1 : 0
                        border.color: root.tBad ? Qt.alpha(Theme.danger, 0.6) : Qt.rgba(1, 1, 1, 0.30)
                        TextInput {
                            id: timeField
                            x: 8
                            width: parent.width - 16
                            anchors.verticalCenter: parent.verticalCenter
                            text: root.tqOn ? root.tq : root.res.time
                            color: root.txt
                            font.family: Theme.fontMono
                            font.pixelSize: 11
                            font.features: ({ "tnum": 1 })
                            selectionColor: Qt.alpha(Theme.accent, 0.35)
                            selectedTextColor: root.txt
                            maximumLength: 5
                            clip: true
                            KeyNavigation.tab: root.res.rep.f !== "never" ? untilField : titleField
                            KeyNavigation.backtab: bodyField
                            cursorDelegate: Rectangle { width: 1; color: Theme.accent; visible: timeField.cursorVisible }
                            onTextEdited: root.typedTime(text)
                            onActiveFocusChanged: { if (activeFocus) edFlick.show(parent); else root.applyTime(); }
                            Keys.onPressed: event => {
                                const k = event.key;
                                if (k === Qt.Key_Up || k === Qt.Key_Down)
                                    root.stepTime((k === Qt.Key_Up ? 1 : -1) * (event.modifiers & Qt.ShiftModifier ? 60 : 15));
                                else if (k === Qt.Key_Escape) root.closeEditor();
                                else if (k === Qt.Key_Return || k === Qt.Key_Enter) root.save();
                                else return;
                                event.accepted = true;
                            }
                        }
                        Text {
                            visible: timeField.text === ""
                            x: 8
                            anchors.verticalCenter: parent.verticalCenter
                            text: "hh:mm"
                            color: root.txt2
                            font.family: Theme.fontMono
                            font.pixelSize: 11
                        }
                    }
                    Repeater {
                        model: ["09:00", "12:00", "18:00"]
                        delegate: Ch {
                            required property string modelData
                            label: modelData
                            on: root.res.time === modelData
                            onPressed: { root.dTime = modelData; root.setTime = true; root.tqOn = false; root.tBad = false; }
                        }
                    }
                    Ch { label: "None"; on: !root.res.time; onPressed: { root.dTime = ""; root.setTime = true; root.tqOn = false; root.tBad = false; } }
                }

                // REMIND, once there is a time.
                Line {
                    visible: root.res.time !== ""
                    lab: "Remind"
                    Repeater {
                        model: Notes.remindSteps
                        delegate: Ch {
                            required property var modelData
                            label: modelData[0] === 0 ? "At " + root.res.time : modelData[1]
                            on: root.dRemind === modelData[0]
                            // not takeTime(): choosing when to be reminded is not
                            // choosing the time, so "Dentist 14:30" keeps its
                            // words claimed and the title stays "Dentist"
                            onPressed: root.dRemind = modelData[0]
                        }
                    }
                }

                // REPEAT, and the second line for the choice.
                Line {
                    lab: "Repeat"
                    Repeater {
                        model: [["never", "Never"], ["day", "Daily"], ["week", "Weekly"], ["month", "Monthly"], ["year", "Yearly"]]
                        delegate: Ch {
                            required property var modelData
                            label: modelData[1]
                            on: root.res.rep.f === modelData[0]
                            onPressed: {
                                const f = modelData[0], k = root.takeKey();
                                root.repEdit(r => {
                                    r.f = f; r.n = 1;
                                    if (f === "week" && !r.days.length) r.days = [Notes.wd(k)];
                                    if (f === "never") r.until = 0;
                                });
                            }
                        }
                    }
                }
                Line {
                    visible: root.res.rep.f !== "never"
                    lab: ""
                    Text { height: 24; verticalAlignment: Text.AlignVCenter; text: "Every"; color: root.txt2; font.family: Theme.fontMono; font.pixelSize: 11 }
                    Ch { sq: true; label: "−"; onPressed: root.repEdit(r => { r.n = Math.max(1, (r.n || 1) - 1); }) }
                    Text {
                        width: 18
                        height: 24
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                        text: root.res.rep.n
                        color: root.txt
                        font.family: Theme.fontMono
                        font.pixelSize: 11
                        font.features: ({ "tnum": 1 })
                    }
                    Ch { sq: true; label: "+"; onPressed: root.repEdit(r => { r.n = Math.min(99, (r.n || 1) + 1); }) }
                    Text {
                        height: 24
                        verticalAlignment: Text.AlignVCenter
                        readonly property string unit: ({ day: "day", week: "week", month: "month", year: "year" })[root.res.rep.f] || ""
                        text: unit + (root.res.rep.n === 1 ? "" : "s") + (root.res.rep.f === "year"
                              ? " on " + Notes.from(root.res.key).d + " " + Notes.monthNames[Notes.from(root.res.key).m] : "")
                              + (root.res.rep.f === "week" || root.res.rep.f === "month" ? "  on" : "")
                        color: root.txt2
                        font.family: Theme.fontMono
                        font.pixelSize: 11
                    }
                    // Weekly: the days, Monday first, and Mon–Fri in one press.
                    Repeater {
                        model: root.res.rep.f === "week" ? [1, 2, 3, 4, 5, 6, 0] : []
                        delegate: Ch {
                            required property int modelData
                            readonly property var days: root.res.rep.days.length ? root.res.rep.days : [Notes.wd(root.res.key)]
                            sq: true
                            label: Notes.dayNames[modelData][0]
                            on: days.indexOf(modelData) >= 0
                            onPressed: {
                                const x = modelData, k = root.takeKey();
                                root.repEdit(r => {
                                    const ds = r.days.length ? r.days : [Notes.wd(k)], i = ds.indexOf(x);
                                    if (i >= 0) { if (ds.length > 1) ds.splice(i, 1); } else ds.push(x);
                                    r.days = ds;
                                });
                            }
                        }
                    }
                    Ch {
                        visible: root.res.rep.f === "week"
                        label: "Mon–Fri"
                        on: Notes.sortDays(root.res.rep.days).join() === "1,2,3,4,5"
                        onPressed: root.repEdit(r => { r.days = [1, 2, 3, 4, 5]; })
                    }
                    // Monthly: on the date, the nth weekday, or the last one.
                    Repeater {
                        model: {
                            if (root.res.rep.f !== "month") return [];
                            const p = Notes.from(root.res.key), o = Math.ceil(p.d / 7), wn = Notes.dayNames[Notes.wd(root.res.key)];
                            const out = [["date", "the " + Notes.ord(p.d)]];
                            if (o < 5) out.push(["nth", "the " + Notes.ord(o) + " " + wn]);
                            if (p.d + 7 > Notes.dim(p.y, p.m)) out.push(["last", "the last " + wn]);
                            return out;
                        }
                        delegate: Ch {
                            required property var modelData
                            label: modelData[1]
                            on: root.res.rep.mby === modelData[0]
                            onPressed: { const v = modelData[0]; root.repEdit(r => { r.mby = v; }); }
                        }
                    }
                }
                // ENDS: never, or on a date you type.
                Line {
                    visible: root.res.rep.f !== "never"
                    lab: ""
                    Text { height: 24; verticalAlignment: Text.AlignVCenter; text: "Ends"; color: root.txt2; font.family: Theme.fontMono; font.pixelSize: 11 }
                    Ch { label: "Never"; on: !root.res.rep.until; onPressed: root.repEdit(r => { r.until = 0; }, true) }
                    Rectangle {
                        width: 80
                        height: 24
                        radius: 7
                        color: Theme.panelWell
                        border.width: root.uBad ? 1 : untilField.activeFocus ? 1 : 0
                        border.color: root.uBad ? Qt.alpha(Theme.danger, 0.6) : Qt.rgba(1, 1, 1, 0.30)
                        TextInput {
                            id: untilField
                            x: 8
                            width: parent.width - 16
                            anchors.verticalCenter: parent.verticalCenter
                            text: root.uqOn ? root.uq : root.res.rep.until
                                  ? Notes.from(root.res.rep.until).d + "/" + (Notes.from(root.res.rep.until).m + 1) : ""
                            color: root.txt
                            font.family: Theme.fontMono
                            font.pixelSize: 11
                            selectionColor: Qt.alpha(Theme.accent, 0.35)
                            selectedTextColor: root.txt
                            clip: true
                            KeyNavigation.tab: titleField
                            KeyNavigation.backtab: timeField
                            cursorDelegate: Rectangle { width: 1; color: Theme.accent; visible: untilField.cursorVisible }
                            onTextEdited: { root.uq = text; root.uqOn = true; root.uBad = false; }
                            onActiveFocusChanged: { if (activeFocus) edFlick.show(parent); else root.applyUntil(); }
                            Keys.onPressed: event => {
                                const k = event.key;
                                if (k === Qt.Key_Escape) root.closeEditor();
                                else if (k === Qt.Key_Return || k === Qt.Key_Enter) root.save();
                                else return;
                                event.accepted = true;
                            }
                        }
                        Text {
                            visible: untilField.text === ""
                            x: 8
                            anchors.verticalCenter: parent.verticalCenter
                            text: "on dd/mm"
                            color: root.txt2
                            font.family: Theme.fontMono
                            font.pixelSize: 11
                        }
                    }
                    Text {
                        visible: !!root.res.rep.until
                        height: 24
                        verticalAlignment: Text.AlignVCenter
                        text: root.res.rep.until ? Notes.long(root.res.rep.until) : ""
                        color: root.txt2
                        font.family: Theme.fontMono
                        font.pixelSize: 11
                    }
                }

                // THE ACTIONS, or Delete asked. Enter deletes, Esc takes it back.
                Item {
                    width: parent.width
                    height: root.ask ? askRow.implicitHeight : 30
                    Row {
                        visible: !root.ask
                        anchors.right: parent.right
                        spacing: 6
                        Btn { label: "Cancel"; kind: "quiet"; onClicked: root.closeEditor() }
                        Btn { label: root.edId >= 0 ? "Save" : "Add"; kind: "solid"; onClicked: root.save() }
                    }
                    Btn {
                        visible: !root.ask && root.edId >= 0
                        x: -7
                        label: "Delete"
                        kind: "danger"
                        onClicked: { root.ask = true; askRow.forceActiveFocus(); }
                    }
                    Item {
                        id: askRow
                        visible: root.ask
                        width: parent.width
                        implicitHeight: Math.max(30, cq.implicitHeight)
                        Keys.onPressed: event => {
                            if (event.key === Qt.Key_Escape) { root.ask = false; root.focusTitle(); }
                            else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) root.del();
                            event.accepted = true;
                        }
                        Text {
                            id: cq
                            width: parent.width - askBtns.width - 10
                            anchors.verticalCenter: parent.verticalCenter
                            wrapMode: Text.WrapAtWordBoundaryOrAnywhere
                            maximumLineCount: 3
                            elide: Text.ElideRight
                            textFormat: Text.StyledText
                            text: "Delete <font color=\"" + root.txt + "\">“" + (Notes.find(root.edId) || { title: "" }).title
                                  .replace(/&/g, "&amp;").replace(/</g, "&lt;") + "”</font>?"
                                  + ((Notes.find(root.edId) || { rep: { f: "never" } }).rep.f !== "never" ? " Every repeat goes with it." : "")
                            color: root.txt2
                            font.family: Theme.fontMono
                            font.pixelSize: 11
                        }
                        Row {
                            id: askBtns
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 6
                            Btn { label: "Delete"; kind: "danger"; onClicked: root.del() }
                            Btn { label: "Cancel"; kind: "quiet"; onClicked: { root.ask = false; root.focusTitle(); } }
                        }
                    }
                }
            }
        }
    }

    // ═══ A NOTE ON THE MOVE ═════════════════════════════════
    // No animation: it is under the pointer, exactly, and lands on release.
    property int dragId: -1
    property int dragFrom: 0
    property int dragOver: -1
    property string dragText: ""
    function drop(id, from, to) {
        dragId = -1; dragOver = -1;
        home();
        if (to >= 0 && to !== from) { sel = to; Notes.move(id, from, to); }
    }
    Rectangle {
        id: ghost
        visible: root.dragId >= 0
        z: 10
        width: Math.min(160, gt.implicitWidth + 14)
        height: 19
        radius: 5
        color: Qt.rgba(40 / 255, 52 / 255, 50 / 255, 0.96)
        border.width: 1
        border.color: Qt.rgba(228 / 255, 238 / 255, 236 / 255, 0.18)
        Text {
            id: gt
            x: 7
            width: parent.width - 14
            anchors.verticalCenter: parent.verticalCenter
            elide: Text.ElideRight
            text: root.dragText
            color: root.txt
            font.family: Theme.fontSans
            font.pixelSize: 11
        }
    }

    // ═══ PIECES ═════════════════════════════════════════════

    // A day in the month. Its number and as many notes as fit, names
    // only: the month answers WHICH DAY, the day page answers the rest.
    // The whole day is the button -- round four's + is gone.
    component Day: Rectangle {
        id: day
        required property int index
        readonly property int k: root.start + index
        readonly property var p: Notes.from(k)
        readonly property bool oth: p.m !== root.vm
        readonly property bool isSel: k === root.sel
        readonly property bool isDrop: root.dragId >= 0 && root.dragOver === k
        readonly property var notes: { Notes.list; return Notes.onDay(k); }
        readonly property int shown: notes.length > root.cap ? root.cap - 1 : notes.length

        x: root.cellX(index)
        y: root.cellY(index)
        width: root.cellW
        height: root.cellH
        radius: 7
        color: isDrop ? Qt.rgba(1, 1, 1, 0.10) : isSel ? Theme.panelCursor
             : (dm.containsMouse && root.dragId < 0) ? Qt.rgba(1, 1, 1, 0.045) : Qt.rgba(1, 1, 1, 0)
        border.width: isDrop || isSel ? 1 : 0
        border.color: isDrop ? Qt.rgba(1, 1, 1, 0.32) : Qt.rgba(1, 1, 1, 0.11)
        Behavior on color { enabled: Anim.enabled; ColorAnimation { duration: Anim.ms(Anim.hover) } }

        // One press opens the day. (The user's ask, round five.)
        MouseArea {
            id: dm
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onPressed: root.openDay(day.k)
        }

        Text {
            x: 7
            y: 4
            height: 16
            verticalAlignment: Text.AlignVCenter
            text: day.p.d
            color: day.k === Notes.today ? Theme.accent : root.txt
            opacity: day.oth && day.k !== Notes.today ? 0.45 : 1
            font.family: Theme.fontMono
            font.pixelSize: 11
            font.weight: day.k === Notes.today ? Font.DemiBold : Font.Normal
            font.features: ({ "tnum": 1 })
        }

        Column {
            x: 4
            y: 22
            width: parent.width - 8
            spacing: 2
            Repeater {
                model: day.notes.slice(0, day.shown)
                delegate: Rectangle {
                    id: chip
                    required property var modelData
                    width: parent.width
                    height: 17
                    radius: 4
                    opacity: root.dragId === modelData.id ? 0.35 : 1
                    color: cm.containsMouse && root.dragId < 0 ? Qt.rgba(1, 1, 1, 0.11) : Qt.rgba(1, 1, 1, 0.06)
                    Behavior on color { enabled: Anim.enabled; ColorAnimation { duration: Anim.ms(Anim.hover) } }
                    Text {
                        x: 5
                        width: parent.width - 10
                        anchors.verticalCenter: parent.verticalCenter
                        elide: Text.ElideRight
                        text: chip.modelData.title
                        color: day.k < Notes.today ? root.txt2 : root.txt
                        font.family: Theme.fontSans
                        font.pixelSize: 11
                    }
                    // A press that moves 5 px is a drag; one that does not
                    // opens the day with this note ready to change, on
                    // release. The one control here that answers on release,
                    // because a drag starts with a press.
                    MouseArea {
                        id: cm
                        anchors.fill: parent
                        hoverEnabled: true
                        preventStealing: true
                        cursorShape: root.dragId >= 0 ? Qt.ClosedHandCursor : Qt.PointingHandCursor
                        property point at
                        onPressed: mouse => at = Qt.point(mouse.x, mouse.y)
                        onPositionChanged: mouse => {
                            if (!pressed) return;
                            if (root.dragId < 0) {
                                if (Math.abs(mouse.x - at.x) + Math.abs(mouse.y - at.y) < 5) return;
                                root.dragId = chip.modelData.id; root.dragFrom = day.k; root.dragText = chip.modelData.title;
                            }
                            const q = mapToItem(root, mouse.x, mouse.y);
                            ghost.x = q.x + 10; ghost.y = q.y - 10;
                            root.dragOver = root.cellAt(q.x, q.y);
                        }
                        onReleased: mouse => {
                            if (root.dragId < 0) root.openDay(day.k, chip.modelData.id);
                            else root.drop(root.dragId, root.dragFrom, root.dragOver);
                        }
                        onCanceled: { root.dragId = -1; root.dragOver = -1; }
                    }
                }
            }
            // "+3 more" opens the day with all of them.
            Rectangle {
                visible: day.notes.length > day.shown
                width: mt.implicitWidth + 10
                height: 15
                radius: 4
                color: mm.containsMouse ? Qt.rgba(1, 1, 1, 0.07) : Qt.rgba(1, 1, 1, 0)
                Text {
                    id: mt
                    x: 5
                    anchors.verticalCenter: parent.verticalCenter
                    text: "+" + (day.notes.length - day.shown) + " more"
                    color: mm.containsMouse ? root.txt : root.txt2
                    font.family: Theme.fontMono
                    font.pixelSize: 10
                }
                MouseArea {
                    id: mm
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onPressed: root.openDay(day.k)
                }
            }
        }
    }

    // A note on the day page: its time in a column of its own, the
    // title, up to four lines of details, and one line saying when it
    // reminds and how it repeats. Press it to change it.
    component NoteRow: Rectangle {
        id: nr
        property var n: null
        readonly property bool past: root.sel < Notes.today
        readonly property string rt: n ? Notes.remindText(n) : ""
        readonly property string rp: n ? Notes.repText(n.rep, n.key) : ""
        width: parent ? parent.width : 0
        height: col.implicitHeight + 18
        radius: 9
        color: nm.containsMouse ? Qt.rgba(1, 1, 1, 0.045) : Qt.rgba(1, 1, 1, 0)
        Behavior on color { enabled: Anim.enabled; ColorAnimation { duration: Anim.ms(Anim.hover) } }

        MouseArea {
            id: nm
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onPressed: root.editNote(nr.n.id)
        }
        Text {
            x: 10
            y: 9
            width: 44
            height: 19
            verticalAlignment: Text.AlignVCenter
            text: nr.n ? nr.n.time : ""
            color: nr.past ? root.txt2 : root.txt
            font.family: Theme.fontMono
            font.pixelSize: 12
            font.weight: Font.Medium
            font.features: ({ "tnum": 1 })
        }
        Column {
            id: col
            x: 64
            y: 9
            width: parent.width - x - 10
            spacing: 3
            Text {
                width: parent.width
                text: nr.n ? nr.n.title : ""
                wrapMode: Text.WrapAtWordBoundaryOrAnywhere
                lineHeight: 19
                lineHeightMode: Text.FixedHeight
                color: nr.past ? root.txt2 : root.txt
                font.family: Theme.fontSans
                font.pixelSize: 14
                font.weight: Font.Medium
            }
            Text {
                visible: text !== ""
                width: parent.width
                text: nr.n ? nr.n.body : ""
                wrapMode: Text.WrapAtWordBoundaryOrAnywhere
                maximumLineCount: 4
                elide: Text.ElideRight
                lineHeight: 1.35
                color: root.body2
                font.family: Theme.fontSans
                font.pixelSize: 13
            }
            Flow {
                visible: nr.rt !== "" || nr.rp !== ""
                width: parent.width
                spacing: 14
                topPadding: 2
                Row {
                    visible: nr.rt !== ""
                    spacing: 4
                    Icon { anchors.verticalCenter: parent.verticalCenter; name: "bell-fill"; size: 12; color: root.txt2 }
                    Text { text: nr.rt; color: root.txt2; font.family: Theme.fontMono; font.pixelSize: 11 }
                }
                Row {
                    visible: nr.rp !== ""
                    spacing: 4
                    Icon { anchors.verticalCenter: parent.verticalCenter; name: "refresh"; size: 12; color: root.txt2 }
                    Text { text: nr.rp; color: root.txt2; font.family: Theme.fontMono; font.pixelSize: 11 }
                }
            }
        }
    }

    // One line of the editor's rows: a small-caps label, then its chips,
    // which wrap under themselves rather than under the label.
    component Line: Item {
        id: ln
        property string lab: ""
        default property alias chips: fl.data
        width: parent ? parent.width : 0
        height: Math.max(26, fl.implicitHeight)
        Text {
            width: 60
            height: 26
            verticalAlignment: Text.AlignVCenter
            text: ln.lab
            color: root.txt2
            font.family: Theme.fontCaps
            font.pixelSize: 9
            font.weight: Theme.capsWeight
            font.letterSpacing: 1.4
            font.capitalization: Font.AllUppercase
        }
        Flow {
            id: fl
            x: 65
            y: 1
            width: parent.width - x
            spacing: 5
        }
    }

    // A chip in the editor: a word, or a square with one letter or a glyph.
    component Ch: Rectangle {
        id: c
        property string label: ""
        property string icon: ""
        property real turn: 0
        property bool on: false
        property bool sq: false
        signal pressed()
        width: sq ? 26 : ct.implicitWidth + 18
        height: 24
        radius: 7
        color: c.on ? Qt.rgba(1, 1, 1, 0.15) : chm.containsMouse ? Qt.rgba(1, 1, 1, 0.10) : Qt.rgba(1, 1, 1, 0.06)
        Behavior on color { enabled: Anim.enabled; ColorAnimation { duration: Anim.ms(Anim.hover) } }
        Text {
            id: ct
            visible: c.icon === ""
            anchors.centerIn: parent
            text: c.label
            color: c.on || chm.containsMouse ? root.txt : root.txt2
            font.family: Theme.fontMono
            font.pixelSize: 11
            font.features: ({ "tnum": 1 })
        }
        Icon {
            visible: c.icon !== ""
            anchors.centerIn: parent
            name: c.icon || "x"
            size: 13
            rotation: c.turn
            color: chm.containsMouse ? root.txt : root.txt2
        }
        MouseArea {
            id: chm
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onPressed: c.pressed()
        }
    }

    // A glyph you press: the month's arrows, the day's arrows.
    component IconBtn: Rectangle {
        id: ib
        property string icon: "x"
        property real turn: 0
        property int side: 26
        property int wide: side
        property int iconSize: 14
        signal clicked()
        width: wide
        height: side
        radius: 5
        color: im.containsMouse ? Qt.rgba(1, 1, 1, 0.10) : Qt.rgba(1, 1, 1, 0)
        Behavior on color { enabled: Anim.enabled; ColorAnimation { duration: Anim.ms(Anim.hover) } }
        Icon {
            anchors.centerIn: parent
            name: ib.icon
            size: ib.iconSize
            rotation: ib.turn
            color: im.containsMouse ? root.txt : root.txt2
        }
        MouseArea {
            id: im
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onPressed: ib.clicked()
        }
    }
}
