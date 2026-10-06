pragma Singleton

// ═══════════════════════════════════════════════════════════════
// NOTES — what the calendar holds, and the reminders it fires.
//
// Datum Panels, Time & Date round four (2026-09-28), and round five
// (2026-09-30): a repeat is an object now, and a reminder can come
// early. The panel draws them (CalendarPanel.qml); this file keeps
// them, reads a typed line, and says a note's name when its time comes.
//
// ── THE FILE ─────────────────────────────────────────────────
// ~/.local/share/datum/notes.json, one object:
//     { "next": 7, "notes": [ { "id": 3, "title": "Dentist",
//       "body": "", "date": "2026-10-03", "time": "14:30", "remind": 60,
//       "rep": { "f": "week", "n": 1, "days": [1, 3], "mby": "date",
//                "until": "2026-12-31" } }, ... ] }
// A date is written as a date, not as the day number the code counts
// in, so the file can be read and fixed by hand. A file that does not
// parse is NEVER written over: the calendar comes up empty and says
// nothing is saved, and your notes are still in the file.
//
// ROUND FOUR'S FILE IS CONVERTED ONCE, WHEN READ. Its rep was a word
// ("weekly", "everyN" + repN); "weekly" becomes weekly on that note's
// own weekday, "everyN" becomes daily every N, and every timed note
// reminds at its time, which is what it did. The old file is copied
// to notes.json.bak before the first write in the new shape.
//
// ── DAYS ARE WHOLE NUMBERS ───────────────────────────────────
// A day is its count from 1970-01-01, taken in UTC so a day is always
// 86 400 000 ms and daylight saving cannot make one 23 hours long.
// Today is read off the LOCAL clock and converted, every 15 s.
//
// ── A REPEAT IS ONE NOTE ─────────────────────────────────────
//   f      never | day | week | month | year
//   n      every N of them (every other week is 2)
//   days   week only: which weekdays, 0 = Sunday. Empty = the note's own.
//   mby    month only: "date" (the 29th), "nth" (the 5th Tuesday...
//          the 1st Thursday), "last" (the last Tuesday)
//   until  a day, 0 for never. The last day it can land on.
// Daily COUNTS DAYS; weekly counts WEEKS from the note's own Monday,
// so "every other week on Mon, Wed" keeps both days in the same week.
// Monthly and yearly are DATES -- a birthday is 26 September, not 365
// days after the last one. The 31st lands on the last day of a short
// month; 29 February lands on 1 March in the other three years.
// ═══════════════════════════════════════════════════════════════

import Quickshell
import Quickshell.Io
import QtQuick

Singleton {
    id: root

    property var list: []
    property int next: 1
    // false until the file has been read (or found missing), and false
    // for good if it did not parse -- nothing is written over it then.
    property bool writable: false
    property bool broken: false
    // true when the file on disk is round four's shape; the first store()
    // copies it to .bak before writing the new one.
    property bool oldShape: false

    property int today: localToday()
    Timer {
        interval: 15000
        running: true
        repeat: true
        onTriggered: { root.today = root.localToday(); root.fire(); }
    }

    // ── DAYS ─────────────────────────────────────────────────
    readonly property var monthNames: ["January", "February", "March", "April", "May", "June", "July",
                                       "August", "September", "October", "November", "December"]
    readonly property var dayNames: ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"]

    function key(y, m, d) { return Math.round(Date.UTC(y, m, d) / 86400000); }
    function from(k) { const t = new Date(k * 86400000); return { y: t.getUTCFullYear(), m: t.getUTCMonth(), d: t.getUTCDate() }; }
    function wd(k) { return new Date(k * 86400000).getUTCDay(); }
    function dim(y, m) { return new Date(Date.UTC(y, m + 1, 0)).getUTCDate(); }
    function leap(y) { return (y % 4 === 0 && y % 100 !== 0) || y % 400 === 0; }
    function localToday() { const n = new Date(); return key(n.getFullYear(), n.getMonth(), n.getDate()); }
    function pad(n) { return (n < 10 ? "0" : "") + n; }
    function iso(k) { const p = from(k); return p.y + "-" + pad(p.m + 1) + "-" + pad(p.d); }
    function unIso(s, dflt) { const m = /^(\d{4})-(\d\d)-(\d\d)$/.exec(s || ""); return m ? key(+m[1], +m[2] - 1, +m[3]) : dflt; }
    function monday(k) { return k - (wd(k) + 6) % 7; }
    function mins(t) { return +t.slice(0, 2) * 60 + +t.slice(3, 5); }
    function hm(m) { m = ((m % 1440) + 1440) % 1440; return pad(Math.floor(m / 60)) + ":" + pad(m % 60); }
    function ord(n) { const s = ["th", "st", "nd", "rd"], v = n % 100; return n + (s[(v - 20) % 10] || s[v] || s[0]); }

    // "Today", "Tomorrow", "Yesterday", or "Sat 3 Oct".
    function short(k) {
        if (k === today) return "Today";
        if (k === today + 1) return "Tomorrow";
        if (k === today - 1) return "Yesterday";
        const p = from(k);
        return dayNames[wd(k)].slice(0, 3) + " " + p.d + " " + monthNames[p.m].slice(0, 3);
    }
    // "Saturday 3 October"
    function long(k) { const p = from(k); return dayNames[wd(k)] + " " + p.d + " " + monthNames[p.m]; }

    // ── A REPEAT ─────────────────────────────────────────────
    function rep0() { return { f: "never", n: 1, days: [], mby: "date", until: 0 }; }
    function cloneRep(r) {
        r = r || rep0();
        return { f: r.f || "never", n: r.n || 1, days: (r.days || []).slice(), mby: r.mby || "date", until: r.until || 0 };
    }
    // Monday first, the way the week strip and the toggles read.
    function sortDays(d) { return d.slice().sort((x, y) => ((x + 6) % 7) - ((y + 6) % 7)); }

    // "Every weekday", "Every other week on Mon, Wed", "Monthly on the
    // last Tuesday · until 31 Dec". The words the note's line says.
    function repText(r, k) {
        if (!r || r.f === "never") return "";
        const N = r.n || 1, p = from(k), wdN = dayNames[wd(k)];
        let s;
        if (r.f === "day") s = N === 1 ? "Every day" : "Every " + N + " days";
        else if (r.f === "week") {
            const d = sortDays(r.days.length ? r.days : [wd(k)]);
            const wk = d.join() === "1,2,3,4,5";
            const lead = N === 1 ? "Every " : N === 2 ? "Every other week on " : "Every " + N + " weeks on ";
            if (d.length === 7 && N === 1) s = "Every day";
            else if (wk && N === 1) s = "Every weekday";
            else if (d.length === 1) s = (N === 1 ? "Every " : N === 2 ? "Every other " : "Every " + N + " weeks on ") + dayNames[d[0]];
            else s = lead + (wk ? "weekdays" : d.map(x => dayNames[x].slice(0, 3)).join(", "));
        } else if (r.f === "month") {
            const on = r.mby === "nth" ? "the " + ord(Math.ceil(p.d / 7)) + " " + wdN
                     : r.mby === "last" ? "the last " + wdN : "the " + ord(p.d);
            s = (N === 1 ? "Monthly" : "Every " + N + " months") + " on " + on;
        } else s = (N === 1 ? "Every year" : "Every " + N + " years") + " on " + p.d + " " + monthNames[p.m];
        if (r.until) { const u = from(r.until); s += " · until " + u.d + " " + monthNames[u.m].slice(0, 3); }
        return s;
    }

    // ── A REMINDER ───────────────────────────────────────────
    // Minutes before the note's time; -1 is off. A note without a time
    // has no reminder, whatever this says.
    readonly property var remindSteps: [[0, "At the time"], [15, "15 min before"], [60, "1 h before"],
                                        [1440, "The day before"], [-1, "Off"]]
    function remindText(n) {
        if (!n.time || n.remind < 0) return "";
        if (!n.remind) return "Reminds at " + n.time;
        if (n.remind === 1440) return "Reminds the day before, " + n.time;
        return "Reminds " + hm(mins(n.time) - n.remind) + " · " + (n.remind === 60 ? "1 h" : n.remind + " min") + " before";
    }

    // ── WHICH NOTES ARE ON A DAY ─────────────────────────────
    function on(n, k) {
        if (n.key === k) return true;
        const r = n.rep;
        if (!r || r.f === "never" || k < n.key) return false;
        if (r.until && k > r.until) return false;
        const N = Math.max(1, r.n || 1), a = from(n.key), b = from(k);
        if (r.f === "day") return (k - n.key) % N === 0;
        if (r.f === "week") {
            const days = r.days.length ? r.days : [wd(n.key)];
            if (days.indexOf(wd(k)) < 0) return false;
            return ((monday(k) - monday(n.key)) / 7) % N === 0;
        }
        if (r.f === "month") {
            if (((b.y - a.y) * 12 + (b.m - a.m)) % N) return false;
            const m = dim(b.y, b.m);
            if (r.mby === "nth") return wd(k) === wd(n.key) && Math.ceil(b.d / 7) === Math.ceil(a.d / 7);
            if (r.mby === "last") return wd(k) === wd(n.key) && b.d + 7 > m;
            return a.d === b.d || (a.d > m && b.d === m);
        }
        if ((b.y - a.y) % N) return false;
        if (a.m === 1 && a.d === 29 && !leap(b.y)) return b.m === 2 && b.d === 1;
        return a.m === b.m && a.d === b.d;
    }
    // Timed notes first, in time order; then untimed, oldest first.
    function onDay(k) {
        return list.filter(n => on(n, k)).sort((a, b) => {
            const x = a.time || "99", y = b.time || "99";
            return x < y ? -1 : x > y ? 1 : a.id - b.id;
        });
    }
    function find(id) { for (let i = 0; i < list.length; i++) if (list[i].id === id) return list[i]; return null; }

    // ── CHANGING THEM ────────────────────────────────────────
    // Every change replaces `list`, so every binding that reads it redraws.
    function clean(id, r) {
        const rep = cloneRep(r.rep);
        if (rep.f === "week" && !rep.days.length) rep.days = [wd(r.key)];
        if (rep.f === "never") rep.until = 0;
        return { id: id, title: r.title, body: r.body || "", key: r.key, time: r.time || "",
                 remind: r.time ? (r.remind === undefined ? 0 : r.remind) : 0, rep: rep };
    }
    function add(r) {
        list = list.concat([clean(next, r)]);
        next++;
        store();
    }
    function update(id, r) {
        list = list.map(n => n.id !== id ? n : clean(id, r));
        store();
    }
    function remove(id) { list = list.filter(n => n.id !== id); store(); }
    // A dragged note moves by the days it was dragged, so a repeating one
    // moves its whole series and keeps its rhythm -- a Mon/Wed/Fri series
    // dragged one day on is Tue/Thu/Sat.
    function move(id, fromKey, toKey) {
        const dd = toKey - fromKey, sh = ((dd % 7) + 7) % 7;
        list = list.map(n => {
            if (n.id !== id) return n;
            const rep = cloneRep(n.rep);
            if (rep.f === "week") rep.days = rep.days.map(x => (x + sh) % 7);
            return Object.assign({}, n, { key: n.key + dd, rep: rep });
        });
        store();
    }

    function store() {
        if (!writable) return;
        if (oldShape) {
            // The one copy of round four's file, taken before it is
            // replaced -- from the text as read, in this process, so it
            // cannot race the write below the way a spawned cp would.
            bak.setText(oldText);
            oldShape = false;
        }
        file.setText(JSON.stringify({ next: next, notes: list.map(n => ({
            id: n.id, title: n.title, body: n.body, date: iso(n.key), time: n.time, remind: n.remind,
            rep: { f: n.rep.f, n: n.rep.n, days: n.rep.days, mby: n.rep.mby, until: n.rep.until ? iso(n.rep.until) : "" }
        })) }, null, 1) + "\n");
    }

    readonly property string dir: Quickshell.env("HOME") + "/.local/share/datum"
    Component.onCompleted: Quickshell.execDetached(["mkdir", "-p", dir])

    // Round four's word, or round five's object, into the object.
    function readRep(n, k) {
        const r = n.rep;
        if (r && typeof r === "object")
            return { f: r.f || "never", n: Math.max(1, r.n || 1), days: (r.days || []).slice(), mby: r.mby || "date",
                     until: r.until ? unIso(r.until, 0) : 0 };
        oldShape = true;
        const o = rep0();
        if (r === "weekly") { o.f = "week"; o.days = [wd(k)]; }
        else if (r === "monthly") o.f = "month";
        else if (r === "yearly") o.f = "year";
        else if (r === "everyN") { o.f = "day"; o.n = Math.max(1, n.repN || 1); }
        return o;
    }

    property string oldText: ""
    FileView { id: bak; path: root.dir + "/notes.json.bak"; preload: false; printErrors: false }

    FileView {
        id: file
        path: root.dir + "/notes.json"
        onLoaded: {
            try {
                root.oldText = text();
                const o = JSON.parse(root.oldText);
                root.list = (o.notes || []).map(n => {
                    const k = root.unIso(n.date, root.today);
                    if (n.remind === undefined) root.oldShape = true;
                    return { id: n.id, title: n.title || "", body: n.body || "", key: k, time: n.time || "",
                             remind: n.remind === undefined ? 0 : n.remind, rep: root.readRep(n, k) };
                });
                root.next = Math.max(o.next || 1, ...root.list.map(n => n.id + 1), 1);
                root.writable = true;
            } catch (e) {
                root.broken = true;
                console.warn("notes.json does not parse; it will not be written over:", e);
            }
        }
        // No file yet is the first run, not an error.
        onLoadFailed: err => { if (err === FileViewError.FileNotFound) root.writable = true; else root.broken = true; }
    }

    // ── THE REMINDER ─────────────────────────────────────────
    // A timed note says its name at its time less its remind minutes,
    // through dunst like everything else on this desktop. Checked every
    // 15 s, so it lands in the right minute; each occurrence fires once.
    // The day before is found the same way as fifteen minutes before:
    // the occurrence is the day that puts the reminder at THIS minute.
    // A minute the machine slept through is not fired late -- a reminder
    // an hour after the dentist is noise.
    property var fired: ({})
    function fire() {
        const n = new Date(), now = n.getHours() * 60 + n.getMinutes();
        list.forEach(x => {
            if (!x.time || x.remind < 0) return;
            const dd = now + x.remind - mins(x.time);
            if (dd % 1440 !== 0) return;
            const occ = today + dd / 1440, tag = x.id + "@" + occ;
            if (fired[tag] || !on(x, occ)) return;
            fired[tag] = true;
            const first = (x.body || "").split("\n")[0].trim();
            const when = x.remind === 1440 ? "Tomorrow at " + x.time : "At " + x.time;
            Quickshell.execDetached(["notify-send", "-a", "Calendar", x.title, first || when]);
        });
    }

    // ═══ READING A TYPED LINE ═══════════════════════════════
    // Round three's parser (T15), plus round five's words (T32): an end
    // ("until 30/10"), then a repeat, then a time, then a date, each probe
    // run against a copy with the earlier matches BLANKED at the same
    // indices -- so "every 3 days" never has its 3 read as a clock, and
    // the spans stay aligned with what you typed.
    readonly property var wdWords: ({ sunday: 0, sun: 0, monday: 1, mon: 1, tuesday: 2, tues: 2, tue: 2,
        wednesday: 3, weds: 3, wed: 3, thursday: 4, thurs: 4, thur: 4, thu: 4, friday: 5, fri: 5, saturday: 6, sat: 6 })
    readonly property var moWords: ({ january: 0, jan: 0, february: 1, feb: 1, march: 2, mar: 2, april: 3, apr: 3,
        may: 4, june: 5, jun: 5, july: 6, jul: 6, august: 7, aug: 7, september: 8, sept: 8, sep: 8,
        october: 9, oct: 9, november: 10, nov: 10, december: 11, dec: 11 })
    readonly property string wdRe: "sunday|sun|monday|mon|tuesday|tues|tue|wednesday|weds|wed|thursday|thurs|thur|thu|friday|fri|saturday|sat"
    readonly property string moRe: "january|jan|february|feb|march|mar|april|apr|may|june|jun|july|jul|august|aug|september|sept|sep|october|oct|november|nov|december|dec"

    // A day and month with no year: this year's, or next year's if it
    // has already gone. 0 when it is not a date.
    function dm(d, mo) {
        const y = from(today).y;
        if (mo < 0 || mo > 11 || d < 1 || d > dim(y, mo)) return 0;
        const k = key(y, mo, d);
        return k < today ? key(y + 1, mo, d) : k;
    }

    function quick(str) {
        const T = today, r = { key: null, time: "", rep: null, until: 0, sp: [] };
        if (!str) return r;
        let w = str, m;
        const eat = tag => {
            r.sp.push([m.index, m.index + m[0].length, tag]);
            w = w.slice(0, m.index) + " ".repeat(m[0].length) + w.slice(m.index + m[0].length);
        };
        const R = (f, n, days) => ({ f: f, n: n, days: days || [], mby: "date", until: 0 });
        // THE END first -- "until 30/10" must not be read as the note's date
        if ((m = /\buntil\s+(\d{1,2})[\/.](\d{1,2})\b/i.exec(w))) { const u = dm(+m[1], +m[2] - 1); if (u) { r.until = u; eat("rep"); } }
        else if ((m = new RegExp("\\buntil\\s+(\\d{1,2})\\s+(" + moRe + ")\\b", "i").exec(w))) {
            const u = dm(+m[1], moWords[m[2].toLowerCase()]); if (u) { r.until = u; eat("rep"); }
        }
        // REPEAT -- it owns its digits before the clock sees them
        const WD = "(?:" + wdRe + ")";
        if ((m = /\b(?:every\s+weekdays?|weekdays)\b/i.exec(w))) { r.rep = R("week", 1, [1, 2, 3, 4, 5]); eat("rep"); }
        else if ((m = new RegExp("\\bevery\\s+(other\\s+)?(" + WD + "(?:\\s*(?:,|and|&|\\+)\\s*" + WD + ")*)\\b", "i").exec(w))) {
            const ds = [];
            m[2].toLowerCase().split(/\s*(?:,|and|&|\+)\s*/).forEach(x => { const v = wdWords[x.trim()]; if (v !== undefined && ds.indexOf(v) < 0) ds.push(v); });
            r.rep = R("week", m[1] ? 2 : 1, ds); eat("rep");
        }
        else if ((m = /\bevery\s+(other|\d{1,3})\s*(days?|d|weeks?|months?|years?)\b/i.exec(w))) {
            const u = m[2].toLowerCase(), f = u[0] === "w" ? "week" : u[0] === "m" ? "month" : u[0] === "y" ? "year" : "day";
            r.rep = R(f, /other/i.test(m[1]) ? 2 : Math.max(1, +m[1])); eat("rep");
        }
        else if ((m = /\b(?:every\s+(day|week|month|year)|(daily|weekly|monthly|yearly))\b/i.exec(w))) {
            const u = (m[1] || m[2]).toLowerCase();
            r.rep = R(({ daily: "day", weekly: "week", monthly: "month", yearly: "year" })[u] || u, 1); eat("rep");
        }
        if (r.rep && r.until) r.rep.until = r.until;
        // TIME
        if ((m = /(?:\bat\s+)?\b([01]?\d|2[0-3])[:.]([0-5]\d)\b/.exec(w))) { r.time = pad(+m[1]) + ":" + m[2]; eat("time"); }
        else if ((m = /(?:\bat\s+)?\b(1[0-2]|0?[1-9])(?:[:.]([0-5]\d))?\s*(am|pm)\b/i.exec(w))) {
            let hh = (+m[1]) % 12; if (/p/i.test(m[3])) hh += 12;
            r.time = pad(hh) + ":" + (m[2] || "00"); eat("time");
        }
        // DATE
        if ((m = /\btoday\b/i.exec(w))) { r.key = T; eat("date"); }
        else if ((m = /\b(?:tomorrow|tmrw|tmr|tmw)\b/i.exec(w))) { r.key = T + 1; eat("date"); }
        else if ((m = /\bin\s+(\d{1,3})\s*(days?|weeks?|months?)\b/i.exec(w))) {
            const n = +m[1], un = m[2].toLowerCase(), p0 = from(T);
            r.key = un.indexOf("week") === 0 ? T + n * 7
                  : un.indexOf("month") === 0 ? key(p0.y, p0.m + n, Math.min(p0.d, dim(p0.y, p0.m + n)))
                  : T + n;
            eat("date");
        }
        else if ((m = new RegExp("\\b(?:next\\s+|on\\s+)?(" + wdRe + ")\\b", "i").exec(w))) {
            // a bare weekday means THE NEXT ONE, never today
            let dd = (wdWords[m[1].toLowerCase()] - wd(T) + 7) % 7; if (!dd) dd = 7;
            r.key = T + dd; eat("date");
        }
        else if ((m = /\b(\d{1,2})[\/.](\d{1,2})(?:[\/.](\d{2,4}))?\b/.exec(w))) {
            const d1 = +m[1], mo = +m[2] - 1, yy = m[3] ? (+m[3] < 100 ? 2000 + (+m[3]) : +m[3]) : 0;
            const k = yy ? (mo >= 0 && mo < 12 && d1 >= 1 && d1 <= dim(yy, mo) ? key(yy, mo, d1) : 0) : dm(d1, mo);
            if (k) { r.key = k; eat("date"); }
        }
        else if ((m = new RegExp("\\b(\\d{1,2})\\s+(" + moRe + ")\\b", "i").exec(w)) ||
                 (m = new RegExp("\\b(" + moRe + ")\\s+(\\d{1,2})\\b", "i").exec(w))) {
            const num = /^\d+$/.test(m[1]), k = dm(num ? +m[1] : +m[2], moWords[(num ? m[2] : m[1]).toLowerCase()]);
            if (k) { r.key = k; eat("date"); }
        }
        r.sp.sort((a, b) => a[0] - b[0]);
        return r;
    }

    // WHAT A DRAFT ACTUALLY HOLDS. The parser's claim on a field dies the
    // moment that field is set by hand -- the words go back to being part
    // of the name, so the two can never disagree. Round three, §15.2.
    //   d: { title, key, time, rep, setDate, setTime, setRep }
    function resolve(d) {
        const q = quick(d.title), live = [];
        let k = d.key, time = d.time, rep = d.rep, words = false, dated = false;
        q.sp.forEach(s => {
            if (s[2] === "date" && !d.setDate) { k = q.key; live.push(s); dated = true; }
            else if (s[2] === "time" && !d.setTime) { time = q.time; live.push(s); }
            else if (s[2] === "rep" && !d.setRep && (q.rep || q.until)) {
                // "until 30/10" alone ends whatever repeat the draft already has
                rep = q.rep || Object.assign(cloneRep(d.rep), { until: q.until });
                words = true; live.push(s);
            }
        });
        // "Gym every mon, wed" starts on the first of those days from the
        // day you are on, not on a day it does not repeat.
        if (words && !dated && !d.setDate && rep.f === "week" && rep.days.length && rep.days.indexOf(wd(k)) < 0)
            for (let i = 1; i < 7; i++) if (rep.days.indexOf(wd(k + i)) >= 0) { k += i; break; }
        let t = d.title;
        for (let i = live.length - 1; i >= 0; i--) t = t.slice(0, live[i][0]) + t.slice(live[i][1]);
        return { title: t.replace(/\s{2,}/g, " ").trim(), sp: live, key: k, time: time, rep: cloneRep(rep) };
    }
}
