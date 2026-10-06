// ═══════════════════════════════════════════════════════════════
// SECTION — a panel's group label: tracked capitals with a hairline
// running to the right edge (or to `lineEnd`, when the label carries an
// action at its right end, as Sound's Test does).
//
// Sans SemiBold 11 at 1 px of track, not the mock-ups' 9 px mono at
// 0.24 em. The mock's set read as loose dots of grey on the live glass
// ("KNOWN NETWORKS breaks in readability"); 10 px mono Medium was next,
// and its W still collapsed ("looks cooked") -- see fontCaps in
// Theme.qml. No count on it.
// ═══════════════════════════════════════════════════════════════

import QtQuick

Item {
    property alias text: lbl.text
    property real lineEnd: width
    width: parent ? parent.width : 0
    height: 14
    Text {
        id: lbl
        anchors.verticalCenter: parent.verticalCenter
        color: Theme.textDim
        font.family: Theme.fontCaps
        font.pixelSize: Theme.capsPx
        font.weight: Theme.capsWeight
        font.letterSpacing: Theme.capsTrack
        font.capitalization: Font.AllUppercase
    }
    Rectangle {
        x: lbl.implicitWidth + 8
        width: parent.lineEnd - x
        height: 1
        anchors.verticalCenter: parent.verticalCenter
        color: Theme.glassEdge
    }
}
