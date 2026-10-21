// Pill: the buttons in one round pill, icons always shown (the menus' first look).
import QtQuick

Rectangle {
    id: b
    // ── set by the shell ──
    property string icon: ""
    property bool danger: false
    property bool toggled: false
    property bool hovered: false
    property bool pressed: false
    property string iconFamily: ""
    property color errorContainer: "pink"
    property color errorInk: "black"
    property color primaryColor: "blue"
    property color primaryInk: "white"
    property color inkPlain: "white"
    property color hoverBg: "gray"
    property color pressBg: "gray"
    // ── this style's own ──
    property int size: 28
    property int gap: 2
    property bool pill: true
    property real iconScale: 0.64

    implicitWidth: size
    implicitHeight: size
    radius: height / 2
    color: danger && (hovered || pressed) ? errorContainer : toggled ? primaryColor : pressed ? pressBg : hovered ? hoverBg : "transparent"
    Behavior on color { ColorAnimation { duration: 120 } }
    scale: pressed ? 0.9 : 1
    Behavior on scale { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }
    Text {
        anchors.fill: parent
        // a hair low: Material Symbols' glyphs sit high in their line box (measured 1 px at 1.6)
        topPadding: 1.2
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
        text: b.icon
        font.family: b.iconFamily
        font.pixelSize: Math.round(b.size * b.iconScale)
        color: b.danger && b.hovered ? b.errorInk : b.toggled ? b.primaryInk : b.inkPlain
        opacity: b.hovered || b.toggled ? 1 : 0.75
    }
}
