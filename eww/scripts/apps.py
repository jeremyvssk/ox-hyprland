#!/usr/bin/env python3
"""
THE APP INDEX behind the search panel.

SINCE 2026-09-16 THE PANEL IS QUICKSHELL'S (quickshell/SearchPanel.qml,
Apps.qml). It reads the cache files and calls three commands: `refresh`
(autostart), `panel` (on open) and `launch`. `index`, `open`, `filter`,
`pick`, `used`, `window`, `count` and the row window below served eww's
panel and search.sh, both deleted that day; they are dead, not removed. What follows
is the eww-era description.

This is the half of the launcher that rofi used to do. It exists because
the launcher moved from rofi into eww -- see the long note at the top of
apps.sh -- and everything rofi did for free (read the .desktop files,
find the icons, rank a query) now has to be done here.

Two commands, and they are deliberately split:

  index          parse every .desktop file on the system, resolve every
                 icon to a real path, write ~/.cache/eww/apps.json.
                 Slow-ish (icon lookup is a filesystem walk) and run
                 rarely -- once when the panel opens, if the cache is
                 older than the application directories.

  filter QUERY [OFF]
                 read that cache, rank it, write the whole ranking to
                 $XDG_RUNTIME_DIR/eww-search-rows.jsonl and print ONE
                 WINDOW of it as JSON. Run on EVERY KEYSTROKE, so it may
                 not touch the disk beyond the one cache read and the
                 one write, and must not stat anything.

The arrow keys are NOT in this list, and that is the point: they scroll
by slicing that jsonl in bash. A python start is 28ms and a held arrow
key repeats every 40, so the keys that repeat cannot afford one -- see
the note over `move` in search.sh.

Splitting them is the whole performance story: the expensive work is
proportional to the number of installed apps and happens once, the
per-keystroke work is a scan of a list already in memory.
"""

import json
import os
import re
import shutil
import subprocess
import sys
import time

HOME = os.path.expanduser("~")
CACHE = os.path.join(HOME, ".cache/eww/apps.json")
USAGE = os.path.join(HOME, ".cache/eww/apps-usage.json")
# ── THE ROW CACHE, AND WHY A HELD ARROW KEY NEEDS ONE ───────────────
# Every ranked row, one JSON object per line, rewritten on the same
# process that ranks them. It exists so that `search.sh move` can build
# the next window with `mapfile -s` and not start a python -- an arrow
# key repeat is 40ms on this machine (input:repeat_rate 25) and a
# python start alone is 28. See the note over `move` in search.sh.
#
# In XDG_RUNTIME_DIR, not ~/.cache: it is state for one live panel, it
# must not survive a reboot, and it is rewritten several times a second
# while you type.
ROWS = os.path.join(os.environ.get("XDG_RUNTIME_DIR", "/tmp"),
                    "eww-search-rows.jsonl")
# How many rows are on screen at once. It is a WINDOW, not a cap: the
# rank below is computed over every match and this is only how much of
# it you can see, which is what lets the selection walk off the bottom
# and pull the list up under it.
#
# 10 because the panel is PINNED to a height and the category strip
# takes the eleventh row. `.search-sheet` in eww.scss reserves the lot
# no matter what the query matches, so the panel stops resizing under
# the cursor while you type -- measured before: 7 matches 344px, 6
# matches 306px, 5 matches 268px, and every keystroke that changed the
# count moved the whole sheet. The two numbers must move together.
WINDOW = 10

# ── THE SIX BUCKETS ─────────────────────────────────────────────────
# Six because six is what fits on ONE row of the strip: at 10.5px in
# JetBrains Mono the labels below measure 216px of text, and with the
# chip padding and the gaps that is 342px inside a 416px panel. Adding
# the F-key hints the first sketch had ("F1 System") makes it 450px,
# which is where the strip breaks onto a second row -- so the hints are
# gone and the token the chip writes into the field teaches the
# keyboard path instead.
#
# The token is what you type; the label is what the chip says; the tuple
# is the Categories= values that count as that bucket. Counts on this
# machine: sys 17, util 11, dev 11, net 8, set 7, media 5.
CATS = [
    ("sys",   "System",   ("System",)),
    ("util",  "Utility",  ("Utility",)),
    ("dev",   "Dev",      ("Development",)),
    ("net",   "Network",  ("Network",)),
    ("set",   "Settings", ("Settings",)),
    ("media", "Media",    ("AudioVideo", "Audio", "Video")),
]

# XDG_DATA_DIRS in priority order: a user's own .desktop file shadows a
# system one with the same basename, which is how "I overrode Discord's
# launcher" is supposed to work.
APPDIRS = []
for d in [os.environ.get("XDG_DATA_HOME") or os.path.join(HOME, ".local/share")] + \
         (os.environ.get("XDG_DATA_DIRS") or "/usr/local/share:/usr/share").split(":"):
    p = os.path.join(d, "applications")
    if p not in APPDIRS:
        APPDIRS.append(p)

# Icon themes are searched in this order and the FIRST hit wins. Papirus
# leads because that is what the rofi theme asked for by name
# (`icon-theme: "Papirus-Dark"`) and it is the only theme here with
# near-complete coverage; hicolor is the fallback every theme inherits
# from, and pixmaps is where old apps still drop a loose png.
ICON_THEMES = ["Papirus-Dark", "Papirus", "hicolor"]
ICON_ROOTS = [os.path.join(HOME, ".local/share/icons"),
              os.path.join(HOME, ".icons"),
              "/usr/share/icons"]
ICON_FLAT = ["/usr/share/pixmaps", "/usr/share/icons"]
# Big enough that a 24px widget downscales rather than upscales, and
# scalable first because Papirus is svg throughout. gdk-pixbuf renders
# svg here (verified on this machine -- `gdk-pixbuf-query-loaders` does
# not list it but Pixbuf.new_from_file_at_size loads one fine), so there
# is no rasterising step.
ICON_SIZES = ["scalable", "64x64", "48x48", "128x128", "32x32", "24x24", "symbolic"]
ICON_EXTS = [".svg", ".png", ".xpm"]
# Every row gets an icon, even the entries with a broken or missing
# Icon= key. eww 0.5.0's `image` logs a GdkPixbuf error and leaves a
# blank hole for an unloadable path, and a hole is worse than a generic
# cog -- it makes the list look like it failed rather than like that app
# has no icon. Resolved once at index time, not per row.
FALLBACK_ICON = "/usr/share/icons/Papirus-Dark/64x64/mimetypes/application-x-executable.svg"


# ── .desktop parsing ────────────────────────────────────────────────
# Only the [Desktop Entry] group. A .desktop file can hold any number of
# additional [Desktop Action ...] groups, and those carry their own Name
# and Exec -- reading them as if they were the entry is how a launcher
# ends up listing "New Window" as an application.
def parse(path):
    e, in_entry = {}, False
    try:
        with open(path, encoding="utf-8", errors="replace") as f:
            for line in f:
                line = line.strip()
                if line.startswith("["):
                    in_entry = line == "[Desktop Entry]"
                    continue
                if not in_entry or not line or line.startswith("#"):
                    continue
                k, _, v = line.partition("=")
                if _:
                    e[k.strip()] = v.strip()
    except OSError:
        return None
    return e


def visible(e):
    """The four ways a .desktop file says 'not in the menu'."""
    if not e or e.get("Type", "Application") != "Application":
        return False
    if not e.get("Name") or not (e.get("Exec") or e.get("DBusActivatable") == "true"):
        return False
    if e.get("NoDisplay", "").lower() == "true":
        return False
    if e.get("Hidden", "").lower() == "true":
        return False
    # OnlyShowIn / NotShowIn are how a desktop hides another desktop's
    # control panels. We are Hyprland, and Hyprland is not in anybody's
    # OnlyShowIn list, so a file that names ANY desktop but not ours is
    # not for us. This is what keeps ~40 KDE/GNOME settings panes out.
    only = [s for s in e.get("OnlyShowIn", "").split(";") if s]
    if only and "Hyprland" not in only:
        return False
    if "Hyprland" in [s for s in e.get("NotShowIn", "").split(";") if s]:
        return False
    # TryExec names the binary that has to exist for the entry to be
    # real. Uninstalled-but-left-behind .desktop files are common.
    te = e.get("TryExec", "")
    if te:
        if te.startswith("/"):
            if not os.access(te, os.X_OK):
                return False
        elif not any(os.access(os.path.join(p, te), os.X_OK)
                     for p in os.environ.get("PATH", "").split(":") if p):
            return False
    return True


# ── icon name -> a path gdk-pixbuf can open ─────────────────────────
# Built as ONE index of every candidate directory rather than as a
# per-name search, because a per-name search re-walks the same theme
# directories 233 times. The whole index below costs a couple of
# hundred listdir calls, once.
def icon_index():
    idx = {}

    def offer(name, path):
        # First writer wins, and the callers below are ordered so that
        # "first" means "highest priority theme, largest useful size".
        if name not in idx:
            idx[name] = path

    for theme in ICON_THEMES:
        for root in ICON_ROOTS:
            tdir = os.path.join(root, theme)
            if not os.path.isdir(tdir):
                continue
            # Papirus nests as <theme>/<size>/apps, hicolor as
            # <theme>/<size>/apps too, but sizes are named differently
            # and some themes add a scale suffix (128x128@2). Walk the
            # size dirs we care about in preference order.
            for size in ICON_SIZES:
                for sub in ("apps", "devices", "places", ""):
                    d = os.path.join(tdir, size, sub) if sub else os.path.join(tdir, size)
                    try:
                        entries = os.listdir(d)
                    except OSError:
                        continue
                    for fn in entries:
                        stem, ext = os.path.splitext(fn)
                        if ext in ICON_EXTS:
                            offer(stem, os.path.join(d, fn))

    for d in ICON_FLAT:
        try:
            entries = os.listdir(d)
        except OSError:
            continue
        for fn in entries:
            stem, ext = os.path.splitext(fn)
            if ext in ICON_EXTS:
                offer(stem, os.path.join(d, fn))
    return idx


def resolve_icon(name, idx):
    fb = FALLBACK_ICON if os.path.exists(FALLBACK_ICON) else ""
    if not name:
        return fb
    # An absolute path is already an answer -- but only if it is still
    # there; .desktop files outlive the files they point at.
    if name.startswith("/"):
        return name if os.path.exists(name) else fb
    stem = os.path.splitext(name)[0]
    return idx.get(name) or idx.get(stem) or fb


def wm_candidates(e, fn):
    out = []
    swc = e.get("StartupWMClass", "").strip()
    if swc:
        out.append(swc.lower())
    stem = fn[:-len(".desktop")] if fn.endswith(".desktop") else fn
    out.append(stem.lower())
    if "." in stem:                 # org.kde.dolphin -> dolphin
        out.append(stem.rsplit(".", 1)[-1].lower())
    ex = e.get("Exec", "").split()
    for tok in ex:
        if tok.startswith("-") or "=" in tok or tok.startswith("%"):
            continue
        out.append(os.path.basename(tok).lower())
        break
    seen, uniq = set(), []
    for c in out:
        if c and c not in seen:
            seen.add(c)
            uniq.append(c)
    return uniq


# ── ACTIVATE, DO NOT RELAUNCH ───────────────────────────────────────
# THE BUG THIS FIXES, reproduced rather than guessed: System Settings
# was already open on workspace 3. Typing "system settings" and
# pressing Enter did nothing at all -- no new process, no window moved,
# focus stayed where it was. KDE's systemsettings is single-instance:
# the second launch hands off to the first over D-Bus and exits, and
# the first is on another workspace, so from where you are sitting the
# launcher did nothing. Firefox has the same shape with a different
# ending: you get a fresh empty window instead of the session you had.
#
# So: if the app already has a window, go to it. The one exception is
# the window you are ALREADY on -- launching the app you are looking at
# can only mean "another one of these", which is how you get a second
# terminal.
#
# ── AND THEN THAT RULE ATE THE LAUNCHER ─────────────────────────────
# "It does not launch apps properly" again, reproduced with a virtual
# keyboard: focused on KCalc, Super+S, `kitty`, Return -- no new
# process, no new window, focus jumped to a terminal already open on
# workspace 3. Correct by the rule above and useless as a launcher.
# The rule was derived from ONE app that really is single-instance and
# then applied to all 62, so every app you already had open stopped
# being launchable: ask for a terminal and you get the terminal you
# were already ignoring, ask for a browser window and you get the one
# playing something else.
#
# The hand-off is not a property of "having a window open", it is a
# property of THE APP: does a second launch make a second window, or is
# it handed to the first process and dropped? The .desktop file answers
# that. `DBusActivatable=true` means the launch is an Activate call on
# an existing name, which is exactly the hand-off; KDE also marks
# `SingleMainWindow=true` on the ones that refuse a second window.
# On this machine that is 6 entries of 62 -- Discover, KDE Connect SMS,
# KDE System Settings, KWalletManager, Spectacle, System Monitor --
# which includes systemsettings, the app the whole rule was written for.
# The other 56, kitty and Brave and Discord and Code among them, launch.
#
# The hist-0 exception below stays: it is now the difference between
# "another one of these" and "the one I am looking at" for the six.
def find_window(desktop_file):
    """(address, focus_history_id) of the best window for this app.

    None for anything a second launch would open a second window of --
    for those the answer is always "launch it".
    """
    cands = None
    for a in load():
        if a.get("file") == desktop_file:
            if not a.get("single"):
                return None
            cands = a.get("wmclass") or []
            break
    if cands is None:
        e = parse(desktop_file)
        if not e:
            return None
        if not (e.get("DBusActivatable", "").strip().lower() == "true"
                or e.get("SingleMainWindow", "").strip().lower() == "true"):
            return None
        cands = wm_candidates(e, os.path.basename(desktop_file))
    if not cands:
        return None
    try:
        out = subprocess.run(["hyprctl", "clients", "-j"], timeout=3,
                             capture_output=True, text=True).stdout
        clients = json.loads(out)
    except Exception:
        return None

    best = None
    for c in clients:
        names = {str(c.get("class", "")).lower(),
                 str(c.get("initialClass", "")).lower()}
        names.discard("")
        if not names:
            continue
        hit = any(n == cand for n in names for cand in cands)
        if not hit:
            # dolphin vs org.kde.dolphin, brave vs brave-browser: a
            # containment test in both directions catches the usual
            # mismatches without matching "code" against "vscodium".
            hit = any((n in cand or cand in n) and min(len(n), len(cand)) >= 4
                      for n in names for cand in cands)
        if not hit:
            continue
        # focusHistoryID 0 is the focused window, 1 the one before it.
        h = c.get("focusHistoryID", 999)
        if best is None or h < best[1]:
            best = (c.get("address", ""), h)
    return best


def build_index():
    idx = icon_index()
    seen, apps = set(), []
    for d in APPDIRS:
        try:
            names = os.listdir(d)
        except OSError:
            continue
        for fn in sorted(names):
            if not fn.endswith(".desktop"):
                continue
            if fn in seen:          # a user override already claimed it
                continue
            seen.add(fn)
            path = os.path.join(d, fn)
            e = parse(path)
            if not visible(e):
                continue
            apps.append({
                "name": e["Name"],
                "generic": e.get("GenericName", ""),
                "comment": e.get("Comment", ""),
                "exec": e.get("Exec", ""),
                "keywords": e.get("Keywords", "").replace(";", " "),
                # Raw, not bucketed. The buckets are a display choice
                # and change without a reindex; what the file actually
                # claimed does not.
                "cats": [c for c in e.get("Categories", "").split(";") if c],
                "icon": resolve_icon(e.get("Icon", ""), idx),
                "file": path,
                "id": fn,
                # What this app's window will call itself, for
                # activate-instead-of-relaunch. StartupWMClass is the
                # only authoritative answer and about half of all
                # entries carry it; the other two are the guesses every
                # launcher makes -- the desktop id without its suffix
                # (org.kde.dolphin -> dolphin) and the Exec binary.
                "wmclass": wm_candidates(e, fn),
                # Whether a SECOND launch of this app produces a second
                # window or is handed to the first one. See find_window.
                "single": (e.get("DBusActivatable", "").strip().lower() == "true"
                           or e.get("SingleMainWindow", "").strip().lower() == "true"),
            })
    apps.sort(key=lambda a: a["name"].lower())
    os.makedirs(os.path.dirname(CACHE), exist_ok=True)
    tmp = CACHE + ".tmp"
    with open(tmp, "w", encoding="utf-8") as f:
        json.dump(apps, f)
    os.replace(tmp, CACHE)          # atomic: a filter never sees a half file
    return apps


# ── USAGE, AND WHY IT IS NOT OPTIONAL ───────────────────────────────
# `rofi -show drun` sorts by launch history by default. Dropping that
# would have made this launcher measurably worse than the one it
# replaces on the only query that matters -- the short prefix you
# actually type. With 'co' typed and no history, tier 2 is ordered by
# name length, so "KDE Connect" (11 chars) sits above "Visual Studio
# Code" (18) forever, no matter that you have opened Code every day and
# KDE Connect never.
#
# The store is keyed by DESKTOP ID -- the .desktop basename -- and not
# by full path. The path is not a stable identity: `code.desktop` exists
# both in /usr/share/applications and in ~/.local/share/applications on
# this machine, the user copy shadows the system one, and keying by path
# meant that dropping in (or removing) an override silently reset that
# app's history to zero. The basename is what XDG calls the entry's ID
# and it is what survives the override.
#
# The store is a flat {desktop-id: score}. On each launch the
# winner gains 1 and EVERY score decays by 0.92, which is what makes it
# frecency rather than a lifetime counter: an app you used constantly
# two months ago falls behind one you have used twice this week, and
# nothing needs a timestamp or a cron job to expire.
DECAY = 0.92


def usage_load():
    try:
        with open(USAGE, encoding="utf-8") as f:
            return json.load(f)
    except Exception:
        return {}


def usage_bump(desktop_id):
    desktop_id = os.path.basename(desktop_id)
    u = usage_load()
    u = {k: v * DECAY for k, v in u.items() if v * DECAY > 0.05}
    u[desktop_id] = u.get(desktop_id, 0.0) + 1.0
    os.makedirs(os.path.dirname(USAGE), exist_ok=True)
    tmp = USAGE + ".tmp"
    with open(tmp, "w", encoding="utf-8") as f:
        json.dump(u, f)
    os.replace(tmp, USAGE)


def load():
    try:
        with open(CACHE, encoding="utf-8") as f:
            apps = json.load(f)
    except Exception:
        return build_index()
    # stale() watches the application DIRECTORIES, so it cannot notice
    # that this file's own shape changed. A cache written before a field
    # was added has to be rebuilt on the spot or every consumer reads a
    # missing key as a default and the new behaviour never arrives.
    if apps and "cats" not in apps[0]:
        return build_index()
    return apps


def stale():
    """Rebuild only when an application directory has actually changed.

    mtime on the DIRECTORY, not on the files: installing or removing a
    package writes the directory, and that is the only event that can
    add or drop an entry. Editing a .desktop in place is rare enough to
    live with one panel-open of lag.
    """
    try:
        c = os.path.getmtime(CACHE)
    except OSError:
        return True
    for d in APPDIRS:
        try:
            if os.path.getmtime(d) > c:
                return True
        except OSError:
            pass
    return False


# ── ranking ─────────────────────────────────────────────────────────
# Tiered, not fuzzy-scored. A launcher is judged on one thing: does the
# app you were thinking of sit on row 1 by the third keystroke. Tiers
# make that predictable -- "code" puts Code above Codium above anything
# merely mentioning code in its description -- where a single blended
# score lets a long name with a lucky subsequence jump the queue.
TOKEN = re.compile(r":([A-Za-z]*)")


def split_token(q):
    """Take a `:tok` out of the query, anywhere in it, and say which
    bucket it means.

    Returns (token or "", the rest of the query). Prefix matching, so
    the list narrows while the token is still half typed -- but only
    when the prefix is unambiguous: `:s` could be sys or set, and until
    you commit to one it filters nothing.

    An unresolved token is DROPPED rather than searched for. Typing `:`
    and then a letter would otherwise empty the panel between the colon
    and the third character, which reads as the launcher breaking; this
    way the list is merely unfiltered until the token means something.

    ── AND "ANYWHERE" IS NOT GENEROSITY, IT IS GTK ──────────────────
    The chip and ALT+<n> write the token by setting the entry's text,
    and gtk_entry_set_text leaves the cursor at position 0 -- eww 0.5.0
    exposes no way to move it. So the next thing you type goes IN FRONT
    of the token: press ALT+6, type `kit`, and the field reads
    `kit:media`. Measured, twice, with a uinput keyboard.
    Reading the token wherever it sits makes that the same search as
    `:media kit`, which is what the user meant both times.
    """
    tok = ""

    def take(m):
        nonlocal tok
        head = m.group(1).lower()
        if not tok and head:
            hits = [t for t, _l, _c in CATS if t.startswith(head)]
            if len(hits) == 1:
                tok = hits[0]
        # A token word is never part of the text that gets ranked,
        # resolved or not -- see the paragraph above.
        return " "

    # Two statements, and it has to be: `return tok, TOKEN.sub(...)`
    # reads tok BEFORE the substitution that assigns it, and silently
    # returns the empty token every time.
    rest = TOKEN.sub(take, q).strip()
    return tok, rest


def in_cat(app, tok):
    want = next(c for t, _l, c in CATS if t == tok)
    return any(c in want for c in app.get("cats", ()))


def rank(apps, q):
    # The token FILTERS, the rest RANKS. They are different operations
    # on purpose: `:dev` with nothing after it is the whole category in
    # history order, and every keystroke after it ranks inside that
    # category rather than reopening the other 51 apps.
    tok, q = split_token(q.strip())
    if tok:
        apps = [a for a in apps if in_cat(a, tok)]
    q = q.strip().lower()
    u = usage_load()
    if not q:
        # The empty query is the panel's opening frame, so it is the one
        # place history is the WHOLE ordering: with nothing typed there
        # is no other signal, and "the things I actually launch" is a
        # better first screen than the first seven apps alphabetically.
        return sorted(apps, key=lambda a: (-u.get(a["id"], 0.0),
                                           a["name"].lower()))
    out = []
    for a in apps:
        n = a["name"].lower()
        if n == q:
            t = 0
        # ONE prefix tier, not two. A prefix of the whole name and a
        # prefix of a WORD in the name were tiers 1 and 2, and that
        # ranking is wrong for a launcher: with "c" typed it put CMake
        # -- never opened -- above "Visual Studio Code", permanently,
        # because "Visual" is what the name starts with. Neither match
        # is really better evidence than the other; which app you meant
        # is decided by which one you actually launch, and that is what
        # history is for. Merged, they are ordered by history below.
        elif n.startswith(q) or any(
                w.startswith(q) for w in n.replace("-", " ").replace("_", " ").split()):
            t = 1
        elif q in n:
            t = 3
        elif q in a["generic"].lower() or q in a["keywords"].lower():
            t = 4
        elif q in a["comment"].lower() or q in a["exec"].lower():
            t = 5
        else:
            # Last resort: the letters in order, anywhere. This is what
            # makes "gimp" find "GNU Image Manipulation Program", and it
            # is tier 6 so it can never outrank a real substring match.
            it = iter(n)
            if not all(ch in it for ch in q):
                continue
            t = 6
        # Inside a tier: what you launch most, then the shorter name.
        # History first is what puts Code above KDE Connect on "co";
        # length is the tiebreak for everything you have never opened,
        # where "Code" is still a better guess than "Color Picker
        # Companion". Tiers are never crossed -- history can reorder
        # equally-good matches, it can never promote a weak one.
        out.append((t, -u.get(a["id"], 0.0), len(a["name"]), a["name"].lower(), a))
    out.sort(key=lambda r: r[:4])
    return [r[4] for r in out]


# ── the sliding window ──────────────────────────────────────────────
# rank() returns EVERY match; this is the part of it that is on screen.
# Ranking the lot costs nothing (it is a scan of ~60 dicts already in
# memory) and rendering the lot is what would be expensive -- eww builds
# a real widget per row -- so the cut happens here, at the last moment,
# and the rank stays whole underneath it.
def publish(rows, off):
    """Write the whole ranking to ROWS and return the slice of it that
    is on screen. Both halves of the sliding window happen here so they
    cannot disagree: what search.sh scrolls through later is the file
    this wrote, in this order, with these indices."""
    # `i` is the row's index into the WHOLE ranked list, not into the
    # slice. search-sel is absolute, the highlight compares against it
    # and `pick` resolves it, so a row that scrolls out of view and back
    # is the same row both times. It is stamped on every row, not just
    # the visible ten, because the file is what the scroll reads.
    for k, r in enumerate(rows):
        r["i"] = k
    # Written and renamed, not written in place: `move` reads this file
    # with no lock of its own, and a half-written line would be a row
    # that is not JSON. os.replace is atomic on the same filesystem.
    tmp = ROWS + ".new"
    try:
        with open(tmp, "w") as f:
            for r in rows:
                f.write(json.dumps(r) + "\n")
        os.replace(tmp, ROWS)
    except OSError:
        # An arrow key that scrolls nothing is worse than one that
        # scrolls a stale list -- same rule as every lock here.
        pass
    off = max(0, min(off, max(0, len(rows) - WINDOW)))
    return rows[off:off + WINDOW]


def main():
    cmd = sys.argv[1] if len(sys.argv) > 1 else "filter"
    if cmd == "index":
        print(len(build_index()))
        return
    if cmd == "open":
        # What the panel calls on open, and it is ONE process on purpose.
        # This was a `refresh` followed by a `filter`, i.e. two python
        # starts and two cache reads (34 ms + 32 ms measured) for work
        # that shares everything. Rebuilding only when an application
        # directory has actually changed means the common case never
        # touches the disk beyond a single cache read.
        rows = build_index() if stale() else load()
        ranked = rank(rows, "")
        # TWO lines out, and the second one is the length of the whole
        # ranking -- not of the ten that are on screen. search.sh seeds
        # its nav file with it so a held arrow key knows where the list
        # ends without asking anything.
        print(json.dumps(publish(ranked, 0)))
        print(len(ranked))
        return
    if cmd == "refresh":
        # Rebuild-if-stale on its own, for callers that do not want the
        # list back. Deliberately does NOT load the cache when it is
        # fresh -- parsing the whole index to print a number it throws
        # away was pure cost.
        if stale():
            build_index()
        return
    if cmd == "filter":
        # The row's own index is stamped into the row. eww 0.5.0's
        # `(for x in list)` exposes no loop counter, so the only way a
        # row can know whether IT is the selected one -- and therefore
        # whether to paint itself -- is to carry its position with it.
        # THREE lines out: the category the query resolved to (empty for
        # an ordinary search), then the rows, then how many rows the
        # ranking has in total. The first line is what lights the chip
        # on the strip, and it comes back from the same process that did
        # the ranking because asking a second time would be a second
        # python start on every keystroke. The third is the same economy
        # for the arrow keys -- see publish().
        q = sys.argv[2] if len(sys.argv) > 2 else ""
        off = int(sys.argv[3]) if len(sys.argv) > 3 else 0
        ranked = rank(load(), q)
        print(split_token(q.strip())[0])
        print(json.dumps(publish(ranked, off)))
        print(len(ranked))
        return
    if cmd == "pick":
        # The selected row's .desktop path, for the launcher. Resolving
        # it here rather than carrying it through an eww var keeps the
        # index the single source of truth about what row N is.
        q = sys.argv[2] if len(sys.argv) > 2 else ""
        i = int(sys.argv[3]) if len(sys.argv) > 3 else 0
        rows = rank(load(), q)
        print(rows[i]["file"] if 0 <= i < len(rows) else "")
        return
    if cmd == "panel":
        # What quickshell/Apps.qml runs when the Search panel opens, ONE
        # process. It rebuilds the cache if an application directory
        # changed (the panel watches apps.json and re-reads it), then
        # prints {file: workspace} for every app whose Enter would go to
        # its window instead of launching -- the six `single` apps, when
        # find_window names a window that is not the focused one. That is
        # what lets the cursor row say "Go to workspace 3" BEFORE you
        # press; `launch` asks find_window again at the press.
        apps = build_index() if stale() else load()
        out = {}
        try:
            clients = json.loads(subprocess.run(["hyprctl", "clients", "-j"], timeout=3,
                                                capture_output=True, text=True).stdout)
        except Exception:
            clients = []
        ws = {c.get("address"): (c.get("workspace") or {}).get("name", "") for c in clients}
        for a in apps:
            if not a.get("single"):
                continue
            w = find_window(a["file"])
            if w and w[0] and w[1] != 0 and ws.get(w[0]):
                out[a["file"]] = ws[w[0]]
        print(json.dumps(out))
        return
    if cmd == "launch":
        # Enter or a click in the Search panel. search.sh's launch path,
        # moved here when eww's panel went: record it, go to the window
        # if find_window says this app hands off to one, else gio launch.
        # Quickshell starts this detached, so nothing waits on it.
        f = sys.argv[2] if len(sys.argv) > 2 else ""
        if not f:
            return
        usage_bump(f)
        w = find_window(f)
        if w and w[0] and w[1] != 0:
            subprocess.run(["hyprctl", "dispatch",
                            'hl.dsp.focus({ window = "address:%s" })' % w[0]],
                           capture_output=True, timeout=3)
            return
        # THE ENVIRONMENT IS NOT COSMETIC. Every app started from here
        # inherits it, and the shell that runs this was started from hypr
        # autostart with whatever env that had. XDG_CURRENT_DESKTOP=KDE
        # made launched apps ask for the KDE portal and file dialog while
        # the same app from a terminal behaved like a Hyprland app. Copied
        # from search.sh, which copied it from rofi-launcher.sh.
        #
        # EXCEPT XDG_DATA_DIRS, which that block also set, to
        # ~/.local/share/applications:/usr/share/applications:… -- the
        # applications folders, where the spec wants their PARENTS. Every
        # app started with it looked for icons, mime types and GSettings
        # schemas under /usr/share/applications/… and found none:
        # nm-connection-editor (Advanced Network Configuration) aborted on
        # its first icon, core dumped, every launch (2026-09-16). The
        # session's own value is inherited instead -- which is also where
        # flatpak's exports are, on a machine that has them.
        env = dict(os.environ,
                   XDG_CURRENT_DESKTOP="Hyprland", XDG_SESSION_TYPE="wayland",
                   XDG_SESSION_DESKTOP="Hyprland",
                   QT_QPA_PLATFORMTHEME="qt6ct", QT_QPA_PLATFORM="wayland")
        # Terminal=true apps: gio's own terminal list has no kitty, foot,
        # alacritty or wezterm, so without this nvtop opens in Konsole or,
        # on a kitty-only machine, nowhere. See term/xdg-terminal-exec.
        if not shutil.which("xdg-terminal-exec"):
            env["PATH"] = os.path.join(os.path.dirname(os.path.abspath(__file__)), "term") \
                          + ":" + env.get("PATH", "")
        # `gio launch`, not a hand-parsed Exec line: field codes,
        # Terminal=true and DBusActivatable are all its job. Own session,
        # so the app does not die with the shell that started it.
        subprocess.Popen(["gio", "launch", f], env=env, start_new_session=True,
                         stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL,
                         stderr=subprocess.DEVNULL)
        return
    if cmd == "used":
        # Record a launch. Takes the .desktop path (reduced to its id
        # inside), not a row index, so it cannot be desynchronised from
        # what was actually started.
        if len(sys.argv) > 2 and sys.argv[2]:
            usage_bump(sys.argv[2])
        return
    if cmd == "window":
        # "<address> <focusHistoryID>", or nothing. search.sh decides
        # what to do with it -- see the note above find_window.
        if len(sys.argv) > 2 and sys.argv[2]:
            w = find_window(sys.argv[2])
            if w and w[0]:
                print("%s %s" % (w[0], w[1]))
        return
    if cmd == "count":
        q = sys.argv[2] if len(sys.argv) > 2 else ""
        print(len(rank(load(), q)))
        return


if __name__ == "__main__":
    main()
