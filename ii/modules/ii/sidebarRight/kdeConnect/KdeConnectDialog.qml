import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io

WindowDialog {
    id: root
    backgroundHeight: 540

    property var device: KdeConnectService.firstDevice

    WindowDialogTitle {
        text: Translation.tr("KDE Connect")
    }
    WindowDialogSeparator {}

    // Empty state
    ColumnLayout {
        Layout.fillWidth: true; Layout.alignment: Qt.AlignHCenter
        spacing: 8
        visible: KdeConnectService.devices.length === 0

        MaterialSymbol {
            Layout.alignment: Qt.AlignHCenter
            text: "phonelink_off"; iconSize: 48
            color: Appearance.colors.colSubtext
        }
        StyledText {
            Layout.alignment: Qt.AlignHCenter
            text: Translation.tr("No devices paired")
            font.pixelSize: Appearance.font.pixelSize.normal
        }
        StyledText {
            Layout.alignment: Qt.AlignHCenter
            Layout.fillWidth: true
            text: Translation.tr("Open the KDE Connect app on your phone and pair to this device.")
            font.pixelSize: Appearance.font.pixelSize.smaller
            color: Appearance.colors.colSubtext
            wrapMode: Text.WordWrap
            horizontalAlignment: Text.AlignHCenter
        }
        Rectangle {
            Layout.alignment: Qt.AlignHCenter
            implicitWidth: refreshRow.implicitWidth + 24
            implicitHeight: 36
            radius: 18
            color: refreshHov.hovered ? Appearance.m3colors.m3surfaceContainerHighest : Appearance.m3colors.m3surfaceContainerHigh
            HoverHandler { id: refreshHov }
            TapHandler { onTapped: KdeConnectService.refreshDevices() }
            Row {
                id: refreshRow
                anchors.centerIn: parent; spacing: 6
                MaterialSymbol {
                    anchors.verticalCenter: parent.verticalCenter
                    text: "refresh"; iconSize: Appearance.font.pixelSize.small
                    color: Appearance.m3colors.m3onSurface
                }
                StyledText {
                    anchors.verticalCenter: parent.verticalCenter
                    text: Translation.tr("Refresh")
                    color: Appearance.m3colors.m3onSurface
                }
            }
        }
    }

    // Device picker (when more than one)
    RowLayout {
        Layout.fillWidth: true
        spacing: 6
        visible: KdeConnectService.devices.length > 1
        Repeater {
            model: KdeConnectService.devices
            delegate: Rectangle {
                required property var modelData
                readonly property bool active: root.device && modelData.id === root.device.id
                Layout.fillWidth: true
                implicitHeight: 38
                radius: 19
                color: active ? Appearance.colors.colPrimary
                    : (devHov.hovered ? Appearance.m3colors.m3surfaceContainerHighest : Appearance.m3colors.m3surfaceContainerHigh)
                Behavior on color { ColorAnimation { duration: 100 } }
                HoverHandler { id: devHov }
                TapHandler { onTapped: root.device = modelData }
                RowLayout {
                    anchors.centerIn: parent; spacing: 6
                    MaterialSymbol {
                        text: modelData.reachable ? "smartphone" : "phonelink_off"
                        iconSize: Appearance.font.pixelSize.small
                        color: parent.parent.active ? Appearance.m3colors.m3onPrimary : Appearance.m3colors.m3onSurface
                    }
                    StyledText {
                        text: modelData.name
                        color: parent.parent.active ? Appearance.m3colors.m3onPrimary : Appearance.m3colors.m3onSurface
                    }
                }
            }
        }
    }

    // Selected device summary card
    Rectangle {
        Layout.fillWidth: true
        implicitHeight: 96
        radius: 16
        color: Appearance.m3colors.m3surfaceContainerHigh
        visible: root.device !== null

        RowLayout {
            anchors.fill: parent; anchors.margins: 14
            spacing: 14

            MaterialSymbol {
                text: "smartphone"
                iconSize: 48
                color: Appearance.colors.colPrimary
            }
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 2
                StyledText {
                    text: root.device?.name ?? ""
                    font.pixelSize: Appearance.font.pixelSize.normal
                    font.weight: Font.Medium
                    color: Appearance.m3colors.m3onSurface
                }
                StyledText {
                    text: root.device?.reachable
                        ? Translation.tr("Connected")
                        : Translation.tr("Offline")
                    color: root.device?.reachable
                        ? Appearance.m3colors.m3primary : Appearance.colors.colSubtext
                    font.pixelSize: Appearance.font.pixelSize.smaller
                }
                RowLayout {
                    spacing: 6
                    visible: (root.device?.battery ?? -1) >= 0
                    MaterialSymbol {
                        text: root.device?.charging ? "battery_charging_full" : "battery_full"
                        iconSize: Appearance.font.pixelSize.small
                        color: Appearance.m3colors.m3onSurface
                    }
                    StyledText {
                        text: (root.device?.battery ?? 0) + "%"
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        color: Appearance.m3colors.m3onSurface
                    }
                }
            }
        }
    }

    KdeConnectActions {
        Layout.fillWidth: true
        device: root.device
    }
}
