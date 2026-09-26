import qs
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
                        // A device on its cable is not "Paired" in any useful
                        // sense - the cable IS the connection, and a speaker
                        // drops its Bluetooth link when plugged in.
                        let statusText = root.device?.connected ? Translation.tr("Connected")
                                       : Devices.isOnUsb(name) ? Translation.tr("USB")
                                       : Translation.tr("Paired");
                        if (root.device?.batteryAvailable)
                            return statusText + ` • ${Math.round(root.device?.battery * 100)}%`;
                        // BlueZ never publishes Battery1 for some devices; the
                        // service knows where else to get one.
                        const bat = Devices.batteryFor(name);
                        if (bat >= 0) return statusText + ` • ${bat}%`;
                        return statusText;
                    }
                }
            }

            // Per-device controls. Only shown when this device actually has
            // some - Devices.capabilitiesFor() decides, so a new device type
            // needs no change here.
            RippleButton {
                visible: Devices.hasControls(root.device?.name ?? "")
                implicitWidth: 30
                implicitHeight: 30
                buttonRadius: Appearance.rounding.full
                onClicked: {
                    GlobalStates.deviceControlsName = root.device?.name ?? ""
                    GlobalStates.openDeviceControlsRequest++
                }
                // Not "tune": that glyph is already the generic settings
                // button in the audio panels, and two identical icons in one
                // row is two guesses about what the button does. "instant_mix"
                // is vertical faders - reads as "this device's knobs".
                contentItem: MaterialSymbol {
                    anchors.centerIn: parent
                    text: "instant_mix"
                    iconSize: 17
                    color: Appearance.colors.colOnLayer3
                }
                StyledToolTip { text: Translation.tr("Device controls") }
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
