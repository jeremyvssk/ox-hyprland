//@ pragma NativeTextRendering
// ═══════════════════════════════════════════════════════════════
// DATUM — the bar. Day 1: the shape and the handle.
//
// The pragma on line 1 must stay on line 1 (Quickshell reads `//@` lines
// only at the top). NativeTextRendering draws type with the platform's
// hinted rasteriser instead of Qt's distance fields, which render 9-10 px
// labels soft -- the panel's tracked capitals and the clock's date broke
// up without it (2026-09-13). It is read at launch: restart, not reload.
//
// No modules. Day 2 puts real readings and real actions in; this
// step exists to get the two things that can go wrong out of the
// way while there is still room in the week -- the silhouette, and
// the pointer mask.
//
// ── THE ARCHITECTURE, AND WHY THERE IS ONLY ONE OF IT ────────
// ONE PanelWindow, mapped at login, as wide as the screen and as
// tall as the tallest state the bar can reach. It is never resized
// and never unmapped. That is not a preference; three independent
// findings force it:
//
//   * Hyprland cannot animate a layer usefully -- a layer slide
//     offsets the surface by its own height along the nearest screen
//     edge, so a panel hanging under the bar enters from off-screen
//     ACROSS the island.
//   * Quickshell cannot resize a window smoothly -- every frame of a
//     resize is a Wayland configure round-trip, and animating window
//     size is an open question upstream.
//   * The eww era already landed here: every popup carries
//     `animation = none` and a GtkRevealer does the work, because
//     the window moving WAS the bug.
//
// So the surface never moves and everything animates inside it.
// Nothing in this file asks the compositor for anything.
//
// ── WHICH MAKES THE MASK THE MOST DANGEROUS LINE HERE ────────
// A full-height invisible surface sits over the output at all times.
// `mask` is the only thing stopping it swallowing every click on the
// screen. If it is wrong, the desktop looks frozen while showing
// nothing -- windows still repaint, the cursor still moves, so it
// does not look like a crash, it looks like every application broke
// at once. That exact failure has been reported on this machine four
// times, always as something else ("Firefox is frozen", "nothing
// launches"), and chased down the wrong subsystem three of those.
//
// The escape hatch is bound BEFORE this file runs:
//     SUPER + SHIFT + Q  ->  pkill -x quickshell     (keybinds.lua)
// A Hyprland bind still fires in that state, because the compositor
// sees the key before any client does.
//
// The mask is built from THE SILHOUETTE, fillets included -- not
// from the island's rectangle. A body-shaped mask leaves the flare
// unclickable: hover would still light the rim (that is Qt, which
// does not consult the mask) while the click falls straight through
// to the desktop. It would not error, would not log, and would not
// respond.
// ═══════════════════════════════════════════════════════════════

import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import Quickshell.Wayland
import QtQuick

ShellRoot {
    id: shell

    // ── DENSITY ──────────────────────────────────────────────
    // Read it as a rule, not a table: THE ENDS COLLAPSE, THE MIDDLE
    // CHOOSES. Every corner does something in every state -- an
    // earlier version clamped, so two of the six clicks did nothing,
    // and on a bar a control that does nothing is indistinguishable
    // from a bar that has stopped responding.
    //
    //   from Normal:   left -> Compact      right -> Full
    //   from either end: both corners -> Normal
    //
    // FULL IS THE SAME 620 WIDE AND THE SAME 38 TALL -- the readouts
    // arrive as a second row inside a body that does not grow, which
    // is why this is a three-state machine with only two widths in it
    // and one height. That is also why the mask and the blur region
    // below read `targetWidth` and the island's own height: a shelf
    // under the row or a tongue hanging off it would have put a second
    // rectangle in both of them, and the exclusive zone would have
    // become a question. It never does. The one thing that changes
    // that height is a panel, and a panel is the same rectangle made
    // taller. → Readouts.qml, WifiPanel.qml
    property string density: "normal"

    // A panel is always 620 wide -- panel width is never a design
    // variable -- so an open panel holds the island at Normal's width
    // whatever face the bar is wearing.
    readonly property int targetWidth: density === "compact" && panel === ""
                                       ? Theme.widthCompact
                                       : Theme.widthNormal

    // ── WHICH PANEL IS OPEN ──────────────────────────────────
    // "", "wifi", "bluetooth", "sound", "search" or "calendar". One at a time, owned here, because the mask, the
    // blur, the keyboard and the focus grab all have to agree about it.
    property string panel: ""

    function step(direction) {
        if (density !== "normal") density = "normal";
        else density = direction < 0 ? "compact" : "full";
    }

    function cycle() {
        density = density === "compact" ? "normal"
                : density === "normal"  ? "full"
                : "compact";
    }

    // ── THE KEYBOARD TWIN ────────────────────────────────────
    // Every pointer control on this desktop has one, and the reason
    // is in panels.md: a control you can only reach with the pointer
    // is a control you cannot reach when the pointer is the thing
    // that is broken.
    //
    //     qs ipc call bar cycle
    //     qs ipc call bar set normal
    //
    // Bound to SUPER+ALT+B, not SUPER+B -- Super+B is brave, and
    // has been for longer than this bar has existed. It was
    // SUPER+SHIFT+B until that went to the Bluetooth panel (2026-10-06).
    IpcHandler {
        target: "bar"

        function cycle(): string {
            shell.cycle();
            return shell.density;
        }

        function set(value: string): string {
            if (value !== "compact" && value !== "normal" && value !== "full")
                return "error: expected compact|normal|full, got " + value;
            shell.density = value;
            return shell.density;
        }

        function get(): string {
            return shell.density;
        }
    }

    // The panel's keyboard twin, for the same reason:
    //
    //     qs ipc call panel toggle wifi|bluetooth|sound|search|calendar
    //     qs ipc call panel close
    IpcHandler {
        target: "panel"

        function toggle(name: string): string {
            if (name !== "wifi" && name !== "bluetooth" && name !== "sound" && name !== "search" && name !== "calendar")
                return "error: expected wifi|bluetooth|sound|search|calendar, got " + name;
            shell.panel = shell.panel === name ? "" : name;
            return shell.panel === "" ? "closed" : shell.panel;
        }

        function close(): string {
            shell.panel = "";
            return "closed";
        }

        function get(): string {
            return shell.panel;
        }
    }

    // ── SUPER+S IS NOT THE IPC ───────────────────────────────
    // Search is the one panel you type into the moment it opens, and
    // `qs ipc` is a process start: 62–67 ms measured before `panel`
    // changes, and every letter typed in that time went to the window
    // underneath -- "firefox" arrived as "irefox" 3 times in 10 at a fast
    // typist's pace. A global shortcut is the compositor calling this
    // process directly. keybinds.lua binds it:
    //     hl.dsp.global("quickshell:search")
    // toggle-search.sh keeps the IPC for everything that is not a key.
    GlobalShortcut {
        name: "search"
        description: "Open or close the Search panel"
        onPressed: shell.panel = shell.panel === "search" ? "" : "search"
    }

    // The other four panels open from the keyboard the same way, on
    // Super+Shift and the panel's first letter (keybinds.lua). Same
    // path as Search rather than the IPC: the calendar has a field you
    // type into too, and one path for every key is one path to reason
    // about. The same key again closes; another panel's key switches.
    GlobalShortcut {
        name: "wifi"
        description: "Open or close the Wi-Fi panel"
        onPressed: shell.panel = shell.panel === "wifi" ? "" : "wifi"
    }
    GlobalShortcut {
        name: "bluetooth"
        description: "Open or close the Bluetooth panel"
        onPressed: shell.panel = shell.panel === "bluetooth" ? "" : "bluetooth"
    }
    GlobalShortcut {
        name: "sound"
        description: "Open or close the Sound panel"
        onPressed: shell.panel = shell.panel === "sound" ? "" : "sound"
    }
    GlobalShortcut {
        name: "calendar"
        description: "Open or close the Calendar panel"
        onPressed: shell.panel = shell.panel === "calendar" ? "" : "calendar"
    }

    // ── CLICK OUTSIDE CLOSES IT, WITHOUT A BACKDROP ──────────
    // eww's panels closed on an outside click by laying a transparent
    // full-screen button under themselves, and that button is the
    // leaked surface that made the desktop look frozen four times
    // (panels.md). This asks the compositor instead: while a panel is
    // open, Hyprland's focus grab routes the keyboard to this window,
    // and the first click on any OTHER surface ends the grab -- which is
    // the close. Nothing is laid over the screen, so there is nothing to
    // leak.
    HyprlandFocusGrab {
        windows: [win]
        active: shell.panel !== ""
        onCleared: shell.panel = ""
    }

    PanelWindow {
        id: win

        // Full width, pinned to the top. The island is centred
        // INSIDE it; the window itself never moves.
        anchors { top: true; left: true; right: true }

        // ── HOW TALL, AND WHY IT IS STATED ONCE ──────────────
        // The tallest state the bar can reach: the island plus the
        // deepest panel. It was 470 -- sound's eww depth -- "until a
        // panel that needs more is built". The calendar was that panel
        // at 600 from 2026-09-28 until round five put it back to 438
        // (2026-09-30); the formula stays so it can grow again. The mask
        // keeps everything below the island click-through.
        implicitHeight: Theme.islandHeight + Math.max(Theme.panelDepth, Theme.calendarDepth)

        color: "transparent"

        // ── THE ZONE, AND THE DAY IT CHANGED HANDS ──────────
        // This window is 476 tall so a panel has somewhere to open,
        // and 438 of that is empty most of the time. So the zone is
        // STATED, not inferred: ExclusionMode.Auto would reserve the
        // surface, and the desktop would lose half a screen to a
        // popup that is not open.
        //
        // 38, NOT waybar's 50. waybar sat 12 px down from the screen
        // edge and reserved its margin along with itself, because it
        // was a bar in a gutter -- general.lua's "one gap, everywhere"
        // rule, where the space above the island equals the space
        // below it. This island is not in the gutter. It HANGS OFF
        // THE TOP EDGE: the fillets at its top corners are cut so the
        // glass meets the edge with a concave curve, which is a shape
        // that only means anything when there is nothing above it.
        // So there is no gap above to reserve, and the gap below is
        // gaps_out, as it is for every other window.
        //
        // Net effect on every window on the desktop: the usable area
        // starts 12 px higher than it did under waybar.
        exclusionMode: ExclusionMode.Normal
        exclusiveZone: Theme.islandHeight

        // A namespace, so `hyprctl layers` can be read back and the
        // layerrules on day 3 have something to match. A missing
        // namespace makes every animation rule match nothing, and it
        // does so silently.
        WlrLayershell.namespace: "datum"

        // ── THE KEYBOARD, ONLY WHILE A PANEL IS OPEN ─────────
        // OnDemand, NEVER Exclusive. An exclusive-keyboard layer takes
        // every pointer event on the output (panels.md -- a
        // leaked one makes the desktop look frozen), and this surface is 638 px tall and mapped
        // for the whole session. With no panel open it asks for no
        // keyboard at all, which is what it did before panels existed.
        WlrLayershell.keyboardFocus: shell.panel !== "" ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None

        readonly property int islandX: Math.round((width - shell.targetWidth) / 2)

        // ═══ THE MASK ═══════════════════════════════════════
        // Body plus two fillets. Each fillet is a `flare`-sized
        // square with a disc of the same radius SUBTRACTED from it,
        // the disc centred on the square's inner-bottom corner --
        // which is exactly the quarter the silhouette uses, arrived
        // at the same way.
        //
        // Subtracting costs six lines and buys back 3.4 px2 per
        // corner of desktop that would otherwise be invisibly
        // unclickable. The point is not the 3.4 px2; it is that the
        // mask and the drawing are the same figure, so neither can
        // drift from the other.
        mask: Region {
            x: win.islandX
            y: 0
            width: shell.targetWidth
            height: island.height
            radius: 0
            bottomLeftRadius: Theme.bodyRadius
            bottomRightRadius: Theme.bodyRadius

            Region {
                intersection: Intersection.Combine
                x: win.islandX - Theme.flare
                y: 0
                width: Theme.flare
                height: Theme.flare

                Region {
                    intersection: Intersection.Subtract
                    shape: RegionShape.Ellipse
                    x: win.islandX - Theme.flare * 2
                    y: 0
                    width: Theme.flare * 2
                    height: Theme.flare * 2
                }
            }

            Region {
                intersection: Intersection.Combine
                x: win.islandX + shell.targetWidth
                y: 0
                width: Theme.flare
                height: Theme.flare

                Region {
                    intersection: Intersection.Subtract
                    shape: RegionShape.Ellipse
                    x: win.islandX + shell.targetWidth
                    y: 0
                    width: Theme.flare * 2
                    height: Theme.flare * 2
                }
            }
        }

        // ═══ THE BLUR ═══════════════════════════════════════
        // waybar gets its blur from `layerrule = blur, waybar` plus
        // `ignore_alpha 0.15`: the whole 3416x38 surface is blurred
        // and the alpha floor is what carves the pill out of it.
        // That is why style.css carries a "do not go below composite
        // 0.20" floor -- glass thinner than the floor silently stops
        // being glass.
        //
        // Here the region is stated directly, so the alpha floor buys
        // nothing, the fillets are blurred as curves rather than as a
        // rectangle that happens to be transparent at the corners,
        // and the glass can go as thin as it likes. It is the same
        // figure as the mask for the same reason.
        BackgroundEffect.blurRegion: Region {
            x: win.islandX
            y: 0
            width: shell.targetWidth
            height: island.height
            radius: 0
            bottomLeftRadius: Theme.bodyRadius
            bottomRightRadius: Theme.bodyRadius

            Region {
                intersection: Intersection.Combine
                x: win.islandX - Theme.flare
                y: 0
                width: Theme.flare
                height: Theme.flare

                Region {
                    intersection: Intersection.Subtract
                    shape: RegionShape.Ellipse
                    x: win.islandX - Theme.flare * 2
                    y: 0
                    width: Theme.flare * 2
                    height: Theme.flare * 2
                }
            }

            Region {
                intersection: Intersection.Combine
                x: win.islandX + shell.targetWidth
                y: 0
                width: Theme.flare
                height: Theme.flare

                Region {
                    intersection: Intersection.Subtract
                    shape: RegionShape.Ellipse
                    x: win.islandX + shell.targetWidth
                    y: 0
                    width: Theme.flare * 2
                    height: Theme.flare * 2
                }
            }
        }

        Island {
            id: island
            islandWidth: shell.targetWidth
            density: shell.density
            panel: shell.panel
            x: Math.round((parent.width - width) / 2)
            y: 0
            onStepped: direction => shell.step(direction)
            onPanelRequested: name => shell.panel = name
        }
    }
}
