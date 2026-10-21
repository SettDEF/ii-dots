// Vibrant: big dots without icons, brighter inside, the full colour at the edge.
// A button style (services/ButtonStyles.qml): the shell sets what is above the line; every
// property below it can be changed in the config (appearance.glass.decor.panelButtonVars).
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
    property color neutralColor: "gray"
    // ── this style's own ──
    property int size: 28
    property int gap: 9
    property bool pill: false
    property real lighten: 1.28
    property real hoverLighten: 1.45
    property int edge: 2
    property color closeColor: errorColor
    property color actionColor: neutralColor
    property color toggledColor: primaryColor

    readonly property color base: danger ? closeColor : toggled ? toggledColor : actionColor
    implicitWidth: size
    implicitHeight: size
    radius: height / 2
    color: pressed ? base : Qt.lighter(base, hovered ? hoverLighten : lighten)
    Behavior on color { ColorAnimation { duration: 120 } }
    border.width: edge
    border.color: base
    scale: pressed ? 0.9 : 1
    Behavior on scale { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }
}
