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

    // in a crowded row (the row's `dense`) a secondary chip is only its icon, its name a tooltip
    readonly property bool compact: !primary && !!parent && parent.dense === true
    implicitWidth: compact ? implicitHeight : row.implicitWidth + 24
    Behavior on implicitWidth { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
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
            visible: !root.compact
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
        text: root.compact ? (root.tip || root.label) : root.tip
        extraVisibleCondition: text.length > 0
    }
}
