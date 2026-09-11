// VPN half of the connectivity popup — sits alongside the Wi-Fi and Bluetooth
// radars rather than being its own panel, because it is the same kind of thing:
// a connection you turn on and pick a target for.
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts
import Quickshell

Item {
    id: root

    Component.onCompleted: { Vpn.watching = true; Vpn.refresh(); }
    Component.onDestruction: Vpn.watching = false

    StyledFlickable {
        anchors { fill: parent; margins: 16; topMargin: 44 }
        contentHeight: col.implicitHeight
        clip: true

        ColumnLayout {
            id: col
            width: parent.width
            spacing: 12

            // ── Status ────────────────────────────────────────────────────
            Rectangle {
                Layout.fillWidth: true
                implicitHeight: statusRow.implicitHeight + 28
                radius: Appearance.rounding.large
                color: Vpn.connected
                    ? Qt.alpha(Appearance.colors.colPrimary, 0.16)
                    : Appearance.colors.colLayer1
                Behavior on color { ColorAnimation { duration: 180 } }

                RowLayout {
                    id: statusRow
                    anchors { left: parent.left; right: parent.right; top: parent.top; margins: 14 }
                    spacing: 12

                    Rectangle {
                        implicitWidth: 46; implicitHeight: 46
                        radius: Appearance.rounding.full
                        color: Vpn.connected ? Appearance.colors.colPrimary
                                             : Appearance.colors.colLayer2
                        Behavior on color { ColorAnimation { duration: 180 } }
                        MaterialSymbol {
                            anchors.centerIn: parent
                            text: Vpn.busy ? "hourglass_top" : Vpn.connected ? "lock" : "lock_open"
                            iconSize: 24
                            color: Vpn.connected ? Appearance.colors.colOnPrimary
                                                 : Appearance.colors.colSubtext
                        }
                    }
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 2
                        StyledText {
                            Layout.fillWidth: true
                            text: Vpn.statusText
                            font.pixelSize: Appearance.font.pixelSize.normal
                            font.weight: Font.DemiBold
                            color: Appearance.colors.colOnLayer1
                            elide: Text.ElideRight
                        }
                        StyledText {
                            Layout.fillWidth: true
                            text: Vpn.connected
                                ? (Vpn.activeCountry || (Vpn.backend === "nord" ? "NordVPN" : "NetworkManager"))
                                : Translation.tr("Traffic is not tunnelled")
                            font.pixelSize: Appearance.font.pixelSize.smallest
                            color: Appearance.colors.colSubtext
                            elide: Text.ElideRight
                        }
                    }
                    RippleButtonWithIcon {
                        visible: Vpn.connected
                        materialIcon: "link_off"
                        mainText: Translation.tr("Disconnect")
                        onClicked: Vpn.disconnect()
                    }
                }
            }

            // ── Connections ───────────────────────────────────────────────
            StyledText {
                text: Translation.tr("Connections")
                font.pixelSize: Appearance.font.pixelSize.smaller
                font.weight: Font.DemiBold
                color: Appearance.colors.colOnLayer0
            }

            Repeater {
                model: Vpn.profiles
                delegate: Rectangle {
                    required property var modelData
                    Layout.fillWidth: true
                    implicitHeight: 44
                    radius: Appearance.rounding.small
                    color: modelData.active ? Appearance.colors.colPrimaryContainer
                        : (rowMa.containsMouse ? Appearance.colors.colLayer1Hover
                                               : Appearance.colors.colLayer1)
                    Behavior on color { ColorAnimation { duration: 140 } }

                    RowLayout {
                        anchors { fill: parent; leftMargin: 12; rightMargin: 12 }
                        spacing: 10
                        MaterialSymbol {
                            text: modelData.type === "wireguard" ? "vpn_lock" : "vpn_key"
                            iconSize: 18
                            color: modelData.active ? Appearance.colors.colOnPrimaryContainer
                                                    : Appearance.colors.colSubtext
                        }
                        StyledText {
                            Layout.fillWidth: true
                            text: modelData.name
                            elide: Text.ElideRight
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            color: modelData.active ? Appearance.colors.colOnPrimaryContainer
                                                    : Appearance.colors.colOnLayer1
                        }
                        StyledText {
                            visible: modelData.active
                            text: Translation.tr("on")
                            font.pixelSize: Appearance.font.pixelSize.smallest
                            color: Appearance.colors.colOnPrimaryContainer
                        }
                    }
                    MouseArea {
                        id: rowMa
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: parent.modelData.active ? Vpn.disconnect()
                                                           : Vpn.connectTo(parent.modelData)
                    }
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                visible: Vpn.profiles.length === 0
                spacing: 8
                StyledText {
                    Layout.fillWidth: true
                    text: Vpn.nordAvailable
                        ? Translation.tr("No saved servers yet. Run “nordvpn connect” once to get started.")
                        : Translation.tr("No VPN configured. Add one in NetworkManager (OpenVPN or WireGuard), or install a provider's CLI.")
                    wrapMode: Text.WordWrap
                    font.pixelSize: Appearance.font.pixelSize.smallest
                    color: Appearance.colors.colSubtext
                }
                RippleButtonWithIcon {
                    Layout.fillWidth: true
                    materialIcon: "settings_ethernet"
                    mainText: Translation.tr("Open network settings")
                    onClicked: Quickshell.execDetached(["nm-connection-editor"])
                }
            }

            // ── Leak check ────────────────────────────────────────────────
            StyledText {
                Layout.topMargin: 4
                text: Translation.tr("Leak check")
                font.pixelSize: Appearance.font.pixelSize.smaller
                font.weight: Font.DemiBold
                color: Appearance.colors.colOnLayer0
            }

            Rectangle {
                Layout.fillWidth: true
                visible: Vpn.leakDone
                implicitHeight: verdictText.implicitHeight + 16
                radius: Appearance.rounding.small
                readonly property bool bad: Vpn.findings.some(f => f.status === "bad")
                readonly property bool warn: Vpn.findings.some(f => f.status === "warn")
                color: bad ? Qt.alpha(Appearance.m3colors.m3error, 0.18)
                    : warn ? Qt.alpha(Appearance.colors.colSubtext, 0.12)
                    : Qt.alpha(Appearance.colors.colPrimary, 0.16)
                StyledText {
                    id: verdictText
                    anchors { fill: parent; margins: 8 }
                    text: Vpn.verdict
                    wrapMode: Text.WordWrap
                    font.pixelSize: Appearance.font.pixelSize.smallest
                    color: parent.bad ? Appearance.m3colors.m3error : Appearance.colors.colOnLayer1
                }
            }

            Repeater {
                model: Vpn.findings
                delegate: RowLayout {
                    required property var modelData
                    Layout.fillWidth: true
                    spacing: 8
                    MaterialSymbol {
                        text: modelData.status === "ok" ? "check_circle"
                            : modelData.status === "bad" ? "error" : "help"
                        iconSize: 15
                        color: modelData.status === "ok" ? Appearance.colors.colPrimary
                            : modelData.status === "bad" ? Appearance.m3colors.m3error
                            : Appearance.colors.colSubtext
                    }
                    StyledText {
                        text: modelData.label
                        font.pixelSize: Appearance.font.pixelSize.smallest
                        color: Appearance.colors.colOnLayer0
                    }
                    Item { Layout.fillWidth: true }
                    StyledText {
                        Layout.maximumWidth: 230
                        horizontalAlignment: Text.AlignRight
                        text: modelData.value
                        elide: Text.ElideRight
                        font.family: Appearance.font.family.monospace
                        font.pixelSize: Appearance.font.pixelSize.smallest
                        color: Appearance.colors.colSubtext
                    }
                }
            }

            RippleButtonWithIcon {
                Layout.fillWidth: true
                materialIcon: "travel_explore"
                mainText: Vpn.leakChecking ? Translation.tr("Checking…")
                    : Vpn.leakDone ? Translation.tr("Run again")
                    : Translation.tr("Run leak check")
                onClicked: Vpn.runLeakCheck()
                StyledToolTip {
                    text: Translation.tr("Routes and DNS are checked locally. The public address lookup contacts an external service.")
                }
            }
        }
    }
}
