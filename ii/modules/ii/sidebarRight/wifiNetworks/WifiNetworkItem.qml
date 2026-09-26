import qs
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
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

    // DialogListItem is transparent by default, so every network was loose
    // text on the dialog's own background and the expanded card had nothing
    // holding it together. Each network is a surface now: faint when it is
    // one of several in a list, solid once it is carrying a card of detail.
    buttonRadius: Appearance.rounding.normal
    colBackground: root.expanded
        ? Appearance.colors.colLayer2
        : ColorUtils.transparentize(Appearance.colors.colLayer2, 0.55)
    colBackgroundHover: Appearance.colors.colLayer2Hover
    Behavior on colBackground {
        animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
    }

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
        // Scan data (band, channel, security, BSSID) exists for every AP; the
        // negotiated rate, real dBm and retry count exist only for the one you
        // are associated to.
        //
        // Laid out in three tiers rather than as one list of eleven rows: the
        // figures you actually look at, the ones you occasionally need, and
        // the ones you need about twice a year. A flat list gave BSSID the
        // same weight as the signal strength.
        ColumnLayout {
            id: detail
            Layout.topMargin: 10
            Layout.fillWidth: true
            visible: root.expanded && !(root.wifiNetwork?.askingPassword ?? false)
            spacing: 8

            // Tier 1 — the headline figures, as tiles.
            component Stat: Rectangle {
                id: stat
                property string label: ""
                property string value: ""
                property string sub: ""
                property color accent: Appearance.colors.colOnLayer1
                visible: value.length > 0
                Layout.fillWidth: true
                implicitHeight: 52
                radius: Appearance.rounding.small
                color: Appearance.colors.colLayer1
                ColumnLayout {
                    anchors.centerIn: parent
                    spacing: -1
                    StyledText {
                        Layout.alignment: Qt.AlignHCenter
                        text: stat.value
                        font.pixelSize: Appearance.font.pixelSize.normal
                        font.family: Appearance.font.family.monospace
                        color: stat.accent
                    }
                    StyledText {
                        Layout.alignment: Qt.AlignHCenter
                        text: stat.label
                        font.pixelSize: Appearance.font.pixelSize.smallest
                        color: Appearance.colors.colSubtext
                    }
                }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 6

                Stat {
                    label: Translation.tr("Signal")
                    value: root.strength > 0 ? root.strength + "%" : ""
                    // Colour only where it means something: a weak signal is
                    // the thing you opened this panel to find.
                    accent: root.strength >= 60 ? Appearance.colors.colOnLayer1
                          : root.strength >= 35 ? Appearance.colors.colOnLayer1
                          : Appearance.m3colors.m3error
                }
                Stat {
                    label: Translation.tr("Band")
                    value: {
                        const f = root.wifiNetwork?.frequency ?? 0;
                        return f ? Network.bandFor(f) : "";
                    }
                }
                Stat {
                    label: Translation.tr("Link")
                    value: root.isActive && Network.linkInfo.tx
                         ? Network.linkInfo.tx + "M" : ""
                }
            }

            // Tier 2 — the rest of what you read at a glance.
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
                    color: Appearance.colors.colOnLayer1
                    elide: Text.ElideRight
                }
            }

            DetailRow {
                k: Translation.tr("Security")
                v: (root.wifiNetwork?.security ?? "").trim().length > 0
                   ? root.wifiNetwork.security : Translation.tr("Open")
            }
            DetailRow {
                k: Translation.tr("IP address")
                v: root.isActive ? (Network.linkInfo.ip ?? "") : ""
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

            // Tier 3 — behind a toggle. Nobody reads a BSSID by accident.
            property bool technicalOpen: false

            Item {
                id: technicalHeader
                Layout.fillWidth: true
                Layout.topMargin: 2
                implicitHeight: 18

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: detail.technicalOpen = !detail.technicalOpen
                }
                RowLayout {
                    anchors.fill: parent
                    spacing: 6
                    StyledText {
                        text: Translation.tr("Technical")
                        font.pixelSize: Appearance.font.pixelSize.smallest
                        color: Appearance.colors.colSubtext
                    }
                    Rectangle {
                        Layout.fillWidth: true
                        implicitHeight: 1
                        color: Appearance.colors.colLayer0Border
                    }
                    MaterialSymbol {
                        text: detail.technicalOpen ? "expand_less" : "expand_more"
                        iconSize: 16
                        color: Appearance.colors.colSubtext
                    }
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                visible: detail.technicalOpen
                spacing: 3

                DetailRow {
                    k: Translation.tr("Channel")
                    v: {
                        const f = root.wifiNetwork?.frequency ?? 0;
                        if (!f) return "";
                        return Network.channelFor(f) + "  •  " + f + " MHz";
                    }
                }
                DetailRow {
                    k: Translation.tr("Actual signal")
                    v: root.isActive && Network.linkInfo.dbm
                       ? Network.linkInfo.dbm + " dBm"
                       : (root.strength > 0 ? "≈ " + Network.approxDbm(root.strength) + " dBm" : "")
                }
                DetailRow {
                    k: Translation.tr("Link rate")
                    v: root.isActive && Network.linkInfo.tx
                       ? Network.linkInfo.tx + " / " + (Network.linkInfo.rx ?? "?") + " Mbit/s" : ""
                }
                DetailRow {
                    // A climbing retry count against a strong signal is the tell
                    // for a congested channel or a repeater hop — the failure
                    // this whole panel exists to make visible.
                    k: Translation.tr("TX retries / failed")
                    v: root.isActive && Network.linkInfo.retries
                       ? Network.linkInfo.retries + " / " + (Network.linkInfo.failed ?? "0") : ""
                }
                DetailRow {
                    k: Translation.tr("Gateway")
                    v: root.isActive ? (Network.linkInfo.gw ?? "") : ""
                }
                DetailRow {
                    k: "BSSID"
                    v: root.wifiNetwork?.bssid ?? ""
                }
                DetailRow {
                    k: Translation.tr("Priority")
                    v: root.isSaved ? String(Network.priorityOf(root.ssid)) : ""
                }
            }
        }

        // ── Saved-profile controls ──────────────────────────────────────
        ColumnLayout {
            Layout.topMargin: 6
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

            RowLayout {
                Layout.fillWidth: true
                Layout.topMargin: 2
                spacing: 6
                StyledText {
                    text: Translation.tr("Band")
                    font.pixelSize: Appearance.font.pixelSize.smallest
                    color: Appearance.colors.colSubtext
                }
                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: 1
                    color: Appearance.colors.colLayer0Border
                }
            }
            // Locking the band is the direct fix when one SSID is served by
            // both a fast 5GHz radio and a slow 2.4GHz one and the adapter
            // keeps picking the wrong one.
            //
            // One shared track, like the sort control above: three fixed
            // choices sized to the panel rather than to their own labels.
            RowLayout {
                Layout.fillWidth: true
                spacing: 4
                Repeater {
                    model: [
                        { label: Translation.tr("Auto"), value: "" },
                        { label: "5 GHz",  value: "a"  },
                        { label: "2.4 GHz", value: "bg" }
                    ]
                    delegate: DialogButton {
                        required property var modelData
                        readonly property bool sel: Network.bandLockOf(root.ssid) === modelData.value
                        Layout.fillWidth: true
                        buttonText: modelData.label
                        colBackground: sel ? Appearance.colors.colPrimary
                                           : Appearance.colors.colLayer1
                        colText: sel ? Appearance.colors.colOnPrimary
                                     : Appearance.colors.colOnLayer1
                        onClicked: Network.setBandLock(root.ssid, modelData.value)
                    }
                }
            }
        }

        // Action row — Connect / Disconnect / Forget. Mirrors bluetooth.
        RowLayout {
            visible: root.expanded
                  && !(root.wifiNetwork?.askingPassword ?? false)
            Layout.topMargin: 10
            Layout.fillWidth: true
            spacing: 6

            // Sets connection.autoconnect-priority, which NetworkManager itself
            // acts on when several known networks are in range — so the choice
            // survives reboots and applies even when this shell is not running.
            PrimaryActionButton {
                Layout.fillWidth: true
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
                Layout.fillWidth: true
                visible: !root.isActive
                loading: root.isConnecting
                enabled: !root.isConnecting
                buttonText: root.isConnecting ? Translation.tr("Connecting…") : Translation.tr("Connect")
                onClicked: Network.connectToWifiNetwork(root.wifiNetwork)
            }
            // Tonal, not filled: on the network you are already using, the
            // loudest button on screen should not be the one that drops it.
            PrimaryActionButton {
                Layout.fillWidth: true
                visible: root.isActive
                buttonText: Translation.tr("Disconnect")
                colBackground: Appearance.colors.colLayer1
                colText: Appearance.colors.colOnLayer1
                onClicked: Network.disconnectWifiNetwork()
            }
            PrimaryActionButton {
                // "Forget" deletes the saved nmcli connection. Only meaningful
                // for known networks; we approximate "known" as secure
                // networks the user has connected to before. nmcli will no-op
                // for unknown SSIDs.
                // Only offered for networks actually saved — nmcli no-ops on
                // an SSID it does not know, so the old `isSecure` test put a
                // red button on every locked network in the list whether or
                // not it could do anything.
                Layout.fillWidth: true
                visible: root.isSaved
                // Outlined rather than filled: it is destructive, so it must
                // read as different, but a solid red block next to a solid
                // primary block makes the panel look like a warning.
                colBackground: Appearance.colors.colLayer1
                colBackgroundHover: ColorUtils.transparentize(Appearance.colors.colError, 0.8)
                colRipple: Appearance.colors.colErrorActive
                colText: Appearance.colors.colError

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
