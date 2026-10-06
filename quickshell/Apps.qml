pragma Singleton

// ═══════════════════════════════════════════════════════════════
// APPS — what the Search panel reads and does: the index, how often you
// open each app, the ranking, and the launch.
//
// NOT Quickshell's DesktopEntries. 0.3.1 has it, and it was probed on
// 2026-09-16 before this was written: its entry has no OnlyShowIn,
// TryExec, DBusActivatable or SingleMainWindow. Those four are how
// apps.py gets to 62 apps rather than the 234 .desktop files on disk,
// and the last two are how it knows which six apps go to their window
// instead of opening a second one (launcher.md §6 -- the rule that ate the
// launcher when it was applied to all 62). So apps.py stays the index and
// this reads its cache:
//
//   ~/.cache/eww/apps.json         the 62, with raw Categories=, the
//                                  resolved Papirus icon path, `single`
//   ~/.cache/eww/apps-usage.json   {desktop id: frecency}, bumped by launch
//
// Both are FileViews that watch the file, so a launch, or a rebuild after
// a package install, shows on the next open without asking anything.
//
// THE RANKING IS apps.py's rank(), ported line for line, because it runs
// on every key and a python start per key is what made eww's list lag the
// field (launcher.md §2). In here it is a scan of 62 objects in memory.
//
// Two things shell out, and neither is on a key: `apps.py panel` once per
// open (rebuild if stale, and which of the six have a window to go to),
// and `apps.py launch` on Enter.
// ═══════════════════════════════════════════════════════════════

import Quickshell
import Quickshell.Io
import QtQuick

Singleton {
    id: root

    readonly property string py: Quickshell.env("HOME") + "/.config/eww/scripts/apps.py"

    // apps.py's CATS: the token, the tab's word, and the Categories=
    // values that count as that bucket. Order is Alt+1…6.
    readonly property var cats: [
        { tok: "sys",   label: "System",   want: ["System"] },
        { tok: "util",  label: "Utility",  want: ["Utility"] },
        { tok: "dev",   label: "Dev",      want: ["Development"] },
        { tok: "net",   label: "Network",  want: ["Network"] },
        { tok: "set",   label: "Settings", want: ["Settings"] },
        { tok: "media", label: "Media",    want: ["AudioVideo", "Audio", "Video"] }
    ]
    function catLabel(tok) {
        const c = cats.find(c => c.tok === tok);
        return c ? c.label : "";
    }

    property var list: []
    property var usage: ({})
    // {desktop file: workspace name}, for the apps whose Enter goes to a
    // window. Read on open; see apps.py `panel`.
    property var windows: ({})

    FileView {
        path: Quickshell.env("HOME") + "/.cache/eww/apps.json"
        watchChanges: true
        onFileChanged: reload()
        onLoaded: { try { root.list = JSON.parse(text()); } catch (e) {} }
    }
    FileView {
        path: Quickshell.env("HOME") + "/.cache/eww/apps-usage.json"
        watchChanges: true
        onFileChanged: reload()
        onLoaded: { try { root.usage = JSON.parse(text()); } catch (e) {} }
    }

    Process {
        id: panelProc
        command: ["setpriv", "--pdeathsig", "TERM", "python3", root.py, "panel"]
        stdout: StdioCollector {
            onStreamFinished: { try { root.windows = JSON.parse(text); } catch (e) { root.windows = {}; } }
        }
    }

    function opened() {
        windows = {};
        panelProc.running = true;
    }

    function launch(app) {
        Quickshell.execDetached(["python3", py, "launch", app.file]);
    }

    function use(app) { return usage[app.id] || 0; }

    // ── apps.py split_token ──────────────────────────────────
    // A `:tok` anywhere in the query filters, by unambiguous prefix; `:s`
    // is ambiguous and `:zz` unknown, and both filter nothing rather than
    // emptying the list between the colon and the third key.
    function splitToken(q) {
        let tok = "";
        const rest = q.replace(/:([A-Za-z]*)/g, (m, head) => {
            head = head.toLowerCase();
            if (!tok && head) {
                const hits = cats.filter(c => c.tok.startsWith(head));
                if (hits.length === 1) tok = hits[0].tok;
            }
            return " ";
        });
        return { tok: tok, text: rest.trim() };
    }

    function inCat(app, tok) {
        const want = cats.find(c => c.tok === tok).want;
        return (app.cats || []).some(c => want.indexOf(c) >= 0);
    }

    // ── apps.py rank ─────────────────────────────────────────
    // Returns [{app, tier, at, where}], where `at` is where the typed text
    // starts in the name ("n") or the generic name ("g"), -1 when it did
    // not match as a run -- that is what the bold is drawn from.
    function rank(q, tok) {
        let pool = list;
        if (tok) pool = pool.filter(a => inCat(a, tok));
        q = q.trim().toLowerCase();
        const cmp = (a, b) => { a = a.toLowerCase(); b = b.toLowerCase(); return a < b ? -1 : a > b ? 1 : 0; };
        if (!q)
            return pool.slice().sort((a, b) => (use(b) - use(a)) || cmp(a.name, b.name))
                       .map(a => ({ app: a, tier: 0, at: -1, where: "" }));
        const out = [];
        for (const a of pool) {
            const n = a.name.toLowerCase(), g = (a.generic || "").toLowerCase();
            let t, at = -1, where = "n";
            const words = n.replace(/[-_]/g, " ").split(/\s+/);
            if (n === q) { t = 0; at = 0; }
            else if (n.startsWith(q)) { t = 1; at = 0; }
            else if (words.some(w => w.startsWith(q))) {
                t = 1;
                const m = new RegExp("(^|[\\s\\-_])" + q.replace(/[.*+?^${}()|[\]\\]/g, "\\$&")).exec(n);
                at = m ? m.index + m[1].length : -1;
            }
            else if (n.indexOf(q) >= 0) { t = 3; at = n.indexOf(q); }
            else if (g.indexOf(q) >= 0) { t = 4; at = g.indexOf(q); where = "g"; }
            else if ((a.keywords || "").toLowerCase().indexOf(q) >= 0) { t = 4; where = "k"; }
            else if ((a.comment || "").toLowerCase().indexOf(q) >= 0
                     || (a.exec || "").toLowerCase().indexOf(q) >= 0) { t = 5; where = "c"; }
            else {
                let j = 0;
                for (let i = 0; i < n.length && j < q.length; i++) if (n[i] === q[j]) j++;
                if (j < q.length) continue;
                t = 6; where = "";
            }
            out.push({ app: a, tier: t, at: at, where: where });
        }
        out.sort((x, y) => (x.tier - y.tier) || (use(y.app) - use(x.app))
                           || (x.app.name.length - y.app.name.length) || cmp(x.app.name, y.app.name));
        return out;
    }
}
