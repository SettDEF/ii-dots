// macOS: traffic-light dots, the icon on hover.
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
    // ── this style's own ──
    property int size: 22
    property int gap: 9
    property bool pill: false
    property real iconScale: 0.62
    property color closeColor: "#ff5f56"
    property color actionColor: "#ffbd2e"
    property color toggledColor: "#27c93f"

    readonly property color base: danger ? closeColor : toggled ? toggledColor : actionColor
    implicitWidth: size
    implicitHeight: size
    radius: height / 2
    color: pressed ? Qt.darker(base, 1.15) : base
    border.width: 1
    border.color: Qt.darker(base, 1.3)
    Text {
        anchors.fill: parent
        topPadding: 1.2
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
        visible: b.hovered
        text: b.icon
        font.family: b.iconFamily
        font.pixelSize: Math.round(b.size * b.iconScale)
        color: Qt.rgba(0, 0, 0, 0.6)
    }
}
