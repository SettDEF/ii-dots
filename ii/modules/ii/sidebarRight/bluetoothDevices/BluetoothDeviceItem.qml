import qs.modules.common
import qs.modules.common.widgets
import qs.services
import QtQuick
import QtQuick.Layouts

DialogListItem {
    id: root
    required property var device
    property bool expanded: false
    pointingHandCursor: !expanded
    readonly property bool isConnecting: root.device?.connecting ?? false

    onClicked: expanded = !expanded
    altAction: () => expanded = !expanded
    

    contentItem: ColumnLayout {
        anchors {
            fill: parent
            topMargin: root.verticalPadding
            leftMargin: root.horizontalPadding
            rightMargin: root.horizontalPadding
        }
        spacing: 0

        RowLayout {
            // Name
            spacing: 10

            MaterialSymbol {
                iconSize: Appearance.font.pixelSize.larger
                text: Icons.getBluetoothDeviceMaterialSymbol(root.device?.icon || "")
                color: Appearance.colors.colOnSurfaceVariant
            }

            ColumnLayout {
                spacing: 2
                Layout.fillWidth: true
                StyledText {
                    Layout.fillWidth: true
                    color: Appearance.colors.colOnSurfaceVariant
                    elide: Text.ElideRight
                    text: root.device?.name || Translation.tr("Unknown device")
                    textFormat: Text.PlainText
                }
                StyledText {
                    visible: (root.device?.connected || root.device?.paired) ?? false
                    Layout.fillWidth: true
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: Appearance.colors.colSubtext
                    elide: Text.ElideRight
                    text: {
                        if (!root.device?.paired) return "";
                        const name = root.device?.name ?? "";
                        // A JBL on the USB-C cable is not "Paired" in any useful
                        // sense — the cable IS the connection, and the speaker
                        // drops its Bluetooth link when plugged in.
                        const onUsb = JblBattery.usbConnected && JblBattery.isSupported(name);
                        let statusText = root.device?.connected ? Translation.tr("Connected")
                                       : onUsb ? Translation.tr("USB")
                                       : Translation.tr("Paired");
                        if (root.device?.batteryAvailable)
                            return statusText + ` • ${Math.round(root.device?.battery * 100)}%`;
                        // BlueZ never publishes Battery1 for these speakers; the
                        // number comes from Harman's own BLE control service.
                        if (JblBattery.isSupported(name) && JblBattery.percent >= 0)
                            return statusText + ` • ${JblBattery.percent}%`;
                        return statusText;
                    }
                }
            }

            MaterialSymbol {
                text: "keyboard_arrow_down"
                iconSize: Appearance.font.pixelSize.larger
                color: Appearance.colors.colOnLayer3
                rotation: root.expanded ? 180 : 0
                Behavior on rotation {
                    animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                }
            }
        }

        RowLayout {
            visible: root.expanded
            Layout.topMargin: 8
            Item {
                Layout.fillWidth: true
            }
            PrimaryActionButton {
                loading: root.isConnecting
                enabled: !root.isConnecting
                buttonText: root.isConnecting
                            ? (root.device?.connected ? Translation.tr("Disconnecting…") : Translation.tr("Connecting…"))
                            : (root.device?.connected ? Translation.tr("Disconnect") : Translation.tr("Connect"))

                onClicked: {
                    if (root.device?.connected) {
                        root.device.disconnect();
                    } else {
                        root.device.connect();
                    }
                }
            }
            PrimaryActionButton {
                visible: root.device?.paired ?? false
                colBackground: Appearance.colors.colError
                colBackgroundHover: Appearance.colors.colErrorHover
                colRipple: Appearance.colors.colErrorActive
                colText: Appearance.colors.colOnError

                buttonText: Translation.tr("Forget")
                onClicked: {
                    root.device?.forget();
                }
            }
        }
        Item {
            Layout.fillHeight: true
        }
    }
}
