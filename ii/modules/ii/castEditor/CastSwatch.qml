import qs.modules.common
import qs.modules.common.widgets
import QtQuick

/// A background choice: a two-stop gradient (or a solid when both match),
/// ringed in the primary colour when selected.
Item {
    id: sw
    property color from
    property color to
    property bool selected: false
    property string label: ""
    signal picked()
    implicitWidth: 52; implicitHeight: 40

    Rectangle {
        anchors.fill: parent
        radius: Appearance.rounding.small
        color: "transparent"
        border.width: 2
        border.color: sw.selected ? Appearance.colors.colPrimary : Appearance.colors.colLayer0Border
        Behavior on border.color { ColorAnimation { duration: 140 } }
        Rectangle {
            anchors { fill: parent; margins: 4 }
            radius: Appearance.rounding.verysmall
            gradient: Gradient {
                orientation: Gradient.Horizontal
                GradientStop { position: 0; color: sw.from }
                GradientStop { position: 1; color: sw.to }
            }
        }
    }
    TapHandler { onTapped: sw.picked() }
    HoverHandler { id: hov; cursorShape: Qt.PointingHandCursor }
    StyledToolTip { text: sw.label; extraVisibleCondition: false; alternativeVisibleCondition: hov.hovered && sw.label.length > 0 }
}
