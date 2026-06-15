import qs
import qs.modules.common
import qs.modules.common.widgets
import qs.services
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io

MouseArea {
    id: root
    property bool borderless: Config.options.bar.borderless
    property bool alwaysShowAllResources: false
    implicitWidth: rowLayout.implicitWidth + rowLayout.anchors.leftMargin + rowLayout.anchors.rightMargin
    implicitHeight: Appearance.sizes.barHeight
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor

    onClicked: GlobalStates.hudOpen = !GlobalStates.hudOpen

    property bool hoverExpand: false
    onEntered: hoverExpand = true
    onExited:  hoverExpand = false

    // MiniMeters integration moved to ii/modules/common/models/quickToggles/MiniMetersToggle.qml.

    // SmartRow distributes the 3 resources evenly along the row and
    // keeps them height-aligned. Each cell fills the column equally so
    // they stay aligned even as some show/hide.
    SmartRow {
        id: rowLayout
        anchors.fill: parent
        anchors.leftMargin: 6
        anchors.rightMargin: 6
        spacing: 8

        Resource {
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignVCenter
            iconName: "memory"
            percentage: ResourceUsage.memoryUsedPercentage
            warningThreshold: Config.options.bar.resources.memoryWarningThreshold
        }

        Resource {
            Layout.fillWidth: shown
            Layout.preferredWidth: shown ? -1 : 0
            Layout.alignment: Qt.AlignVCenter
            iconName: "swap_horiz"
            percentage: ResourceUsage.swapUsedPercentage
            shown: (Config.options.bar.resources.alwaysShowSwap && percentage > 0) ||
                (MprisController.activePlayer?.trackTitle == null) ||
                root.alwaysShowAllResources || root.hoverExpand
            warningThreshold: Config.options.bar.resources.swapWarningThreshold
        }

        Resource {
            Layout.fillWidth: shown
            Layout.preferredWidth: shown ? -1 : 0
            Layout.alignment: Qt.AlignVCenter
            iconName: "planner_review"
            percentage: ResourceUsage.cpuUsage
            shown: Config.options.bar.resources.alwaysShowCpu ||
                !(MprisController.activePlayer?.trackTitle?.length > 0) ||
                root.alwaysShowAllResources || root.hoverExpand
            warningThreshold: Config.options.bar.resources.cpuWarningThreshold
        }
    }

    ResourcesPopup {
        hoverTarget: root
    }
}
