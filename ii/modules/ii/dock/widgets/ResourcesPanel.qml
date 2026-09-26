import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts

ColumnLayout {
    spacing: 6

    component Row_: ColumnLayout {
        property string label: ""
        property real fraction: 0
        property string detail: ""
        Layout.fillWidth: true
        spacing: 1
        RowLayout {
            Layout.fillWidth: true
            StyledText {
                Layout.fillWidth: true
                text: label
                font.pixelSize: Appearance.font.pixelSize.smallest
                color: Appearance.colors.colSubtext
            }
            StyledText {
                text: detail
                font.pixelSize: Appearance.font.pixelSize.smallest
                font.family: Appearance.font.family.monospace
                color: Appearance.colors.colOnLayer0
            }
        }
        Rectangle {
            Layout.fillWidth: true
            implicitHeight: 5
            radius: Appearance.rounding.full
            color: Qt.alpha(Appearance.colors.colOnLayer0, 0.18)
            Rectangle {
                anchors { left: parent.left; top: parent.top; bottom: parent.bottom }
                width: parent.width * Math.max(0, Math.min(1, fraction))
                radius: parent.radius
                color: fraction > 0.9 ? Appearance.m3colors.m3error : Appearance.colors.colPrimary
            }
        }
    }

    Row_ {
        label: Translation.tr("CPU")
        fraction: ResourceUsage.cpuUsage
        detail: `${Math.round(ResourceUsage.cpuUsage * 100)}%`
    }
    Row_ {
        label: Translation.tr("Memory")
        fraction: ResourceUsage.memoryUsedPercentage
        detail: `${Math.round(ResourceUsage.memoryUsedPercentage * 100)}%`
    }
    Row_ {
        label: Translation.tr("Swap")
        fraction: ResourceUsage.swapUsedPercentage
        detail: `${Math.round(ResourceUsage.swapUsedPercentage * 100)}%`
    }
}
