// Compact action chip for the copy card: icon + label, tonal or filled.
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts

Rectangle {
    id: root
    property string icon: ""
    property string label: ""
    property string tip: ""
    property bool primary: false
    signal activated

    implicitWidth: row.implicitWidth + 24
    implicitHeight: 34
    radius: Appearance.rounding.full
    readonly property color base: primary ? Appearance.m3colors.m3primary : Appearance.m3colors.m3secondaryContainer
    readonly property color fg: primary ? Appearance.m3colors.m3onPrimary : Appearance.m3colors.m3onSecondaryContainer
    // State layer: the content colour over the fill (M3 hover 8 %, press 12 %).
    color: ColorUtils.mix(fg, base, ma.pressed ? 0.12 : (ma.containsMouse ? 0.08 : 0))
    Behavior on color { ColorAnimation { duration: 120 } }

    RowLayout {
        id: row
        anchors.centerIn: parent
        spacing: 6
        MaterialSymbol {
            text: root.icon
            iconSize: 18
            color: root.fg
        }
        StyledText {
            Layout.maximumWidth: 150
            text: root.label
            elide: Text.ElideRight
            font.pixelSize: Appearance.font.pixelSize.smaller
            font.weight: Font.Medium
            color: root.fg
        }
    }
    MouseArea {
        id: ma
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.activated()
    }
    StyledToolTip {
        text: root.tip
        extraVisibleCondition: root.tip.length > 0
    }
}
