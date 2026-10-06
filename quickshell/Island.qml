// ═══════════════════════════════════════════════════════════════
// THE ISLAND — one silhouette, and the two corners that are the
// handle.
//
// THE SHAPE IS ONE PATH. The body, its two bottom radii, the flush
// top edge and both concave flare fillets are a single closed
// outline, built once as an SVG string and handed to every layer
// that paints. There is no second surface, nothing that can drift
// out of alignment, nothing that can catch a different shadow --
// which was the whole point of the one-piece decision, and it is
// also the answer to "it reads as two extra pieces stuck to the
// ends". It is one object or the drawing is wrong.
//
// WHY AN SVG STRING AND NOT PathLine/PathArc ELEMENTS: QML path
// elements cannot be shared between ShapePaths, so six layers of
// glass would mean six transcriptions of the same geometry and six
// chances for one of them to be wrong. One string, six readers.
//
// WHY THE FILLET IS AN ARC AND NOT A ROUNDED CORNER: a border-radius
// can only round a corner OUTWARD. The flare's corner is concave --
// it bites INWARD -- and the only way to draw that is to add
// material outside a disc. Each fillet is the part of a `flare`-
// sized square that falls OUTSIDE a disc of radius `flare` centred
// on the square's inner-bottom corner.
// ═══════════════════════════════════════════════════════════════

import QtQuick
import QtQuick.Shapes

Item {
    id: root

    // The island's own width -- animated by whoever owns the density
    // state. The item is WIDER than this by the flare on each side,
    // because the flare is part of the silhouette and has to be
    // inside the box that paints it.
    property int islandWidth: Theme.widthNormal

    // Which face the bar is wearing. The island draws it; shell.qml
    // owns the state and the ladder that walks it.
    property string density: "normal"

    // Fired by the corner handles. -1 = the left corner (step down a
    // density), +1 = the right (step up). The island does not know
    // what a density is; it knows which end you hit.
    signal stepped(int direction)

    // Which panel the body is grown into, "" for none. shell.qml owns
    // it; the island asks for a change and draws the answer.
    property string panel: ""
    signal panelRequested(string name)

    // ── THE PANEL IS THE BODY, TALLER ────────────────────────
    // Not a surface hung under the bar: the same silhouette with a
    // bigger H, so the fillets, the side edges, the bottom corners and
    // the ring are the ones the bar already has. ONE NUMBER ANIMATES,
    // 0 -> 438 on top of the bar's 38, on the drawer curve at the
    // panel's 220 -- a surface arriving, which should settle. Closing is
    // the same curve back: it rolls up the way it came down.
    //
    // A Behavior, not a keyframe, because a panel can be toggled twice
    // in a second, and the second press must turn the glass around from
    // wherever it is rather than snap it back to 38 and start again.
    property real depth: panel === "calendar" ? Theme.calendarDepth : panel !== "" ? Theme.panelDepth : 0

    Behavior on depth {
        enabled: Anim.enabled
        NumberAnimation {
            duration: Anim.ms(Anim.panel)
            easing.type: Easing.BezierSpline
            easing.bezierCurve: Anim.drawer
        }
    }

    readonly property int fl: Theme.flare
    readonly property int br: Theme.bodyRadius

    implicitWidth: islandWidth + fl * 2
    implicitHeight: Theme.islandHeight + depth
    width: implicitWidth
    height: implicitHeight

    // ── THE OUTLINE ──────────────────────────────────────────
    // Traversed clockwise from the left flare's outer top corner.
    // Convex corners sweep clockwise (SVG flag 1), the two concave
    // fillets counter-clockwise (flag 0) -- that flag IS the
    // difference between a corner that is rounded off and one that
    // is bitten into.
    //
    // `kx` divides every x. At kx = 1 this is the silhouette. Larger
    // values give the same outline squeezed horizontally, which is
    // how a circular gradient is made elliptical: squeeze the path,
    // stretch the fill back. Arc radii squeeze with it, which is why
    // the rx and ry of each arc are written separately.
    function silhouette(kx) {
        const W = width, H = height, f = fl, r = br;
        const X = v => (v / kx).toFixed(4);
        const R = v => (v / kx).toFixed(4);
        return "M " + X(0) + " 0"
             + " L " + X(W) + " 0"
             + " A " + R(f) + " " + f + " 0 0 0 " + X(W - f) + " " + f
             + " L " + X(W - f) + " " + (H - r)
             + " A " + R(r) + " " + r + " 0 0 1 " + X(W - f - r) + " " + H
             + " L " + X(f + r) + " " + H
             + " A " + R(r) + " " + r + " 0 0 1 " + X(f) + " " + (H - r)
             + " L " + X(f) + " " + f
             + " A " + R(f) + " " + f + " 0 0 0 " + X(0) + " 0"
             + " Z";
    }

    readonly property string path1: silhouette(1)

    // ── THE SPECULAR SWEEP, IN CSS TERMS ─────────────────────
    // linear-gradient(100deg, ...). A CSS angle is measured from
    // "to top" clockwise, so 100deg points right and 10 degrees
    // down; the gradient LINE is long enough that both corners of
    // the box project onto it, which is what the |W.ux| + |H.uy|
    // sum is. Deliberately off-axis -- at 90 it is one more
    // horizontal gradient in a stack of them; at 100 it reads as a
    // reflection.
    readonly property real sweepUx: Math.sin(100 * Math.PI / 180)   //  0.98481
    readonly property real sweepUy: -Math.cos(100 * Math.PI / 180)  //  0.17365
    // Measured on the BAR's 38, not the body's current height: the
    // sweep and the bloom are the bar's own highlights, and a panel
    // opening under the bar must not re-light the bar above it.
    readonly property real sweepLen: Math.abs(width * sweepUx) + Math.abs(Theme.islandHeight * sweepUy)

    // ── THE SHOULDER BLOOM ───────────────────────────────────
    // radial-gradient(120% 240% at 26% -60%, inner, transparent 62%)
    // -- an ellipse 120% of the box wide and 240% of it tall,
    // centred above the bar's left shoulder, where the light is.
    // Qt's RadialGradient is circular only, so it is drawn at the
    // VERTICAL radius and the fill is stretched horizontally by the
    // ratio of the two. Same figure, arrived at from the other side.
    readonly property real bloomRy: Theme.islandHeight * 2.40
    readonly property real bloomK: (width * 1.20) / bloomRy
    readonly property real bloomCx: width * 0.26
    readonly property real bloomCy: Theme.islandHeight * -0.60

    Behavior on islandWidth {
        enabled: Anim.enabled
        NumberAnimation {
            duration: Anim.ms(Anim.density)
            easing.type: Easing.BezierSpline
            easing.bezierCurve: Anim.drawer
        }
    }

    // ── THE LIFT — 0 IN NORMAL, 1 IN FULL ────────────────────
    // The maximise, as one number. The dot block's top edge and the
    // cell's height both run off it, on one clock, so they cannot
    // drift apart the way four independently tweened properties on
    // the old waybar cell did -- which is the bug the workspace row's
    // own header is about, met from the other side.
    //
    // COMPACT READS 0, LIKE NORMAL. That is not a fallback, it is the
    // design: Compact is a different arrangement of two things, not a
    // point on this axis, so stepping to or from it never starts this
    // animation at all and the density collapse stays the cross-fade
    // it already was. Going Full -> Compact this does run, but the
    // compact branches below take their numbers whole and there is
    // nothing on screen for it to move.
    //
    // It is NOT the density curve. 620 -> 118 is the glass travelling
    // and gets 220 ms; this is a 160 px block going 6 px inside a bar
    // that stays where it is, and gets 160. → Anim.qml
    property real lift: density === "full" ? 1 : 0

    Behavior on lift {
        enabled: Anim.enabled
        NumberAnimation {
            duration: Anim.ms(Anim.maximise)
            easing.type: Easing.BezierSpline
            easing.bezierCurve: Anim.easeOut
        }
    }

    // Where the block sits in Normal: centred in the body. Full puts
    // it at Theme.wsTopFull and the lift walks between the two.
    readonly property real wsTopNormal: Math.round((Theme.islandHeight - Theme.wsCellHeight) / 2)

    // ═══ THE GLASS — ONE SHAPE, SIX LAYERS ══════════════════
    Shape {
        anchors.fill: parent
        preferredRendererType: Shape.CurveRenderer
        asynchronous: false

        // 1 · the base tint, under everything.
        ShapePath {
            strokeWidth: -1
            fillColor: Theme.glassBase
            PathSvg { path: root.path1 }
        }

        // 2 · the body. THREE stops, not two -- bright where the
        // surface curves toward the light, thinnest through the
        // middle, heaviest where it pools at the foot. Two stops
        // between near-identical darks is a flat fill with a slope
        // on it.
        ShapePath {
            strokeWidth: -1
            fillGradient: LinearGradient {
                x1: 0; y1: 0
                x2: 0; y2: root.height
                GradientStop { position: 0.00; color: Theme.glassTop }
                GradientStop { position: 0.46; color: Theme.glassMid }
                GradientStop { position: 1.00; color: Theme.glassBot }
            }
            PathSvg { path: root.path1 }
        }

        // 3 · the shoulder bloom. The fill is a circle; the
        // fillTransform stretches it about its own centre into the
        // ellipse CSS asked for, so the path stays the silhouette
        // and only the paint is distorted.
        //
        // The stop colours carry the same RGB at both ends.
        // "transparent" is #00000000 and Qt interpolates
        // un-premultiplied, so fading to it fades through BLACK --
        // a white bloom would pick up a grey bruise on its way out.
        ShapePath {
            strokeWidth: -1
            fillTransform: Qt.matrix4x4(
                root.bloomK, 0, 0, root.bloomCx * (1 - root.bloomK),
                0, 1, 0, 0,
                0, 0, 1, 0,
                0, 0, 0, 1)
            fillGradient: RadialGradient {
                centerX: root.bloomCx; centerY: root.bloomCy
                centerRadius: root.bloomRy
                focalX: root.bloomCx; focalY: root.bloomCy
                focalRadius: 0
                GradientStop { position: 0.00; color: Theme.glassInner }
                GradientStop { position: 0.62; color: Qt.rgba(1, 1, 1, 0) }
                GradientStop { position: 1.00; color: Qt.rgba(1, 1, 1, 0) }
            }
            PathSvg { path: root.path1 }
        }

        // 4 · the sweep.
        ShapePath {
            strokeWidth: -1
            fillGradient: LinearGradient {
                x1: root.width / 2 - root.sweepLen / 2 * root.sweepUx
                y1: Theme.islandHeight / 2 - root.sweepLen / 2 * root.sweepUy
                x2: root.width / 2 + root.sweepLen / 2 * root.sweepUx
                y2: Theme.islandHeight / 2 + root.sweepLen / 2 * root.sweepUy
                // Blend drops the sweep to .020: with the top edge
                // dissolving there is less surface for it to run on.
                GradientStop { position: 0.00; color: Qt.rgba(1, 1, 1, Theme.blendTop ? 0.020 : 0.055) }
                GradientStop { position: 0.46; color: Qt.rgba(1, 1, 1, 0) }
                GradientStop { position: 1.00; color: Qt.rgba(1, 1, 1, 0) }
            }
            PathSvg { path: root.path1 }
        }

        // 5 · THE RING. Stroked ON the path, not inside it -- half
        // the width falls outside the silhouette and is clipped away
        // by the window mask, which is what GTK does and therefore
        // what the live bar actually shows. A full pixel inside
        // measured twice as heavy as waybar.
        //
        // It closes over the fillets too, which is the thing the
        // flare was missing when you said it vanished against black:
        // it had a shape but no edge. A box ring cannot draw a
        // concave corner; this is not a box ring.
        ShapePath {
            strokeColor: Theme.outline ? Theme.glassEdge : "transparent"
            strokeWidth: 1
            fillColor: "transparent"
            PathSvg { path: root.path1 }
        }

        // 6 · BLEND. Flush to the top there IS no top edge, so stop
        // lighting one: a short black ramp instead, and the bar
        // dissolves upward into the screen edge. Painted last, over
        // the ring, because dissolving the ring's top hairline is
        // the point rather than a side effect.
        //
        // At flare 4 this ramp is 10 px deep and the fillet is 4 px
        // tall, so Blend buries the curve entirely. Theme.blendTop
        // is off for exactly that reason -- see Theme.qml.
        ShapePath {
            strokeWidth: -1
            fillGradient: LinearGradient {
                x1: 0; y1: 0
                x2: 0; y2: 10
                GradientStop { position: 0.0; color: Qt.rgba(0, 0, 0, Theme.blendTop ? 0.55 : 0.0) }
                GradientStop { position: 1.0; color: Qt.rgba(0, 0, 0, 0) }
            }
            PathSvg { path: root.path1 }
        }
    }

    // ═══ THE CONTENT ════════════════════════════════════════
    // Three zones, and the arrangement is SPLIT ENDS -- grouped by
    // verb, not by category. Everything on the left opens a chooser you
    // reach into (the mark searches; the three radios pick a network, a
    // device, an output). The right is what you READ, then what
    // reshapes the session -- and the session mark is quarantined at
    // the far end where you will not hit it by accident.
    //
    // ZONES, NOT ONE ROW. waybar has no zones: modules-center is one
    // content-hugging box that GTK re-centres, so anything that changes
    // width moves every module in the bar. Here the centre zone is
    // pinned to the island's actual middle, so the workspace row cannot
    // be moved by anything happening at either end. That is the whole
    // reason the readouts can open at all.
    //
    // clip: true is load-bearing. It is the island's own edge, and if a
    // cluster ever overruns it you see it cut off rather than spilling
    // over the glass -- which is a visible bug instead of a silent one.
    Item {
        id: content
        x: root.fl
        width: root.islandWidth
        // The bar's row, always 38 -- the body under it may be taller.
        height: Theme.islandHeight
        clip: true

        readonly property bool compact: root.density === "compact"
        readonly property bool full: root.density === "full"

        // ── LEFT: the choosers ───────────────────────────────
        Row {
            id: zoneL
            anchors.left: parent.left
            anchors.leftMargin: 7
            anchors.verticalCenter: parent.verticalCenter
            spacing: 2
            visible: !content.compact
            opacity: content.compact ? 0 : 1
            // THE GLASS MAY TRAVEL, THE CONTENT MAY NOT. On a density
            // change the bar's edges move 251 px sideways, which is
            // 47 px a frame -- five times the sideways strobe
            // threshold. Nothing with a glyph in it is dragged across
            // that: the clusters cross-fade and the glass does the
            // travelling. See Anim.qml.
            Behavior on opacity {
                enabled: Anim.enabled
                NumberAnimation { duration: Anim.ms(Anim.fade) }
            }

            // THE MARK IS THE SEARCH BUTTON, and it is 10.5 x 13.5
            // rather than 15 x 15. The Hyprland mark is 241 x 313 of
            // ink -- ratio 0.776 -- so it is the one glyph in the row
            // taller than it is wide, and matching it on either single
            // dimension is wrong in the other one. Drawn at 15 tall it
            // towered over the row; matched to the 12 px of height the
            // other glyphs draw, it went 9.3 wide and read as small.
            // So match the AREA the eye is actually weighing:
            //   reference  12.0 x 12.0 of ink = 144
            //   mark       0.776 * h * h = 144  ->  h = 13.6, w = 10.6
            // Matching the mean of the two dimensions gives 13.5/10.5,
            // the same answer from the other side. That is the number.
            //
            // SEARCH IS QUICKSHELL'S (2026-09-16): no script, the mark grows
            // the body into SearchPanel.qml, as the radios do theirs.
            Mod {
                icon: "hypr"
                glyph: 13.5
                padLeft: 5
                padRight: 8
                anchors.verticalCenter: parent.verticalCenter
                onPressed: root.panelRequested(root.panel === "search" ? "" : "search")
            }

            // 40 px, and it is the only real air in the cluster. The
            // mark opens a chooser over the whole session; the three
            // radios pick a network, a device, an output. Same verb,
            // different scope -- so the gap is a group boundary, not
            // padding, and it is the one place the row has room to
            // say so.
            Item { width: 40 - zoneL.spacing * 2; height: 1 }

            // ALL THREE REPORT. Each of these acts AND reads, and
            // each reads from a different kind of source, which is
            // the only reason there are three mechanisms and not one:
            // PipeWire and BlueZ are native Quickshell services and are
            // simply bound; the Wi-Fi glyph is watched at the command line
            // and told by its own bus, because it was built before 0.3.1's
            // Networking module was found (the Wi-Fi PANEL binds it).
            // → Audio.qml, Bt.qml, Network.qml, and Watcher.qml for the
            // Wi-Fi glyph's shape.
            //
            // NOT ONE OF THEM POLLS. That matters here rather than in
            // those files because this is the row where it would have
            // shown: three modules re-reading three subsystems on
            // three timers is what the waybar this replaces did, and
            // it is why its icons disagreed with its panels.
            //
            // NONE OF THE THREE IS EWW'S. They have no script: pressing one
            // grows the body into WifiPanel.qml, BluetoothPanel.qml (since
            // 2026-09-16) or SoundPanel.qml.
            Mod {
                icon: Network.icon
                anchors.verticalCenter: parent.verticalCenter
                onPressed: root.panelRequested(root.panel === "wifi" ? "" : "wifi")
            }
            Mod {
                icon: Bt.icon
                anchors.verticalCenter: parent.verticalCenter
                onPressed: root.panelRequested(root.panel === "bluetooth" ? "" : "bluetooth")
            }
            // SOUND IS QUICKSHELL'S TOO (2026-09-16): no script, the glyph
            // grows the body into SoundPanel.qml.
            Mod {
                icon: Audio.muted ? "vol-off" : "vol"
                anchors.verticalCenter: parent.verticalCenter
                onPressed: root.panelRequested(root.panel === "sound" ? "" : "sound")
            }
        }

        // ── CENTRE: where you are ────────────────────────────
        // ONE centred row, and in Normal it holds exactly one thing.
        // That matters: with only the workspaces in it, the row's
        // centre IS the island's centre, so the dots sit on the bar's
        // true middle rather than wherever the two clusters happen to
        // leave. In waybar they do not -- the row is one
        // content-hugging box that GTK re-centres, and the dots sit
        // about 8 px right of true centre because of it.
        //
        // COMPACT STACKS THE SAME TWO THINGS RATHER THAN SHRINKING
        // THEM. Side by side they do not fit: 118 px is a real budget
        // and the clock next to five dots came to 128, with the last
        // dot cut off by the island's own edge. Stacked, the row is
        // 90 px and the clock sits under it -- which is why Compact
        // is possible at all, and it is the same two things either
        // way. The dots are on top; that is your call and it is the
        // one place this departs from the doc.
        //
        // ONE Workspaces, not one per face. The row is the same
        // object at two sizes, so a switch cannot leave two of them
        // disagreeing about which workspace is focused.
        Workspaces {
            id: workspaces
            compact: content.compact
            lift: root.lift
            anchors.horizontalCenter: parent.horizontalCenter
            // THE BLOCK RISES, AND THAT IS THE WHOLE EXPLANATION OF
            // THE SECOND LINE. Without it the readouts simply appear
            // under a bar that did not move and nothing says where
            // the line came from; the dots step up, and the space
            // they leave is where the numbers land. One word for it
            // -- spatial consistency -- or it would not be built.
            y: content.compact
               ? Theme.compactTop
               : root.wsTopNormal + (Theme.wsTopFull - root.wsTopNormal) * root.lift
        }

        // ── THE SECOND LINE ──────────────────────────────────
        // Full, and it costs no surface: the run lands on the line
        // the stacked clock already uses, inside a body that stays
        // 38 px tall. The centre zone does not widen -- the block
        // above it left, and nothing else in the row moved.
        //
        // OPACITY ONLY, NO TRAVEL. The container is allowed to move;
        // the numbers inside it are not. They arrive on the line they
        // will live on, 40 ms after the block has started up, landing
        // with it -- and on the way out they leave first, with no
        // delay, so the line empties and then closes rather than
        // closing on top of live text. → Anim.qml
        Readouts {
            id: readouts
            anchors.horizontalCenter: parent.horizontalCenter
            y: Theme.readoutBaseline - height / 2
            opacity: content.full ? 1 : 0
            visible: opacity > 0

            Behavior on opacity {
                enabled: Anim.enabled
                SequentialAnimation {
                    PauseAnimation {
                        duration: content.full ? Anim.ms(Anim.readoutDelay) : 0
                    }
                    NumberAnimation {
                        duration: Anim.ms(content.full ? Anim.readoutIn : Anim.readoutOut)
                    }
                }
            }
        }

        // The compact clock: one line, under the dots, and a hit band
        // that runs from there to the island's bottom edge. The TEXT
        // is 13 px tall and a 13 px target is not a target -- so the
        // box is 20 and the text sits at the top of it. Nothing is
        // drawn in the slack; it is there to be clicked.
        Clock {
            id: compactClock
            visible: content.compact
            compactMode: true
            anchors.horizontalCenter: parent.horizontalCenter
            y: workspaces.y + workspaces.height + Theme.compactGap
            width: content.width
            height: content.height - y
        }

        // ── RIGHT: what you read, then what ends the session ──
        Row {
            id: zoneR
            anchors.right: parent.right
            anchors.rightMargin: 7
            anchors.verticalCenter: parent.verticalCenter
            spacing: 2
            visible: !content.compact
            opacity: content.compact ? 0 : 1
            Behavior on opacity {
                enabled: Anim.enabled
                NumberAnimation { duration: Anim.ms(Anim.fade) }
            }

            // The clock grows the body into CalendarPanel.qml (2026-09-28).
            Clock { onPressed: root.panelRequested(root.panel === "calendar" ? "" : "calendar") }

            // 40 px between what you READ and what ENDS the session --
            // the left end's group boundary, mirrored. The session mark
            // is quarantined at the far end for the same reason: it is
            // the one control on this bar you cannot take back, and it
            // should not sit a glyph's width from the clock you look at
            // forty times an hour. It was 24 until 2026-09-30, and the
            // two ends did not match: 57 px of air between the mark's
            // ink and the radios', 45 between the clock's and power's,
            // so the clock read as pushed toward the edge.
            Item { width: 40 - zoneR.spacing * 2; height: 1 }

            // NO GEAR YET, DELIBERATELY. The doc's right cluster is
            // clock, settings, session -- but settings opens a control
            // centre, and a control centre is not one of the five
            // popups -- eww's or the island's. It does not
            // exist yet on this desktop in any form.
            //
            // A button with nothing behind it is the exact failure
            // this bar's mask comment is about from the other side:
            // you press it, nothing happens, and a bar that does not
            // respond is indistinguishable from a bar that has died.
            // It arrives when there is something for it to open.
            Mod {
                icon: "power"
                script: "power-menu.sh"
                dir: Actions.hypr
                anchors.verticalCenter: parent.verticalCenter
                onPressed: root.panelRequested("")
            }
        }

    }

    // ═══ THE PANEL ══════════════════════════════════════════
    // Clipped to the body's current depth, so the content is uncovered
    // by the glass as it grows rather than travelling in on its own --
    // the glass may travel, the content may not.
    //
    // It ALSO arrives on opacity, the maximise's rule for a line of
    // content under a moving container: in 40 ms after the glass starts,
    // landing with it; out at once and in 90, so the body empties and
    // then rolls up rather than rolling up over live text. layer.enabled
    // only while it is fading -- the card and an open row are
    // translucent over glass, and fading them one by one is a different
    // picture at 50%. → Anim.qml, motion.md §4
    Item {
        x: root.fl
        y: Theme.islandHeight
        width: root.islandWidth
        height: root.depth
        clip: true
        visible: root.depth > 0

        PanelFade {
            open: root.panel === "wifi"
            WifiPanel { open: parent.open; onCloseRequested: root.panelRequested("") }
        }
        PanelFade {
            open: root.panel === "bluetooth"
            BluetoothPanel { open: parent.open; onCloseRequested: root.panelRequested("") }
        }
        PanelFade {
            open: root.panel === "sound"
            SoundPanel { open: parent.open; onCloseRequested: root.panelRequested("") }
        }
        PanelFade {
            open: root.panel === "search"
            SearchPanel { open: parent.open; onCloseRequested: root.panelRequested("") }
        }
        PanelFade {
            open: root.panel === "calendar"
            height: Theme.calendarDepth
            CalendarPanel { open: parent.open; onCloseRequested: root.panelRequested("") }
        }
    }

    // One panel's fade, written once for every panel. `visible` follows
    // it, so a panel that is not open takes no pointer: they share one clip.
    // `|| open` because the fade starts 40 ms late and an invisible item
    // cannot take the keyboard: Search's field must have it on the frame
    // the panel opens, or the first letters of a fast `firefox` are lost.
    component PanelFade: Item {
        id: pf
        property bool open: false
        width: Theme.widthNormal
        height: Theme.panelDepth
        visible: opacity > 0 || open
        opacity: open ? 1 : 0
        layer.enabled: opacity < 1
        Behavior on opacity {
            enabled: Anim.enabled
            SequentialAnimation {
                PauseAnimation { duration: pf.open ? Anim.ms(Anim.readoutDelay) : 0 }
                NumberAnimation { duration: Anim.ms(pf.open ? Anim.readoutIn : Anim.fade) }
            }
        }
    }

    // ═══ THE CORNERS ARE THE HANDLE ═════════════════════════
    // Minimise/maximise as a module costs a seventh button on the
    // end that is already crowded. These two cost no pixels: they
    // are the flare, made clickable. Flush to the top they sit on
    // output row 0, so the pointer can be thrown at the ceiling and
    // cannot overshoot.
    //
    // THE FILLET IS 4 PX. THE TARGET IS 18 x 15. The handle reaches
    // 14 px INTO the body past the fillet, so the thing you hit was
    // never the same object as the curve you see -- which is the
    // answer to "maybe it's too small for clicking". In Compact the
    // target is the same 18 x 15 on a bar a fifth as wide, so it
    // gets proportionally easier to hit, not harder.
    readonly property int handleWidth: fl + 14
    readonly property int handleHeight: 15

    MouseArea {
        id: handleLeft
        x: 0; y: 0
        width: root.handleWidth
        height: root.handleHeight
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onPressed: root.stepped(-1)      // respond on press, not on release
    }

    MouseArea {
        id: handleRight
        x: root.width - root.handleWidth; y: 0
        width: root.handleWidth
        height: root.handleHeight
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onPressed: root.stepped(1)
    }

    // THE GLOW IS AT THE CORNER, NOT ON THE BAR. An earlier pass lit
    // the whole rim, which washed 620 px of surface to acknowledge an
    // 18 px target -- feedback in the wrong place and at the wrong
    // scale. This is the same falloff the Blend top edge uses:
    // brightest under the pointer, gone by three flare-widths in.
    //
    // It is drawn on THE SILHOUETTE'S OWN PATH, so the glow cannot
    // spill past the shape: the concave fillet stays a hard edge
    // while the light on it is soft. Painted after the ring, which is
    // where it sits in the CSS too.
    component CornerGlow: Shape {
        id: glow
        property real cx: 0
        property bool lit: false
        // 44 x 18, at .13. It was the doc's 96 x 40 at .22, and on the
        // live glass that lit a quarter of the bar's end for an 18 px
        // target -- "a bit heavy" (2026-09-30). Now it stays on the
        // corner: a tint at the edge, gone before the first glyph.
        readonly property real k: 44 / 18

        anchors.fill: parent
        preferredRendererType: Shape.CurveRenderer
        opacity: lit ? 1 : 0
        Behavior on opacity {
            enabled: Anim.enabled
            NumberAnimation {
                duration: Anim.ms(Anim.hover)
                easing.type: Easing.BezierSpline
                easing.bezierCurve: Anim.easeOut
            }
        }

        ShapePath {
            strokeWidth: -1
            fillTransform: Qt.matrix4x4(
                glow.k, 0, 0, glow.cx * (1 - glow.k),
                0, 1, 0, 0,
                0, 0, 1, 0,
                0, 0, 0, 1)
            fillGradient: RadialGradient {
                centerX: glow.cx; centerY: 1
                centerRadius: 18
                focalX: glow.cx; focalY: 1
                focalRadius: 0
                GradientStop { position: 0.00; color: Qt.alpha(Theme.accent, 0.13) }
                GradientStop { position: 0.45; color: Qt.alpha(Theme.accent, 0.04) }
                GradientStop { position: 0.76; color: Qt.alpha(Theme.accent, 0.0) }
                GradientStop { position: 1.00; color: Qt.alpha(Theme.accent, 0.0) }
            }
            PathSvg { path: root.path1 }
        }
    }

    CornerGlow { cx: root.fl;              lit: handleLeft.containsMouse }
    CornerGlow { cx: root.width - root.fl; lit: handleRight.containsMouse }
}
