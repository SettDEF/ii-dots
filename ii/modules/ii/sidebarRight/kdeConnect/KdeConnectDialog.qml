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

    // Empty state.
    //
    // Keyed on "no device we can actually act on", NOT on devices.length === 0.
    // With the old test, a device that was listed but filtered out by
    // reachableDevices hid this block AND the summary card below it, and the
    // dialog rendered as nothing but a title and a separator. Whatever else is
    // wrong, there is now always something on screen explaining it.
    ColumnLayout {
        id: emptyState
        Layout.fillWidth: true; Layout.alignment: Qt.AlignHCenter
        spacing: 8
        visible: root.device === null

        readonly property bool anyListed: KdeConnectService.devices.length > 0
        readonly property bool anyPaired: KdeConnectService.devices.some(d => d.trusted)

        MaterialSymbol {
            Layout.alignment: Qt.AlignHCenter
            text: "phonelink_off"; iconSize: 48
            color: Appearance.colors.colSubtext
        }
        StyledText {
            Layout.alignment: Qt.AlignHCenter
            // Distinguishes the three real cases, because "No devices paired" in
            // front of a paired-but-unreachable phone sends you off re-pairing
            // something that was never unpaired.
            text: !emptyState.anyListed ? Translation.tr("No devices paired")
                : !emptyState.anyPaired ? Translation.tr("Device not paired")
                : Translation.tr("Device unreachable")
            font.pixelSize: Appearance.font.pixelSize.normal
        }
        // Shared paragraph style, like every other dialog in the sidebar, rather
        // than a locally-styled StyledText that drifts from them.
        WindowDialogParagraph {
            Layout.fillWidth: true
            horizontalAlignment: Text.AlignHCenter
            text: !emptyState.anyListed
                ? Translation.tr("Open the KDE Connect app on your phone and pair to this device.")
                : !emptyState.anyPaired
                ? Translation.tr("%1 was found on the network but is not paired. Press Pair here, then accept the request on the phone.")
                    .arg(KdeConnectService.devices[0]?.name ?? "")
                : Translation.tr("%1 is paired but not responding. Check that both devices are on the same network and the app is running on the phone.")
                    .arg(KdeConnectService.devices[0]?.name ?? "")
        }
        // Shared button row, same as the other dialogs. Order is deliberate:
        // the least-committal action sits left and the one that actually
        // resolves the state sits right, where these dialogs put their primary.
        WindowDialogButtonRow {
            Layout.fillWidth: true
            Layout.topMargin: 4

            DialogButton {
                buttonText: Translation.tr("Open KDE Connect")
                onClicked: KdeConnectService.openCli()
            }
            DialogButton {
                buttonText: Translation.tr("Refresh")
                onClicked: KdeConnectService.refreshDevices()
            }
            // Pair is the actual fix when a phone is visible but untrusted.
            // Without it the dialog could only tell you to go and do it
            // somewhere else.
            DialogButton {
                visible: emptyState.anyListed && !emptyState.anyPaired
                buttonText: Translation.tr("Pair")
                onClicked: {
                    const d = KdeConnectService.devices.find(x => !x.trusted)
                    if (d) KdeConnectService.pair(d.id)
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
