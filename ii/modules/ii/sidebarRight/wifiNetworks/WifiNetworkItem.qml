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
    readonly property string ssid: wifiNetwork?.ssid ?? ""
    // A preference has to live on a saved profile, so networks you have never
    // joined offer no control rather than one that would quietly do nothing.
    readonly property bool isSaved: Network.isSaved(root.ssid)
    readonly property bool isPreferred: Network.isPreferred(root.ssid)
    readonly property bool isConnecting: Network.wifiConnectTarget === root.wifiNetwork && !root.isActive

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
                        const pref = root.isPreferred ? " • " + Translation.tr("Preferred") : ""
                        if (root.isActive) return Translation.tr("Connected") + " • " + root.strength + "%" + pref
                        if (root.isSecure) return Translation.tr("Secured") + " • " + root.strength + "%" + pref
                        return root.isPreferred ? Translation.tr("Preferred") : ""
                    }
                }
            }

            // Preferred marker — collapsed rows show it too, so the ranking in
            // the list has a visible reason rather than looking like the sort
            // order is wrong.
            MaterialSymbol {
                visible: root.isPreferred
                text: "star"
                fill: 1
                iconSize: Appearance.font.pixelSize.larger
                color: Appearance.m3colors.m3primary
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

        // ── Detail block ────────────────────────────────────────────────
        // Everything nmcli and iw know about this network. Scan data (band,
        // channel, security, BSSID) is available for every AP; the negotiated
        // rate, real dBm and retry count exist only for the one you are
        // actually associated to, so those appear only there.
        ColumnLayout {
            Layout.topMargin: 8
            Layout.fillWidth: true
            visible: root.expanded && !(root.wifiNetwork?.askingPassword ?? false)
            spacing: 3

            component DetailRow: RowLayout {
                property string k
                property string v
                visible: v.length > 0
                Layout.fillWidth: true
                spacing: 8
                StyledText {
                    // The label keeps its natural width but may not grow the
                    // row; the value takes what is left and elides. A spacer
                    // Item with a non-filling value pushed the row to the sum
                    // of both intrinsic widths instead, which is what ran the
                    // whole dialog past its fixed 350px background.
                    text: k
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: Appearance.colors.colSubtext
                    Layout.maximumWidth: parent.width * 0.5
                    elide: Text.ElideRight
                }
                StyledText {
                    text: v
                    Layout.fillWidth: true
                    horizontalAlignment: Text.AlignRight
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    font.family: Appearance.font.family.monospace
                    color: Appearance.colors.colOnSurfaceVariant
                    elide: Text.ElideRight
                }
            }

            DetailRow {
                k: Translation.tr("Band")
                v: {
                    const f = root.wifiNetwork?.frequency ?? 0;
                    if (!f) return "";
                    return Network.bandFor(f) + "  •  " + Translation.tr("ch") + " "
                         + Network.channelFor(f) + "  •  " + f + " MHz";
                }
            }
            DetailRow {
                k: Translation.tr("Signal")
                v: root.strength + "%  ≈ " + Network.approxDbm(root.strength) + " dBm"
            }
            DetailRow {
                k: Translation.tr("Security")
                v: (root.wifiNetwork?.security ?? "").trim().length > 0
                   ? root.wifiNetwork.security : Translation.tr("Open")
            }
            DetailRow {
                k: "BSSID"
                v: root.wifiNetwork?.bssid ?? ""
            }
            DetailRow {
                k: Translation.tr("Priority")
                v: root.isSaved ? String(Network.priorityOf(root.ssid)) : ""
            }

            // Live figures — only meaningful for the active association.
            DetailRow {
                k: Translation.tr("Link rate")
                v: root.isActive && Network.linkInfo.tx
                   ? Network.linkInfo.tx + " / " + (Network.linkInfo.rx ?? "?") + " Mbit/s" : ""
            }
            DetailRow {
                k: Translation.tr("Actual signal")
                v: root.isActive && Network.linkInfo.dbm ? Network.linkInfo.dbm + " dBm" : ""
            }
            DetailRow {
                // A climbing retry count against a strong signal is the tell for
                // a congested channel or a repeater hop — the failure this whole
                // panel exists to make visible.
                k: Translation.tr("TX retries / failed")
                v: root.isActive && Network.linkInfo.retries
                   ? Network.linkInfo.retries + " / " + (Network.linkInfo.failed ?? "0") : ""
            }
            DetailRow {
                k: Translation.tr("IP address")
                v: root.isActive ? (Network.linkInfo.ip ?? "") : ""
            }
            DetailRow {
                k: Translation.tr("Gateway")
                v: root.isActive ? (Network.linkInfo.gw ?? "") : ""
            }
            DetailRow {
                k: Translation.tr("Connected for")
                v: {
                    if (!root.isActive || !Network.linkInfo.uptime) return "";
                    const s = parseInt(Network.linkInfo.uptime, 10);
                    if (!isFinite(s)) return "";
                    const h = Math.floor(s / 3600), m = Math.floor((s % 3600) / 60);
                    return h > 0 ? (h + "h " + m + "m") : (m + "m");
                }
            }
        }

        // ── Saved-profile controls ──────────────────────────────────────
        ColumnLayout {
            Layout.topMargin: 8
            Layout.fillWidth: true
            visible: root.expanded && root.isSaved
                  && !(root.wifiNetwork?.askingPassword ?? false)
            spacing: 6

            RowLayout {
                Layout.fillWidth: true
                StyledText {
                    text: Translation.tr("Connect automatically")
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: Appearance.colors.colSubtext
                }
                Item { Layout.fillWidth: true }
                StyledSwitch {
                    checked: Network.autoconnectOf(root.ssid)
                    onToggled: Network.setAutoconnect(root.ssid, checked)
                }
            }

            StyledText {
                text: Translation.tr("Band")
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: Appearance.colors.colSubtext
            }
            // Locking the band is the direct fix when one SSID is served by
            // both a fast 5GHz radio and a slow 2.4GHz one and the adapter
            // keeps picking the wrong one.
            //
            // Flow, not RowLayout: three buttons plus a label do not fit across
            // 350px, and a RowLayout does not wrap — it just overflows.
            Flow {
                Layout.fillWidth: true
                spacing: 5
                Repeater {
                    model: [
                        { label: Translation.tr("Auto"), value: "" },
                        { label: "5 GHz",  value: "a"  },
                        { label: "2.4 GHz", value: "bg" }
                    ]
                    delegate: DialogButton {
                        required property var modelData
                        readonly property bool sel: Network.bandLockOf(root.ssid) === modelData.value
                        buttonText: modelData.label
                        colBackground: sel ? Appearance.colors.colPrimary
                                           : Appearance.colors.colLayer4
                        colText: sel ? Appearance.colors.colOnPrimary
                                     : Appearance.colors.colOnLayer4
                        onClicked: Network.setBandLock(root.ssid, modelData.value)
                    }
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

            // Sets connection.autoconnect-priority, which NetworkManager itself
            // acts on when several known networks are in range — so the choice
            // survives reboots and applies even when this shell is not running.
            PrimaryActionButton {
                visible: root.isSaved
                buttonText: root.isPreferred ? Translation.tr("Preferred")
                                             : Translation.tr("Prefer")
                colBackground: root.isPreferred ? Appearance.colors.colPrimary
                                                : Appearance.colors.colLayer4
                colText: root.isPreferred ? Appearance.colors.colOnPrimary
                                          : Appearance.colors.colOnLayer4
                onClicked: Network.setPreferred(root.ssid, !root.isPreferred)

                StyledToolTip {
                    text: Translation.tr("Connect to this network before others when both are in range")
                }
            }

            PrimaryActionButton {
                visible: !root.isActive
                loading: root.isConnecting
                enabled: !root.isConnecting
                buttonText: root.isConnecting ? Translation.tr("Connecting…") : Translation.tr("Connect")
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
