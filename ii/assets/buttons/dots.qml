// Dots: round dots in the theme's colours, the icon inside on hover (the close the error
// colour, a button that is on the tertiary, the others the primary). The panels' look (the
// sidebars keep their own buttons; the user, 2026-10-22): macOS dots in the theme's colours.
import QtQuick

Item {
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
    property color tertiaryColor: "violet"
    property color inkOnFill: "black"
    // ── this style's own ──
    // the dot, and the room around it that takes the click
    property int dot: 24
    property int size: 28
    property int gap: 6
    property bool pill: false
    property real iconScale: 0.66
    property real rest: 0.82
    property color closeColor: errorColor
    property color actionColor: primaryColor
    property color toggledColor: tertiaryColor

    readonly property color base: danger ? closeColor : toggled ? toggledColor : actionColor
    implicitWidth: size
    implicitHeight: size
    Rectangle {
        anchors.centerIn: parent
        width: b.dot
        height: b.dot
        radius: width / 2
        // a little quieter at rest, the full colour under the pointer
        color: b.pressed ? Qt.darker(b.base, 1.15) : b.hovered ? b.base : Qt.rgba(b.base.r, b.base.g, b.base.b, b.rest)
        Behavior on color { ColorAnimation { duration: 120 } }
        scale: b.pressed ? 0.88 : b.hovered ? 1.12 : 1
        Behavior on scale { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }
        Text {
            anchors.fill: parent
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
            opacity: b.hovered ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: 120 } }
            text: b.icon
            font.family: b.iconFamily
            font.pixelSize: Math.round(b.dot * b.iconScale)
            color: b.inkOnFill
        }
    }
}
