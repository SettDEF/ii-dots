// CPU and memory as a bar readout; the dock's resources panel is its popup.
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.bar
import QtQuick
import QtQuick.Layouts

MouseArea {
    id: root
    required property string widgetId

    readonly property bool showMemory: BarWidgets.get(root.widgetId, "showMemory") !== false
    readonly property real peak: Math.max(ResourceUsage.cpuUsage,
        root.showMemory ? ResourceUsage.memoryUsedPercentage : 0)

    hoverEnabled: true
    implicitWidth: label.implicitWidth
    implicitHeight: label.implicitHeight + 8

    StyledText {
        id: label
        anchors.centerIn: parent
        text: root.showMemory
            ? `${Math.round(ResourceUsage.cpuUsage * 100)}% · ${Math.round(ResourceUsage.memoryUsedPercentage * 100)}%`
            : `${Math.round(ResourceUsage.cpuUsage * 100)}%`
        font.pixelSize: Appearance.font.pixelSize.smaller
        font.family: Appearance.font.family.monospace
        // Same threshold the panel's bars turn red at.
        color: root.peak > 0.9 ? Appearance.m3colors.m3error : Appearance.colors.colOnLayer1
    }

    StyledPopup {
        hoverTarget: root
        Loader {
            anchors.centerIn: parent
            width: 220
            source: Qt.resolvedUrl("../../common/widgets/ResourcesPanel.qml")
        }
    }
}
