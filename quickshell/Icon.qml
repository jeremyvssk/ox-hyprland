// ═══════════════════════════════════════════════════════════════
// ICON — one drawing from Icons.qml, at a size, in a colour.
//
// The colour is a PROPERTY, not a baked-in fill, which is the whole
// reason these are geometry rather than image files: a module's
// hover is a colour change, and a colour change on a Shape is a
// ColorAnimation on a binding. On an SVG file it is a re-rasterise,
// or an effect node per icon, or a second copy of the file in a
// second colour. → Icons.qml
//
// SIZE IS A HEIGHT, NOT A BOX. Everything in the set is square
// except the Hyprland mark, which is 241 x 313 of ink -- taller than
// it is wide -- so it gets its own width from its own artwork rather
// than being squeezed into a square. Matching it on either single
// dimension is wrong in the other one; see the caller, which matches
// the AREA of a 12 px glyph and lands on 13.5 tall.
// ═══════════════════════════════════════════════════════════════

import QtQuick
import QtQuick.Shapes

Item {
    id: root

    property string name: "x"
    property color color: Theme.textDim
    property real size: 15

    // An unknown name draws the close mark rather than nothing. A
    // missing icon has to be visible -- an empty module is a control
    // that looks broken, and it is the one failure that reads as the
    // bar being dead rather than as a typo.
    readonly property var g: Icons.set[name] !== undefined ? Icons.set[name] : Icons.set["x"]

    readonly property real sc: size / g.vb[3]

    implicitHeight: size
    implicitWidth: Math.round(g.vb[2] * sc)

    Shape {
        preferredRendererType: Shape.CurveRenderer
        transformOrigin: Item.TopLeft
        scale: root.sc
        x: -root.g.vb[0] * root.sc
        y: -root.g.vb[1] * root.sc
        width: root.g.vb[2]
        height: root.g.vb[3]

        // The stroked run. Round caps and round joins -- see Icons.qml
        // for why that is one rule and not twenty.
        ShapePath {
            strokeColor: root.color
            strokeWidth: root.g.sw
            fillColor: "transparent"
            capStyle: ShapePath.RoundCap
            joinStyle: ShapePath.RoundJoin
            PathSvg { path: root.g.stroke }
        }

        // The same stroke at 35% -- what is behind an off-state's
        // slash, and nothing else in the set: wifi-off's two arcs,
        // vol-off's two waves, bt-off's whole rune.
        ShapePath {
            strokeColor: Qt.rgba(root.color.r, root.color.g, root.color.b, root.color.a * 0.35)
            strokeWidth: root.g.sw
            fillColor: "transparent"
            capStyle: ShapePath.RoundCap
            joinStyle: ShapePath.RoundJoin
            PathSvg { path: root.g.dim }
        }

        // The filled run. WindingFill, not Qt's default OddEven,
        // because these were drawn as SVG and SVG's default is
        // nonzero -- an overlap would punch a hole under the other
        // rule, and that is a bug you only see on the one icon that
        // happens to overlap.
        ShapePath {
            strokeWidth: -1
            fillColor: root.color
            fillRule: ShapePath.WindingFill
            PathSvg { path: root.g.fill }
        }
    }
}
