// Breeze: plain glyphs like KDE's title bars, a soft round highlight on hover.
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
    property color errorColor: "red"
    property color primaryColor: "blue"
    property color inkPlain: "white"
    property color hoverBg: "gray"
    // ── this style's own ──
    property int size: 28
    property int gap: 4
    property bool pill: false
    property real iconScale: 0.7

    implicitWidth: size
    implicitHeight: size
    radius: height / 2
    color: danger && hovered ? errorColor : hovered || pressed ? hoverBg : "transparent"
    Behavior on color { ColorAnimation { duration: 120 } }
    Text {
        anchors.fill: parent
        topPadding: 1.2
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
        text: b.icon
        font.family: b.iconFamily
        font.pixelSize: Math.round(b.size * b.iconScale)
        color: b.danger && b.hovered ? "white" : b.toggled ? b.primaryColor : b.inkPlain
    }
}
