// Round icon button in the copy card's header pill (pin, open, share, close).
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import QtQuick

Rectangle {
    id: root
    property string icon: ""
    property string tip: ""
    // a toggle that is on (pinned): filled in the accent
    property bool on: false
    signal hit

    implicitWidth: 28
    implicitHeight: 28
    radius: Appearance.rounding.full
    readonly property color base: on ? Appearance.m3colors.m3primary : "transparent"
    readonly property color fg: on ? Appearance.m3colors.m3onPrimary : Appearance.m3colors.m3onSurfaceVariant
    // State layer: the content colour over the fill (M3 hover 8 %, press 12 %).
    color: ColorUtils.mix(fg, on ? base : Appearance.colors.colLayer2, ma.pressed ? 0.12 : (ma.containsMouse ? 0.08 : 0))
    Behavior on color { ColorAnimation { duration: 120 } }

    MaterialSymbol {
        anchors.centerIn: parent
        text: root.icon
        iconSize: 18
        fill: root.on ? 1 : 0
        color: root.fg
    }
    MouseArea {
        id: ma
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.hit()
    }
    StyledToolTip {
        text: root.tip
        extraVisibleCondition: text.length > 0
    }
}
