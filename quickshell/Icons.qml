pragma Singleton

// ═══════════════════════════════════════════════════════════════
// ICONS — the bar's own drawings, as geometry.
//
// NOT A FONT, AND THAT IS THE WHOLE POINT. An icon in a font is a
// letter, and a letter needs a typeface that may not be there: 29 of
// the 55 glyphs on the live waybar need Nerd Fonts v3+, and on a v2
// machine they are tofu. That is the single biggest portability risk
// in this repo, and it is deleted here rather than managed. A path
// needs nothing.
//
// It is also not Material Symbols. That was the fallback if our own
// drawings did not hold up at 15 px -- they do, they are one set at
// one stroke weight drawn against one 16 px grid, and they are ours
// to licence, which matters on day 5 when this repo gets a LICENSE.
// Material Symbols Rounded 300 stays the reference to redraw a weak
// glyph against, because that is the grid this style comes from.
//
// ── HOW TO READ AN ENTRY ─────────────────────────────────────
//   vb      the box the drawing was made in. Everything is 16 x 16
//           except the Hyprland mark, which is 241 x 313 at y 330 --
//           its own artwork, kept at its own scale rather than
//           re-fitted, so the curves are the real ones.
//   sw      stroke width IN THAT BOX. Icon.qml scales the box, and
//           the stroke scales with it, exactly as an SVG would.
//   stroke  every stroked subpath, concatenated. One string, many
//           M...Z runs -- they stay separate subpaths, so caps still
//           happen per run.
//   fill    the filled subpaths: the wifi dot, the battery's charge,
//           the three tray squares, the Hyprland mark.
//   dim     stroked at 35% -- the three off-states use it, for what
//           is behind the slash: wifi's two arcs, vol's two waves,
//           and the whole of bt's rune.
//
// ROUND CAPS AND ROUND JOINS, EVERYWHERE, one rule instead of
// twenty. Checked rather than assumed: every subpath in the set that
// was drawn with butt caps or mitre joins is a CLOSED shape -- a
// rect, a circle, or a closed polygon -- where neither applies.
// ═══════════════════════════════════════════════════════════════

import Quickshell

Singleton {
    readonly property var set: ({
        "search": { "vb": [0, 0, 16, 16], "sw": 1.4,
            "stroke": "M 2.8 7.2 A 4.4 4.4 0 1 0 11.6 7.2 A 4.4 4.4 0 1 0 2.8 7.2 Z M10.5 10.5 13.6 13.6",
            "fill": "",
            "dim": "" },
        "hypr": { "vb": [0, 330, 241.24, 312.89], "sw": 1.4,
            "stroke": "",
            "fill": "M107 330c-25.9 39.39-61.43 86.28-79.3 114.97C9.83 473.67-1.86 502.32.24 536.26c3.85 62.1 56.46 106.63 120.38 106.63v-27.4c-51.66 0-90.07-33.06-93.03-80.93-1.67-26.96 6.9-48.66 23.37-75.1 14.07-22.6 33.9-47.95 56.03-80.2zm27.25 0c25.89 39.39 61.42 86.28 79.29 114.97 17.87 28.7 29.56 57.35 27.46 91.29-3.85 62.1-56.46 106.63-120.38 106.63v-27.4c51.66 0 90.07-33.06 93.03-80.93 1.67-26.96-6.9-48.66-23.37-75.1-14.07-22.6-33.9-47.95-56.03-80.2z",
            "dim": "" },
        "wifi": { "vb": [0, 0, 16, 16], "sw": 1.4,
            "stroke": "M1.6 5.6a11 11 0 0 1 12.8 0 M4 8.4a7.2 7.2 0 0 1 8 0 M6.4 11.1a3.5 3.5 0 0 1 3.2 0",
            "fill": "M 7.25 13.4 A 0.75 0.75 0 1 0 8.75 13.4 A 0.75 0.75 0 1 0 7.25 13.4 Z",
            "dim": "" },
        "wifi-off": { "vb": [0, 0, 16, 16], "sw": 1.4,
            "stroke": "M2 2l12 12",
            "fill": "",
            "dim": "M1.6 5.6a11 11 0 0 1 12.8 0 M4 8.4a7.2 7.2 0 0 1 8 0" },
        "bt": { "vb": [0, 0, 16, 16], "sw": 1.4,
            "stroke": "M4.8 4.6 11.2 11 8 14V2l3.2 3-6.4 6.4",
            "fill": "",
            "dim": "" },
        // THE ONE SLASH IN THE SET THAT LEANS THE OTHER WAY, and it is
        // geometry, not taste. The bluetooth rune IS an X of both 45
        // degree diagonals -- its upper arm lies on y = x - 0.2 and its
        // lower on y = 16.2 - x -- so the set's own slash (M2 2 l12 12,
        // as wifi-off and vol-off draw it) does not cross this rune, it
        // lands ALONG an arm, 0.14 px off parallel at a 1.4 stroke.
        // Both directions cover an arm; rendered at 15 px and looked
        // at, only this one still reads as a rune crossed out -- the
        // other reads as a rune that got thicker on one side. The
        // steeper angles that cross cleanly on paper tangle with the
        // vertical spine at 15 px, which is where it actually has to
        // work.
        "bt-off": { "vb": [0, 0, 16, 16], "sw": 1.4,
            "stroke": "M2 14 14 2",
            "fill": "",
            "dim": "M4.8 4.6 11.2 11 8 14V2l3.2 3-6.4 6.4" },
        // Connected is the rune plus the two ticks mdi's
        // bluetooth-connect (U+F00B1) puts either side of it -- the
        // rune the bar has drawn for this state all along, redrawn on
        // our own grid. They sit outside the rune's own span (x 4.8 to
        // 11.2) so nothing overlaps, and at 15 px they are the one
        // addition tested that still reads: a badge dot is noise at
        // that size and an arc reads as the volume glyph.
        "bt-conn": { "vb": [0, 0, 16, 16], "sw": 1.4,
            "stroke": "M4.8 4.6 11.2 11 8 14V2l3.2 3-6.4 6.4 M1.9 8h1.9 M12.2 8h1.9",
            "fill": "",
            "dim": "" },
        "vol": { "vb": [0, 0, 16, 16], "sw": 1.4,
            "stroke": "M2.5 6h2.3L8 3.2v9.6L4.8 10H2.5z M10.6 6.1a3 3 0 0 1 0 3.8 M12.6 4.3a5.6 5.6 0 0 1 0 7.4",
            "fill": "",
            "dim": "" },
        // THE SAME "OFF" AS wifi-off, and deliberately the same rule
        // rather than a second idea: the thing that has stopped is
        // stroked at 35% and the slash is drawn over it at full ink.
        // The speaker itself stays ink -- there is still an output
        // device, it is just not going to make a sound.
        "vol-off": { "vb": [0, 0, 16, 16], "sw": 1.4,
            "stroke": "M2.5 6h2.3L8 3.2v9.6L4.8 10H2.5z M2 2l12 12",
            "fill": "",
            "dim": "M10.6 6.1a3 3 0 0 1 0 3.8 M12.6 4.3a5.6 5.6 0 0 1 0 7.4" },
        "mic": { "vb": [0, 0, 16, 16], "sw": 1.4,
            "stroke": "M 8 1.9 H 8 A 2 2 0 0 1 10 3.9 V 6.9 A 2 2 0 0 1 8 8.9 H 8 A 2 2 0 0 1 6 6.9 V 3.9 A 2 2 0 0 1 8 1.9 Z M3.8 7.6a4.2 4.2 0 0 0 8.4 0 M8 11.8v2.3",
            "fill": "",
            "dim": "" },
        "bat": { "vb": [0, 0, 16, 16], "sw": 1.2,
            "stroke": "M 3 5 H 10.8 A 1.4 1.4 0 0 1 12.2 6.4 V 9.6 A 1.4 1.4 0 0 1 10.8 11 H 3 A 1.4 1.4 0 0 1 1.6 9.6 V 6.4 A 1.4 1.4 0 0 1 3 5 Z M13.6 7.2v1.6",
            "fill": "M 3.6 6.4 H 9.4 A 0.6 0.6 0 0 1 10 7 V 9 A 0.6 0.6 0 0 1 9.4 9.6 H 3.6 A 0.6 0.6 0 0 1 3 9 V 7 A 0.6 0.6 0 0 1 3.6 6.4 Z",
            "dim": "" },
        "cpu": { "vb": [0, 0, 16, 16], "sw": 1.2,
            "stroke": "M 5.8 4.6 H 10.2 A 1.2 1.2 0 0 1 11.4 5.8 V 10.2 A 1.2 1.2 0 0 1 10.2 11.4 H 5.8 A 1.2 1.2 0 0 1 4.6 10.2 V 5.8 A 1.2 1.2 0 0 1 5.8 4.6 Z M6.4 2.2v2.4M9.6 2.2v2.4M6.4 11.4v2.4M9.6 11.4v2.4M2.2 6.4h2.4M2.2 9.6h2.4M11.4 6.4h2.4M11.4 9.6h2.4",
            "fill": "",
            "dim": "" },
        "ram": { "vb": [0, 0, 16, 16], "sw": 1.2,
            "stroke": "M 2.8 4.6 H 13.2 A 1 1 0 0 1 14.2 5.6 V 9.6 A 1 1 0 0 1 13.2 10.6 H 2.8 A 1 1 0 0 1 1.8 9.6 V 5.6 A 1 1 0 0 1 2.8 4.6 Z M4.6 10.6v2.2M8 10.6v2.2M11.4 10.6v2.2",
            "fill": "",
            "dim": "" },
        "sun": { "vb": [0, 0, 16, 16], "sw": 1.3,
            "stroke": "M 5 8 A 3 3 0 1 0 11 8 A 3 3 0 1 0 5 8 Z M8 1.6v1.6M8 12.8v1.6M1.6 8h1.6M12.8 8h1.6M3.5 3.5l1.1 1.1M11.4 11.4l1.1 1.1M12.5 3.5l-1.1 1.1M4.6 11.4l-1.1 1.1",
            "fill": "",
            "dim": "" },
        "moon": { "vb": [0, 0, 16, 16], "sw": 1.3,
            "stroke": "M13 9.6A5.6 5.6 0 0 1 6.4 3a5.7 5.7 0 1 0 6.6 6.6z",
            "fill": "",
            "dim": "" },
        "gear": { "vb": [0, 0, 16, 16], "sw": 1.3,
            "stroke": "M 5.5 8 A 2.5 2.5 0 1 0 10.5 8 A 2.5 2.5 0 1 0 5.5 8 Z M8 1.6l1.1 1.75 2.05-.36.36 2.05L13.3 6.2 12.5 8l.8 1.8-1.79 1.16-.36 2.05-2.05-.36L8 14.4l-1.1-1.75-2.05.36-.36-2.05L2.7 9.8 3.5 8l-.8-1.8 1.79-1.16.36-2.05 2.05.36z",
            "fill": "",
            "dim": "" },
        "power": { "vb": [0, 0, 16, 16], "sw": 1.4,
            "stroke": "M8 2.2v5.4 M4.6 4.4a4.9 4.9 0 1 0 6.8 0",
            "fill": "",
            "dim": "" },
        "lock": { "vb": [0, 0, 16, 16], "sw": 1.3,
            "stroke": "M5.2 7V5.2a2.8 2.8 0 0 1 5.6 0V7 M 5 7 H 11 A 1.6 1.6 0 0 1 12.6 8.6 V 11.4 A 1.6 1.6 0 0 1 11 13 H 5 A 1.6 1.6 0 0 1 3.4 11.4 V 8.6 A 1.6 1.6 0 0 1 5 7 Z",
            "fill": "",
            "dim": "" },
        // THE PANEL'S PADLOCK IS FILLED, and the rule is the user's:
        // small glyphs must be filled. An outlined padlock at 13 px is a
        // rectangle with a hoop on it; this is the same drawing with the
        // body as ink and only the shackle stroked. The outlined `lock`
        // above stays for anything drawn at bar size.
        "lock-fill": { "vb": [0, 0, 16, 16], "sw": 1.4,
            "stroke": "M5.2 7V5.2a2.8 2.8 0 0 1 5.6 0V7",
            "fill": "M 5 6.6 H 11 A 1.8 1.8 0 0 1 12.8 8.4 V 11.6 A 1.8 1.8 0 0 1 11 13.4 H 5 A 1.8 1.8 0 0 1 3.2 11.6 V 8.4 A 1.8 1.8 0 0 1 5 6.6 Z",
            "dim": "" },
        // ── THE SOUND PANEL'S GLYPHS ─────────────────────────
        // Filled, because they are drawn at 14-15 px and small glyphs
        // must be filled (the padlock's rule). Redrawn on our grid from
        // the Material Symbols the Datum Panels mock-up used: speaker,
        // tv, headphones, mic, volume_up, language, play_arrow, stop.
        // Holes are subpaths wound the other way (sweep 0), because the
        // fill is WindingFill. A muted glyph is the same drawing at 35%
        // with `slash` over it at full ink -- vol-off's own rule, drawn
        // in two layers because a slash over a solid shape of the same
        // ink disappears into it. → SoundPanel.qml, Glyph
        "speaker-fill": { "vb": [0, 0, 16, 16], "sw": 1.4,
            "stroke": "",
            "fill": "M4.6 1.4H11.4A1.6 1.6 0 0 1 13 3V13A1.6 1.6 0 0 1 11.4 14.6H4.6A1.6 1.6 0 0 1 3 13V3A1.6 1.6 0 0 1 4.6 1.4Z M5.3 9.8A2.7 2.7 0 0 0 10.7 9.8A2.7 2.7 0 0 0 5.3 9.8Z M7.05 4.6A0.95 0.95 0 0 0 8.95 4.6A0.95 0.95 0 0 0 7.05 4.6Z M7 9.8A1 1 0 0 1 9 9.8A1 1 0 0 1 7 9.8Z",
            "dim": "" },
        "tv-fill": { "vb": [0, 0, 16, 16], "sw": 1.4,
            "stroke": "M5.2 14h5.6",
            "fill": "M3 2.6H13A1.6 1.6 0 0 1 14.6 4.2V10A1.6 1.6 0 0 1 13 11.6H3A1.6 1.6 0 0 1 1.4 10V4.2A1.6 1.6 0 0 1 3 2.6Z",
            "dim": "" },
        "headphones-fill": { "vb": [0, 0, 16, 16], "sw": 1.5,
            "stroke": "M3.1 10V8.2a4.9 4.9 0 0 1 9.8 0V10",
            "fill": "M3 8.8H4.2A1.2 1.2 0 0 1 5.4 10V13A1.2 1.2 0 0 1 4.2 14.2H3A1.2 1.2 0 0 1 1.8 13V10A1.2 1.2 0 0 1 3 8.8Z M11.8 8.8H13A1.2 1.2 0 0 1 14.2 10V13A1.2 1.2 0 0 1 13 14.2H11.8A1.2 1.2 0 0 1 10.6 13V10A1.2 1.2 0 0 1 11.8 8.8Z",
            "dim": "" },
        "mic-fill": { "vb": [0, 0, 16, 16], "sw": 1.4,
            "stroke": "M3.6 7.4a4.4 4.4 0 0 0 8.8 0 M8 11.8v2.6",
            "fill": "M8 1.4A2.6 2.6 0 0 1 10.6 4V6.8A2.6 2.6 0 0 1 5.4 6.8V4A2.6 2.6 0 0 1 8 1.4Z",
            "dim": "" },
        "vol-fill": { "vb": [0, 0, 16, 16], "sw": 1.4,
            "stroke": "M2.5 6h2.3L8 3.2v9.6L4.8 10H2.5z M10.6 6.1a3 3 0 0 1 0 3.8 M12.6 4.3a5.6 5.6 0 0 1 0 7.4",
            "fill": "M2.5 6h2.3L8 3.2v9.6L4.8 10H2.5z",
            "dim": "" },
        "globe": { "vb": [0, 0, 16, 16], "sw": 1.3,
            "stroke": "M 1.9 8 A 6.1 6.1 0 1 0 14.1 8 A 6.1 6.1 0 1 0 1.9 8 Z M 5.4 8 A 2.6 6.1 0 1 0 10.6 8 A 2.6 6.1 0 1 0 5.4 8 Z M1.9 8h12.2",
            "fill": "",
            "dim": "" },
        "note-fill": { "vb": [0, 0, 16, 16], "sw": 1.4,
            "stroke": "M6 12.4V3.2l7-1.4v9.2",
            "fill": "M 2.4 12.6 A 1.9 1.9 0 1 0 6.2 12.6 A 1.9 1.9 0 1 0 2.4 12.6 Z M 9.4 11 A 1.9 1.9 0 1 0 13.2 11 A 1.9 1.9 0 1 0 9.4 11 Z",
            "dim": "" },
        "play-fill": { "vb": [0, 0, 16, 16], "sw": 1.4,
            "stroke": "M5 3.4 12.4 8 5 12.6Z",
            "fill": "M5 3.4 12.4 8 5 12.6Z",
            "dim": "" },
        "stop-fill": { "vb": [0, 0, 16, 16], "sw": 1.4,
            "stroke": "",
            "fill": "M5 4H11A1 1 0 0 1 12 5V11A1 1 0 0 1 11 12H5A1 1 0 0 1 4 11V5A1 1 0 0 1 5 4Z",
            "dim": "" },
        "slash": { "vb": [0, 0, 16, 16], "sw": 1.4,
            "stroke": "M2.2 2.2l11.6 11.6",
            "fill": "",
            "dim": "" },
        "chev": { "vb": [0, 0, 16, 16], "sw": 1.5,
            "stroke": "M4.2 6.3 8 10.1l3.8-3.8",
            "fill": "",
            "dim": "" },
        "check": { "vb": [0, 0, 16, 16], "sw": 1.6,
            "stroke": "M3.4 8.4 6.4 11.4 12.6 4.8",
            "fill": "",
            "dim": "" },
        // Scan for new devices / networks: Material's `add`, strokes, not
        // an outline -- two bars cannot read as tofu the way a hollow shape does.
        "plus": { "vb": [0, 0, 16, 16], "sw": 1.5,
            "stroke": "M8 3.2v9.6M3.2 8h9.6",
            "fill": "",
            "dim": "" },
        "x": { "vb": [0, 0, 16, 16], "sw": 1.4,
            "stroke": "M4.6 4.6 11.4 11.4M11.4 4.6 4.6 11.4",
            "fill": "",
            "dim": "" },
        "dots": { "vb": [0, 0, 16, 16], "sw": 1.4,
            "stroke": "",
            "fill": "M 2.95 8 A 1.05 1.05 0 1 0 5.05 8 A 1.05 1.05 0 1 0 2.95 8 Z M 6.95 8 A 1.05 1.05 0 1 0 9.05 8 A 1.05 1.05 0 1 0 6.95 8 Z M 10.95 8 A 1.05 1.05 0 1 0 13.05 8 A 1.05 1.05 0 1 0 10.95 8 Z",
            "dim": "" },
        "refresh": { "vb": [0, 0, 16, 16], "sw": 1.4,
            "stroke": "M13.2 8a5.2 5.2 0 1 1-1.7-3.85 M13.4 2v3.1h-3.1",
            "fill": "",
            "dim": "" },
        // The calendar's reminder line (round five). Filled, because an
        // outlined bell at 12 px is a smudge -- small glyphs are filled.
        "bell-fill": { "vb": [0, 0, 16, 16], "sw": 1.2,
            "stroke": "M8 2.4A3.9 3.9 0 0 0 4.1 6.3V9.5L2.8 11.3H13.2L11.9 9.5V6.3A3.9 3.9 0 0 0 8 2.4Z",
            "fill": "M8 2.4A3.9 3.9 0 0 0 4.1 6.3V9.5L2.8 11.3H13.2L11.9 9.5V6.3A3.9 3.9 0 0 0 8 2.4Z M6.3 12.5A1.7 1.7 0 0 0 9.7 12.5Z",
            "dim": "" },
        "note": { "vb": [0, 0, 16, 16], "sw": 1.3,
            "stroke": "M6 12.4V3.2l7-1.4v9.2 M 2.4 12.6 A 1.9 1.9 0 1 0 6.2 12.6 A 1.9 1.9 0 1 0 2.4 12.6 Z M 9.4 11 A 1.9 1.9 0 1 0 13.2 11 A 1.9 1.9 0 1 0 9.4 11 Z",
            "fill": "",
            "dim": "" },
        // ── THE SEARCH PANEL'S ───────────────────────────────
        // Filled, because it is drawn at 13 px (an outlined circle there
        // reads as tofu). The i is a hole: the disc winds clockwise, the
        // dot and the stem the other way, which WindingFill leaves empty.
        "info-fill": { "vb": [0, 0, 16, 16], "sw": 1.4,
            "stroke": "",
            "fill": "M 1.8 8 A 6.2 6.2 0 1 1 14.2 8 A 6.2 6.2 0 1 1 1.8 8 Z M 7 4.4 A 1 1 0 1 0 9 4.4 A 1 1 0 1 0 7 4.4 Z M 7.2 7.1 V 11.9 H 8.8 V 7.1 Z",
            "dim": "" },
        // ── THE BLUETOOTH PANEL'S ────────────────────────────
        // What kind of device a row is, in the fan's slot: BlueZ's `Icon`
        // names the kind and Bt.qml maps it here. Filled, 15 px, same rules
        // as Sound's: holes are subpaths wound the other way. headphones-,
        // speaker- and tv-fill above are Sound's, reused.
        "headset-fill": { "vb": [0, 0, 16, 16], "sw": 1.4,
            "stroke": "M3.1 9.4V7.6a4.9 4.9 0 0 1 9.8 0V9.4 M3.4 12.4c0 1.6 1.2 2.2 3.4 2.2",
            "fill": "M3 8.2H4.2A1.2 1.2 0 0 1 5.4 9.4V11.4A1.2 1.2 0 0 1 4.2 12.6H3A1.2 1.2 0 0 1 1.8 11.4V9.4A1.2 1.2 0 0 1 3 8.2Z M11.8 8.2H13A1.2 1.2 0 0 1 14.2 9.4V11.4A1.2 1.2 0 0 1 13 12.6H11.8A1.2 1.2 0 0 1 10.6 11.4V9.4A1.2 1.2 0 0 1 11.8 8.2Z M 6.9 14.6 A 1.1 1.1 0 1 0 9.1 14.6 A 1.1 1.1 0 1 0 6.9 14.6 Z",
            "dim": "" },
        "keyboard-fill": { "vb": [0, 0, 16, 16], "sw": 1.4,
            "stroke": "",
            "fill": "M2.8 3.6H13.2A1.6 1.6 0 0 1 14.8 5.2V10.8A1.6 1.6 0 0 1 13.2 12.4H2.8A1.6 1.6 0 0 1 1.2 10.8V5.2A1.6 1.6 0 0 1 2.8 3.6Z M3.2 5.3V6.7H4.6V5.3Z M5.6 5.3V6.7H7V5.3Z M8 5.3V6.7H9.4V5.3Z M10.4 5.3V6.7H11.8V5.3Z M3.2 7.5V8.9H4.6V7.5Z M5.6 7.5V8.9H7V7.5Z M8 7.5V8.9H9.4V7.5Z M10.4 7.5V8.9H11.8V7.5Z M4.8 9.7V10.9H11.2V9.7Z",
            "dim": "" },
        "mouse-fill": { "vb": [0, 0, 16, 16], "sw": 1.4,
            "stroke": "",
            "fill": "M8 1.6A4 4 0 0 1 12 5.6V10.4A4 4 0 0 1 4 10.4V5.6A4 4 0 0 1 8 1.6Z M7.3 3.6V6.4H8.7V3.6Z",
            "dim": "" },
        "phone-fill": { "vb": [0, 0, 16, 16], "sw": 1.4,
            "stroke": "",
            "fill": "M5.8 1.2H10.2A1.8 1.8 0 0 1 12 3V13A1.8 1.8 0 0 1 10.2 14.8H5.8A1.8 1.8 0 0 1 4 13V3A1.8 1.8 0 0 1 5.8 1.2Z M6.6 12.1V13.1H9.4V12.1Z",
            "dim": "" },
        "laptop-fill": { "vb": [0, 0, 16, 16], "sw": 1.4,
            "stroke": "M1 12.8h14",
            "fill": "M3.6 2.8H12.4A1.2 1.2 0 0 1 13.6 4V10.6H2.4V4A1.2 1.2 0 0 1 3.6 2.8Z",
            "dim": "" },
        "gamepad-fill": { "vb": [0, 0, 16, 16], "sw": 1.4,
            "stroke": "",
            "fill": "M4.6 4.2H11.4A3.6 3.6 0 0 1 15 7.8V9.6A2.4 2.4 0 0 1 10.9 11.3L9.8 10.2H6.2L5.1 11.3A2.4 2.4 0 0 1 1 9.6V7.8A3.6 3.6 0 0 1 4.6 4.2Z M4.2 6.2V7.2H3.2V8.4H4.2V9.4H5.4V8.4H6.4V7.2H5.4V6.2Z M 9.85 7.2 A 0.75 0.75 0 0 0 11.35 7.2 A 0.75 0.75 0 0 0 9.85 7.2 Z M 11.25 8.8 A 0.75 0.75 0 0 0 12.75 8.8 A 0.75 0.75 0 0 0 11.25 8.8 Z",
            "dim": "" }
    })
}
