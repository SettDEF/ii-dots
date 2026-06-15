import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts

Item {
    id: root
    property string icon:         ""
    property string label:        ""
    property bool   active:       false
    property bool   compact:      false
    property bool   labelVisible: true

    Layout.fillWidth: true
    // Tall enough to fit icon + label without the label overflowing
    // below the pill background. 30 / 52 instead of 30 / 42.
    implicitHeight: compact ? 30 : 52

    // Width of just the content (icon + label) plus a small padding —
    // exposed so the active-tab pill in the parent can shrink to fit
    // instead of stretching across the whole equal-share cell.
    readonly property real pillWidth: content.implicitWidth + 28

    HoverHandler { id: hov }
    TapHandler   { onTapped: root.clicked() }
    signal clicked()

    // Hover glow on icon-only state
    Rectangle {
        anchors.centerIn: parent
        width: 36; height: 36; radius: 18
        color: Appearance.m3colors.m3onSurfaceVariant
        opacity: hov.hovered && !root.active ? 0.12 : 0
        Behavior on opacity { NumberAnimation { duration: 120 } }
    }

    ColumnLayout {
        id: content
        anchors.horizontalCenter: parent.horizontalCenter
        spacing: 2

        y: Math.max(0, (root.height - implicitHeight) / 2)
        Behavior on y { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }

        MaterialSymbol {
            Layout.alignment: Qt.AlignHCenter
            text: root.icon
            iconSize: compact
                ? Appearance.font.pixelSize.normal
                : Appearance.font.pixelSize.large
            color: root.active
                ? Appearance.m3colors.m3onPrimary
                : Appearance.m3colors.m3onSurfaceVariant
            Behavior on color {
                animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
            }
        }

        StyledText {
            Layout.alignment: Qt.AlignHCenter
            visible: !compact && root.labelVisible
            text: root.label
            font.pixelSize: Appearance.font.pixelSize.small
            color: root.active
                ? Appearance.m3colors.m3onPrimary
                : Appearance.m3colors.m3onSurfaceVariant
            Behavior on color {
                animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
            }
        }
    }
}
