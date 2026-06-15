import qs
import qs.modules.common
import qs.modules.common.widgets
import qs.services
import qs.services.network
import QtQuick
import QtQuick.Layouts
import Quickshell

DialogListItem {
    id: root
    required property WifiAccessPoint wifiNetwork
    enabled: !(Network.wifiConnectTarget === root.wifiNetwork && !wifiNetwork?.active)

    active: (wifiNetwork?.askingPassword || wifiNetwork?.active) ?? false

    // Auto-expand when this network is the active one or is currently
    // requesting a password — mirrors how the bluetooth item shows its
    // actions inline.
    property bool expanded: (wifiNetwork?.askingPassword ?? false)
                         || (wifiNetwork?.active ?? false)
    readonly property bool isActive: wifiNetwork?.active ?? false
    readonly property bool isSecure: wifiNetwork?.isSecure ?? false
    readonly property int  strength: wifiNetwork?.strength ?? 0

    pointingHandCursor: !expanded
    onClicked: {
        if (expanded) {
            // Already expanded — collapse only if not active/asking-password
            if (!root.isActive && !(root.wifiNetwork?.askingPassword ?? false))
                expanded = false
        } else {
            expanded = true
            // For unknown insecure networks, kick off the connect immediately
            if (!root.isActive && !root.isSecure) {
                Network.connectToWifiNetwork(wifiNetwork)
            }
        }
    }
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
            spacing: 10

            MaterialSymbol {
                iconSize: Appearance.font.pixelSize.larger
                text: root.strength > 80 ? "signal_wifi_4_bar"
                    : root.strength > 60 ? "network_wifi_3_bar"
                    : root.strength > 40 ? "network_wifi_2_bar"
                    : root.strength > 20 ? "network_wifi_1_bar"
                    : "signal_wifi_0_bar"
                color: Appearance.colors.colOnSurfaceVariant
            }

            ColumnLayout {
                spacing: 2
                Layout.fillWidth: true
                StyledText {
                    Layout.fillWidth: true
                    color: Appearance.colors.colOnSurfaceVariant
                    elide: Text.ElideRight
                    text: root.wifiNetwork?.ssid ?? Translation.tr("Unknown")
                    textFormat: Text.PlainText
                }
                StyledText {
                    visible: text.length > 0
                    Layout.fillWidth: true
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: Appearance.colors.colSubtext
                    elide: Text.ElideRight
                    text: {
                        if (Network.wifiConnectTarget === root.wifiNetwork && !root.isActive)
                            return Translation.tr("Connecting…")
                        if (root.isActive) return Translation.tr("Connected") + " • " + root.strength + "%"
                        if (root.isSecure) return Translation.tr("Secured") + " • " + root.strength + "%"
                        return ""
                    }
                }
            }

            // Lock / connected indicator
            MaterialSymbol {
                visible: root.isSecure || root.isActive
                text: root.isActive
                    ? "check"
                    : (Network.wifiConnectTarget === root.wifiNetwork ? "settings_ethernet" : "lock")
                iconSize: Appearance.font.pixelSize.larger
                color: Appearance.colors.colOnSurfaceVariant
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

        // Password prompt — only when nmcli reports askingPassword
        ColumnLayout {
            id: passwordPrompt
            Layout.topMargin: 8
            Layout.fillWidth: true
            visible: root.wifiNetwork?.askingPassword ?? false

            MaterialTextField {
                id: passwordField
                Layout.fillWidth: true
                placeholderText: Translation.tr("Password")
                echoMode: TextInput.Password
                inputMethodHints: Qt.ImhSensitiveData
                onAccepted: Network.changePassword(root.wifiNetwork, passwordField.text)
            }

            RowLayout {
                Layout.fillWidth: true
                Item { Layout.fillWidth: true }
                DialogButton {
                    buttonText: Translation.tr("Cancel")
                    onClicked: root.wifiNetwork.askingPassword = false
                }
                PrimaryActionButton {
                    buttonText: Translation.tr("Connect")
                    onClicked: Network.changePassword(root.wifiNetwork, passwordField.text)
                }
            }
        }

        // Captive portal helper — only when active on an open network
        RowLayout {
            id: publicWifiPortal
            Layout.topMargin: 8
            Layout.fillWidth: true
            visible: (root.wifiNetwork?.active && (root.wifiNetwork?.security ?? "").trim().length === 0) ?? false

            DialogButton {
                Layout.fillWidth: true
                buttonText: Translation.tr("Open network portal")
                colBackground: Appearance.colors.colLayer4
                colBackgroundHover: Appearance.colors.colLayer4Hover
                colRipple: Appearance.colors.colLayer4Active
                onClicked: {
                    Network.openPublicWifiPortal()
                    GlobalStates.sidebarRightOpen = false
                }
            }
        }

        // Action row — Connect / Disconnect / Forget. Mirrors bluetooth.
        RowLayout {
            visible: root.expanded
                  && !(root.wifiNetwork?.askingPassword ?? false)
            Layout.topMargin: 8
            Layout.fillWidth: true

            Item { Layout.fillWidth: true }

            PrimaryActionButton {
                visible: !root.isActive
                buttonText: Translation.tr("Connect")
                onClicked: Network.connectToWifiNetwork(root.wifiNetwork)
            }
            PrimaryActionButton {
                visible: root.isActive
                buttonText: Translation.tr("Disconnect")
                onClicked: Network.disconnectWifiNetwork()
            }
            PrimaryActionButton {
                // "Forget" deletes the saved nmcli connection. Only meaningful
                // for known networks; we approximate "known" as secure
                // networks the user has connected to before. nmcli will no-op
                // for unknown SSIDs.
                visible: root.isSecure
                colBackground: Appearance.colors.colError
                colBackgroundHover: Appearance.colors.colErrorHover
                colRipple: Appearance.colors.colErrorActive
                colText: Appearance.colors.colOnError

                buttonText: Translation.tr("Forget")
                onClicked: {
                    Quickshell.execDetached([
                        "nmcli", "connection", "delete",
                        root.wifiNetwork?.ssid ?? ""
                    ])
                }
            }
        }

        Item { Layout.fillHeight: true }
    }
}
