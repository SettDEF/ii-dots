import qs
import qs.services
import qs.services.network
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import QtQuick
import QtQuick.Layouts
import Quickshell

WindowDialog {
    id: root
    // An expanded entry now carries a full detail block, which alone is taller
    // than the old 600px dialog — so the list had nowhere to scroll to and the
    // expanded content was simply unreachable. Take what the screen allows.
    // Measured against the dialog's own bounds rather than the screen: it is
    // already sized to its host surface, and asking ScreenFit here would mean
    // resolving a window that is null on first load.
    // Sized to the screen, not to the content. Sizing to netList.contentHeight
    // was tried and reverted: an expanded row animates its height, so the
    // list's measurement lags and the dialog shrank around content that was
    // still growing — clipping the buttons out of reach. A little empty space
    // below a short list is the cheaper mistake.
    backgroundHeight: Math.max(400, Math.min(900, root.height - 80))

    // The live link figures shell out to `iw`, so they are only polled while
    // this dialog is on screen — and stop again when it closes.
    Component.onCompleted: {
        Network.detailsVisible = true;
        // rescanWifi() is the ONLY path that runs `nmcli dev wifi list
        // --rescan yes`, and it used to be reachable solely through the rescan
        // button in the header. With that button gone, opening the dialog is
        // what refreshes the list — otherwise you would be looking at whatever
        // NetworkManager last happened to cache, with no way to update it.
        Network.rescanWifi();
    }
    Component.onDestruction: Network.detailsVisible = false

    // ── Filter & order ──────────────────────────────────────────────────
    property bool hideOpen: false
    property bool savedOnly: false
    // "smart" is the default from the service: active first, then preferred,
    // then signal. The others are flat orderings for when you are looking for
    // one specific thing rather than browsing.
    property string sortMode: "smart"

    readonly property var shownNetworks: {
        let list = (Network.friendlyWifiNetworks ?? []).filter(n => {
            if (!n) return false;
            if (root.hideOpen && !(n.isSecure ?? false)) return false;
            if (root.savedOnly && !Network.isSaved(n.ssid)) return false;
            return true;
        });
        if (root.sortMode === "signal")
            list = [...list].sort((a, b) => b.strength - a.strength);
        else if (root.sortMode === "name")
            list = [...list].sort((a, b) => (a.ssid ?? "").localeCompare(b.ssid ?? ""));
        else if (root.sortMode === "band")
            // Highest frequency first, so 5GHz radios group above 2.4GHz ones
            // — the quickest way to see whether an SSID even offers 5GHz.
            list = [...list].sort((a, b) => (b.frequency - a.frequency) || (b.strength - a.strength));
        return list;
    }

    WindowDialogTitle {
        text: Translation.tr("Connect to Wi-Fi")
    }

    // No text filter here: the header stays a plain title. The Saved / Secured
    // chips and the sort modes below already narrow the list, without a field
    // competing with the title for the row.
    WindowDialogSeparator {
        visible: !Network.wifiScanning
    }
    StyledIndeterminateProgressBar {
        visible: Network.wifiScanning
        Layout.fillWidth: true
        Layout.topMargin: -8
        Layout.bottomMargin: -8
        Layout.leftMargin: -Appearance.rounding.large
        Layout.rightMargin: -Appearance.rounding.large
    }
    // ── Sort and filter, one row ────────────────────────────────────────
    // Six pills across two rows was more chrome than the whole dialog. The
    // sort is one continuous segmented track; the two filters are icon
    // toggles beside it, which is what they are — a bookmark and a padlock
    // say "saved" and "secured" without spending a third of the width on
    // the words.
    RowLayout {
        Layout.fillWidth: true
        Layout.topMargin: 6
        spacing: 6

        // The segments sit inside one container so they read as a single
        // control rather than four separate buttons that happen to touch.
        Rectangle {
            Layout.fillWidth: true
            implicitHeight: 32
            radius: Appearance.rounding.full
            color: Appearance.colors.colLayer2

            RowLayout {
                anchors { fill: parent; margins: 3 }
                spacing: 2

                Repeater {
                    model: [
                        { label: Translation.tr("Smart"),  value: "smart"  },
                        { label: Translation.tr("Signal"), value: "signal" },
                        { label: Translation.tr("Name"),   value: "name"   },
                        { label: Translation.tr("Band"),   value: "band"   }
                    ]
                    delegate: Rectangle {
                        required property var modelData
                        readonly property bool sel: root.sortMode === modelData.value
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        radius: Appearance.rounding.full
                        color: sel ? Appearance.colors.colPrimary
                             : segHover.hovered ? Appearance.colors.colLayer2Hover
                             : "transparent"
                        Behavior on color {
                            animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
                        }
                        HoverHandler { id: segHover; cursorShape: Qt.PointingHandCursor }
                        TapHandler { onTapped: root.sortMode = modelData.value }
                        StyledText {
                            anchors.centerIn: parent
                            text: modelData.label
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            color: parent.sel ? Appearance.colors.colOnPrimary
                                              : Appearance.colors.colOnLayer2
                        }
                    }
                }
            }
        }

        component FilterToggle: Rectangle {
            property string icon: ""
            property bool on: false
            signal picked
            implicitWidth: 32
            implicitHeight: 32
            radius: Appearance.rounding.full
            color: on ? Appearance.colors.colPrimary
                 : tHover.hovered ? Appearance.colors.colLayer2Hover
                 : Appearance.colors.colLayer2
            Behavior on color {
                animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
            }
            HoverHandler { id: tHover; cursorShape: Qt.PointingHandCursor }
            TapHandler { onTapped: picked() }
            MaterialSymbol {
                anchors.centerIn: parent
                text: parent.icon
                iconSize: 18
                fill: parent.on ? 1 : 0
                color: parent.on ? Appearance.colors.colOnPrimary
                                 : Appearance.colors.colOnLayer2
            }
        }

        FilterToggle {
            icon: "bookmark"
            on: root.savedOnly
            onPicked: root.savedOnly = !root.savedOnly
            StyledToolTip { text: Translation.tr("Only networks you have connected to before") }
        }
        FilterToggle {
            icon: "lock"
            on: root.hideOpen
            onPicked: root.hideOpen = !root.hideOpen
            StyledToolTip { text: Translation.tr("Hide open (unencrypted) networks") }
        }
    }

        ColumnLayout {
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignHCenter
            visible: root.shownNetworks.length === 0
            spacing: 6
            Layout.topMargin: 12
            Layout.bottomMargin: 12

            MaterialSymbol {
                Layout.alignment: Qt.AlignHCenter
                // No spinner here. StyledIndeterminateProgressBar above already
                // animates for the whole scan, and two moving things for one
                // operation read as two separate operations. The rest of the
                // state is carried by the colour and by the text below, which
                // already says "Scanning for networks…".
                //
                // `progress_activity` went with the animation rather than being
                // left static — it is a spinner face, and a spinner that does not
                // turn looks like it has hung.
                text: Network.wifiScanning ? "wifi" : "wifi_off"
                iconSize: 28
                color: Network.wifiScanning ? Appearance.colors.colPrimary : Appearance.colors.colSubtext
            }

            StyledText {
                Layout.alignment: Qt.AlignHCenter
                text: Network.wifiScanning
                      ? Translation.tr("Scanning for networks…")
                      : Translation.tr("No networks match filter")
                font.pixelSize: Appearance.font.pixelSize.small
                font.weight: Font.Medium
                color: Appearance.colors.colOnLayer1
            }

            StyledText {
                Layout.alignment: Qt.AlignHCenter
                text: Network.wifiScanning
                      ? Translation.tr("Please wait while nearby access points are discovered")
                      : Translation.tr("Try clearing the Saved / Secured filters, or reopen this dialog to scan again")
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: Appearance.colors.colSubtext
            }
        }

    StyledListView {
        id: netList
        Layout.fillHeight: true
        Layout.fillWidth: true
        Layout.topMargin: -15
        Layout.bottomMargin: -16
        Layout.leftMargin: -Appearance.rounding.large
        Layout.rightMargin: -Appearance.rounding.large

        clip: true
        // The rows are surfaces now, so they need a gap or they fuse into one
        // block and the containment is wasted.
        spacing: 5
        animateAppearance: false

        model: ScriptModel {
            values: root.shownNetworks
        }
        delegate: WifiNetworkItem {
            required property WifiAccessPoint modelData
            required property int index
            wifiNetwork: modelData
            anchors {
                left: parent?.left
                right: parent?.right
            }
            // An expanded entry can be taller than the viewport, and it grows
            // downward from wherever it happens to sit — so without this the
            // detail block opens off the bottom edge with no obvious way to
            // reach it. Wait for the expand animation to finish, otherwise the
            // list scrolls to the height the row had before it grew.
            onExpandedChanged: if (expanded) scrollIntoView.restart()
            Timer {
                id: scrollIntoView
                interval: Appearance.animation.elementMove.numberAnimation.duration + 40
                onTriggered: netList.positionViewAtIndex(index, ListView.Contain)
            }
        }
    }
    WindowDialogSeparator {}
    WindowDialogButtonRow {
        DialogButton {
            buttonText: Translation.tr("Details")
            onClicked: {
                Quickshell.execDetached(["bash", "-c", `${Network.ethernet ? Config.options.apps.networkEthernet : Config.options.apps.network}`]);
                GlobalStates.sidebarRightOpen = false;
            }
        }

        Item {
            Layout.fillWidth: true
        }

        DialogButton {
            buttonText: Translation.tr("Done")
            onClicked: root.dismiss()
        }
    }
}