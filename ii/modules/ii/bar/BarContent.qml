import qs.modules.ii.bar.weather
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Services.UPower
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import Quickshell.Io

Item { // Bar content region
    id: root

    property var screen: root.QsWindow.window?.screen
    property var brightnessMonitor: Brightness.getMonitorForScreen(screen)
    property real useShortenedForm: (Appearance.sizes.barHellaShortenScreenWidthThreshold >= screen?.width) ? 2 : (Appearance.sizes.barShortenScreenWidthThreshold >= screen?.width) ? 1 : 0
    readonly property int centerSideModuleWidth: (useShortenedForm == 2) ? Appearance.sizes.barCenterSideModuleWidthHellaShortened : (useShortenedForm == 1) ? Appearance.sizes.barCenterSideModuleWidthShortened : Appearance.sizes.barCenterSideModuleWidth

    component VerticalBarSeparator: Rectangle {
        implicitWidth: 1
        height: Appearance.sizes.baseBarHeight * 0.4
        anchors.verticalCenter: parent?.verticalCenter
        color: Appearance.colors.colOutlineVariant
    }

    // Background shadow
    Loader {
        active: Config.options.bar.showBackground && Config.options.bar.cornerStyle === 1 && Config.options.bar.floatStyleShadow
        anchors.fill: barBackground
        sourceComponent: StyledRectangularShadow {
            anchors.fill: undefined // The loader's anchors act on this, and this should not have any anchor
            target: barBackground
        }
    }
    // Background
    Rectangle {
        id: barBackground
        anchors {
            fill: parent
            margins: Config.options.bar.cornerStyle === 1 ? (Appearance.sizes.hyprlandGapsOut) : 0 // idk why but +1 is needed
        }
        color: Config.options.bar.showBackground ? Appearance.colors.colLayer0 : "transparent"
        topLeftRadius:     Config.options.bar.cornerStyle === 1 ? Appearance.rounding.windowRounding : 0
        topRightRadius:    Config.options.bar.cornerStyle === 1 ? Appearance.rounding.windowRounding : 0
        bottomLeftRadius:  Config.options.bar.cornerStyle === 1 ? Appearance.rounding.windowRounding : 0
        bottomRightRadius: Config.options.bar.cornerStyle === 1 ? Appearance.rounding.windowRounding : 0
        border.width: Config.options.bar.cornerStyle === 1 ? 1 : 0
        border.color: Appearance.colors.colLayer0Border
    }

    FocusedScrollMouseArea { // Left side | scroll to change brightness
        id: barLeftSideMouseArea

        anchors {
            top: parent.top
            bottom: parent.bottom
            left: parent.left
            right: leftCenterGroup.left
        }
        implicitWidth: leftSectionRowLayout.implicitWidth
        implicitHeight: Appearance.sizes.baseBarHeight

        onScrollDown: root.brightnessMonitor.setBrightness(root.brightnessMonitor.brightness - 0.05)
        onScrollUp: root.brightnessMonitor.setBrightness(root.brightnessMonitor.brightness + 0.05)
        onMovedAway: GlobalStates.osdBrightnessOpen = false
        // Need acceptedButtons explicitly to receive middle-clicks.
        acceptedButtons: Qt.LeftButton | Qt.MiddleButton
        onPressed: event => {
            if (event.button === Qt.LeftButton)
                GlobalStates.sidebarLeftOpen = !GlobalStates.sidebarLeftOpen;
            else if (event.button === Qt.MiddleButton)
                GlobalStates.shelfOpen = !GlobalStates.shelfOpen;
        }

        // Visual content
        ScrollHint {
            reveal: barLeftSideMouseArea.hovered
            icon: "light_mode"
            tooltipText: Translation.tr("Scroll to change brightness")
            side: "left"
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
        }

        RowLayout {
            id: leftSectionRowLayout
            anchors.fill: parent
            spacing: 0

            // The left-sidebar (AI) button used to stand alone here. It now
            // lives inside the ActiveWindow pill, where it grows out of the
            // status dot — see ActiveWindow.qml's leading slot.

            // Morphs between active window title and shelf tab switcher
            Item {
                Layout.leftMargin: Appearance.rounding.screenRounding
                Layout.rightMargin: Appearance.rounding.screenRounding
                Layout.fillWidth: true
                Layout.fillHeight: true
                visible: root.useShortenedForm === 0

                ActiveWindow {
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.left: parent.left
                    // Cap the right edge to where the workspaces' context
                    // starts so we don't overlap. Animate the margin so the
                    // visible title pill grows/shrinks smoothly.
                    anchors.right: parent.right
                    anchors.rightMargin: Math.max(0,
                        (workspacesWidget.ctxTotalW > 0 ? workspacesWidget.ctxTotalW + workspacesWidget.padH : 0))
                    Behavior on anchors.rightMargin {
                        NumberAnimation { duration: 350; easing.type: Easing.InOutCubic }
                    }
                    opacity: GlobalStates.shelfOpen ? 0 : 1
                    visible: opacity > 0
                    Behavior on opacity { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
                }

                // Shelf main tab pills — uses the shared PillTabBar widget.
                PillTabBar {
                    anchors.verticalCenter: parent.verticalCenter
                    height: Appearance.sizes.barIslandHeight
                    opacity: GlobalStates.shelfOpen ? 1 : 0
                    visible: opacity > 0
                    Behavior on opacity { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }

                    tabs: [
                        { id: "files",   icon: "folder_open", label: qsTr("Files")   },
                        { id: "battle",  icon: "graphic_eq",  label: qsTr("Battle")  },
                        { id: "media",   icon: "music_note",  label: qsTr("Media")   },
                    ]
                    current: GlobalStates.shelfTab
                    onTabSelected: id => GlobalStates.shelfTab = id
                }
            }
        }
    }

    // Workspaces island — pills visually centered (offset compensates for
    // asymmetric context/recording sub-sections). While the HUD is open
    // this island swaps the Workspaces widget for a PillTabBar that
    // drives the HUD's tabs, so the HUD itself needs no internal tab row.
    Item {
        id: middleCenterGroup
        anchors {
            top: parent.top
            bottom: parent.bottom
            horizontalCenter: parent.horizontalCenter
            // HUD-tab mode is symmetric — no context/recording offset.
            horizontalCenterOffset: GlobalStates.hudOpen ? 0
                : ((workspacesWidget.ctxTotalW > 0
                    ? workspacesWidget.ctxTotalW + workspacesWidget.padH
                    : 0) - workspacesWidget.recordingExtra) / 2
            Behavior on horizontalCenterOffset {
                NumberAnimation { duration: 350; easing.type: Easing.OutCubic }
            }
        }
        // The HUD tab bar is icon-only → its width is constant, so the
        // island never re-centers and no tab can drift off.
        width: GlobalStates.hudOpen ? hudTabBar.implicitWidth
                                    : workspacesWidget.implicitWidth
        Behavior on width { NumberAnimation { duration: 350; easing.type: Easing.OutCubic } }

        Workspaces {
            id: workspacesWidget
            anchors.verticalCenter: parent.verticalCenter
            visible: !GlobalStates.hudOpen
        }

        // HUD tab selector — only while the HUD is open. Icon-only:
        // five fixed-width icon tabs, names shown as hover tooltips.
        PillTabBar {
            id: hudTabBar
            anchors.verticalCenter: parent.verticalCenter
            anchors.horizontalCenter: parent.horizontalCenter
            iconOnly: true
            visible: GlobalStates.hudOpen
            tabs: [
                { id: "0", icon: "home",    label: "Home"   },
                { id: "1", icon: "tune",    label: "System" },
                { id: "2", icon: "widgets", label: "Hub"    },
            ]
            // Home group now includes the new Essentials page (6).
            current: String((GlobalStates.hudActiveTab === 0 || GlobalStates.hudActiveTab === 5 || GlobalStates.hudActiveTab === 6) ? 0
                           : (GlobalStates.hudActiveTab === 1 || GlobalStates.hudActiveTab === 2) ? 1 : 2)
            onTabSelected: id => GlobalStates.hudActiveTab = [0, 1, 4][parseInt(id)]
        }
    }

    // Time — sibling of middleCenterGroup, anchored to its left edge.
    // Lives outside the workspaces group so its width doesn't pull the
    // workspaces off-center.
    ClockWidget {
        id: barTime
        anchors.right: middleCenterGroup.left
        anchors.rightMargin: 10
        anchors.verticalCenter: middleCenterGroup.verticalCenter
        showTime: true
        showDate: false
    }

    // Resources removed from the bar — the HUD dropdown shows CPU/RAM/GPU.
    // Keep an empty zero-width placeholder so other anchors that referenced
    // leftCenterGroup don't break.
    Item {
        id: leftCenterGroup
        anchors {
            top: parent.top
            bottom: parent.bottom
            right: barTime.left
            rightMargin: 0
        }
        width: 0
        implicitWidth: 0
    }

    // Clock + util island — mirrors leftCenterGroup, right of workspaces
    Row {
        id: rightCenterGroup
        anchors {
            top: parent.top
            bottom: parent.bottom
            left: middleCenterGroup.right
            leftMargin: 4
        }
        spacing: 4
        // Match left group width so workspaces stay visually centered
        width: leftCenterGroup.implicitWidth

        // Right cluster keeps the DATE-only clock + util-island. Time is
        // moved to the left section. Battery moved out of the island —
        // see the right RowLayout (next to bluetooth/wifi).
        ClockWidget {
            anchors.verticalCenter: parent.verticalCenter
            showTime: false
            showDate: (Config.options.bar.verbose && root.useShortenedForm < 2)
        }

        // Util buttons island (hover to expand) — battery removed.
        Item {
            id: utilIsland
            anchors.verticalCenter: parent.verticalCenter
            property bool isHovered: utilHover.hovered
            implicitHeight: utilIslandBg.implicitHeight + 8
            implicitWidth: utilIslandRow.implicitWidth + 12

            Behavior on implicitWidth {
                NumberAnimation { duration: 300; easing.type: Easing.OutCubic }
            }

            HoverHandler { id: utilHover }

            Rectangle {
                id: utilIslandBg
                anchors { fill: parent; topMargin: 4; bottomMargin: 4 }
                radius: Appearance.rounding.full
                color: Appearance.colors.colBarIsland
                border.width: 1
                border.color: Appearance.colors.colBarIslandBorder

                MouseArea {
                    anchors.fill: parent
                    onPressed: GlobalStates.sidebarRightOpen = !GlobalStates.sidebarRightOpen
                }
            }

            Row {
                id: utilIslandRow
                anchors.centerIn: parent
                spacing: 4

                UtilButtons { anchors.verticalCenter: parent.verticalCenter }
            }
        }
    }

    FocusedScrollMouseArea { // Right side | scroll to change volume
        id: barRightSideMouseArea

        anchors {
            top: parent.top
            bottom: parent.bottom
            // `rightCenterGroup` has a CLAMPED width (= leftCenterGroup's
            // width, to keep workspaces centered), so its children — the
            // clock + util island — overflow past `rightCenterGroup.right`.
            // Anchoring to `rightCenterGroup.right` put this scroll
            // MouseArea ON TOP of the util buttons and ate their clicks.
            // `utilIsland` isn't a sibling, so anchor to rightCenterGroup's
            // left edge + a margin = the util island's true right edge.
            left: rightCenterGroup.left
            leftMargin: utilIsland.x + utilIsland.width
            right: parent.right
        }
        implicitWidth: rightSectionRowLayout.implicitWidth
        implicitHeight: Appearance.sizes.baseBarHeight

        onScrollDown: Audio.decrementVolume();
        onScrollUp: Audio.incrementVolume();
        onMovedAway: GlobalStates.osdVolumeOpen = false;
        onPressed: event => {
            if (event.button === Qt.LeftButton) {
                GlobalStates.sidebarRightOpen = !GlobalStates.sidebarRightOpen;
            }
        }

        // Visual content
        ScrollHint {
            reveal: barRightSideMouseArea.hovered
            icon: "volume_up"
            tooltipText: Translation.tr("Scroll to change volume")
            side: "right"
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
        }

        RowLayout {
            id: rightSectionRowLayout
            anchors.fill: parent
            spacing: 5
            layoutDirection: Qt.RightToLeft

            // When the shelf is open with Battle active, swap the right
            // cluster (indicator pill, sys tray, weather) for the Battle
            // sub-tab pills. Single source: `_battleMode`.
            readonly property bool _battleMode: GlobalStates.shelfOpen
                                              && GlobalStates.shelfTab === "battle"
            // Same swap for Files → Torrents: swap the right cluster for
            // the torrent filter pills (All / Downloading / Seeding / …).
            readonly property bool _torrentsMode: GlobalStates.shelfOpen
                                                && GlobalStates.shelfTab === "files"
                                                && GlobalStates.shelfFilesSubTab === "torrents"
            // While the corner popup is open its tab strip is rendered here
            // instead of inside the popup, so the popup reads as one clean
            // surface and the strip sits in space the bar already has.
            readonly property bool _cornerPopupMode: GlobalStates.cornerPopupOpen
            // Any swap-mode hides the standard right cluster.
            readonly property bool _swapMode: _battleMode || _torrentsMode || _cornerPopupMode

            RippleButton { // Right sidebar button
                id: rightSidebarButton
                visible: !rightSectionRowLayout._swapMode

                Layout.alignment: Qt.AlignRight | Qt.AlignVCenter
                Layout.rightMargin: Appearance.rounding.screenRounding
                Layout.fillWidth: false

                implicitWidth: indicatorsRowLayout.implicitWidth + 10 * 2
                implicitHeight: indicatorsRowLayout.implicitHeight + 5 * 2

                buttonRadius: Appearance.rounding.full
                colBackground: barRightSideMouseArea.hovered ? Appearance.colors.colLayer1Hover : ColorUtils.transparentize(Appearance.colors.colLayer1Hover, 1)
                colBackgroundHover: Appearance.colors.colLayer1Hover
                colRipple: Appearance.colors.colLayer1Active
                colBackgroundToggled: Appearance.colors.colSecondaryContainer
                colBackgroundToggledHover: Appearance.colors.colSecondaryContainerHover
                colRippleToggled: Appearance.colors.colSecondaryContainerActive
                toggled: GlobalStates.sidebarRightOpen
                property color colText: toggled ? Appearance.m3colors.m3onSecondaryContainer : Appearance.colors.colOnLayer0

                Behavior on colText {
                    animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
                }

                onPressed: {
                    GlobalStates.sidebarRightOpen = !GlobalStates.sidebarRightOpen;
                }

                RowLayout {
                    id: indicatorsRowLayout
                    anchors.centerIn: parent
                    property real realSpacing: 15
                    spacing: 0

                    Revealer {
                        reveal: Audio.sink?.audio?.muted ?? false
                        Layout.fillHeight: true
                        Layout.rightMargin: reveal ? indicatorsRowLayout.realSpacing : 0
                        Behavior on Layout.rightMargin {
                            animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                        }
                        MaterialSymbol {
                            text: "volume_off"
                            iconSize: Appearance.font.pixelSize.larger
                            color: rightSidebarButton.colText
                        }
                    }
                    // NOTE: the microphone indicator lives further down, next to
                    // the network symbol. There used to be a second one here —
                    // a Revealer on `Audio.source.muted` — so a muted mic drew
                    // TWO crossed-out icons a few slots apart, in two different
                    // colours, saying the same thing. The one below replaces it
                    // outright: it also reports recording, opens the mic panel
                    // when clicked, and carries a tooltip. Don't re-add one here.
                    HyprlandXkbIndicator {
                        Layout.alignment: Qt.AlignVCenter
                        Layout.rightMargin: indicatorsRowLayout.realSpacing
                        color: rightSidebarButton.colText
                    }
                    Revealer {
                        reveal: Notifications.silent || Notifications.unread > 0
                        Layout.fillHeight: true
                        Layout.rightMargin: reveal ? indicatorsRowLayout.realSpacing : 0
                        implicitHeight: reveal ? notificationUnreadCount.implicitHeight : 0
                        implicitWidth: reveal ? notificationUnreadCount.implicitWidth : 0
                        Behavior on Layout.rightMargin {
                            animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                        }
                        NotificationUnreadCount {
                            id: notificationUnreadCount
                        }
                    }
                    /**
                     * Microphone state.
                     *
                     * Shown only when it is worth knowing — muted, or something
                     * is recording — so it costs no space the rest of the time.
                     * Today's whole "bodycam can't hear me" hunt was a mic that
                     * had been muted and turned down to 1.8%, and nothing on
                     * screen said so; a crossed-out icon here would have ended
                     * it in a glance. Red while recording is the same
                     * convention every OS uses for "you are live".
                     */
                    MaterialSymbol {
                        id: micIndicator
                        Layout.rightMargin: visible ? indicatorsRowLayout.realSpacing : 0
                        visible: Mic.muted || Mic.recordingStreams.length > 0
                        text: Mic.muted ? "mic_off" : "mic"
                        iconSize: Appearance.font.pixelSize.larger
                        color: Mic.muted ? Appearance.m3colors.m3error
                             : Mic.recordingStreams.length > 0 ? Appearance.m3colors.m3error
                             : rightSidebarButton.colText
                        TapHandler {
                            gesturePolicy: TapHandler.ReleaseWithinBounds
                            onTapped: GlobalStates.micOpen = !GlobalStates.micOpen
                        }
                        StyledToolTip {
                            text: Mic.muted
                                ? Translation.tr("Microphone muted")
                                : Translation.tr("%1 app(s) recording").arg(Mic.recordingStreams.length)
                        }
                    }
                    MaterialSymbol {
                        text: Network.materialSymbol
                        iconSize: Appearance.font.pixelSize.larger
                        color: rightSidebarButton.colText
                        // Click → open the Wi-Fi popup. Eats the press so
                        // the surrounding RippleButton doesn't toggle the
                        // whole sidebar open/closed too.
                        TapHandler {
                            gesturePolicy: TapHandler.ReleaseWithinBounds
                            onTapped: GlobalStates.openWifiDialogRequest++
                        }
                    }
                    MaterialSymbol {
                        Layout.leftMargin: indicatorsRowLayout.realSpacing
                        visible: BluetoothStatus.available
                        text: BluetoothStatus.connected ? "bluetooth_connected" : BluetoothStatus.enabled ? "bluetooth" : "bluetooth_disabled"
                        iconSize: Appearance.font.pixelSize.larger
                        color: rightSidebarButton.colText
                        TapHandler {
                            gesturePolicy: TapHandler.ReleaseWithinBounds
                            onTapped: GlobalStates.openDevicesDialogRequest++
                        }
                    }
                }
            }

            // Battery — sits OUTSIDE the right-sidebar pill, snugly next
            // to it (just left of the network/bluetooth cluster in RTL flow).
            // Negative right margin closes the row's spacing-induced gap so
            // it doesn't read as a separator.
            // Pluggable widgets; empty by default. Beside the battery because
            // these are readouts, not buttons.
            Repeater {
                model: BarWidgets.enabled
                delegate: BarWidget {
                    required property var modelData
                    widgetId: modelData
                    visible: !rightSectionRowLayout._swapMode
                    Layout.alignment: Qt.AlignVCenter
                    Layout.leftMargin: 4
                    Layout.rightMargin: 4
                }
            }

            BatteryIndicator {
                Layout.alignment: Qt.AlignVCenter
                Layout.leftMargin: 0
                Layout.rightMargin: -rightSectionRowLayout.spacing
                visible: root.useShortenedForm < 2
                       && Battery.available
                       && !rightSectionRowLayout._swapMode
            }

            // Separator dot outside the SysTray's dark background capsule
            StyledText {
                id: traySeparator
                Layout.alignment: Qt.AlignVCenter
                font.pixelSize: Appearance.font.pixelSize.larger
                color: Appearance.colors.colSubtext
                text: "•"
                visible: trayInner.implicitWidth > 0 && root.useShortenedForm === 0 && !rightSectionRowLayout._swapMode
            }

            // SysTray + media expand area — recessed darker background
            // gives it a "hole in the bar" look.
            Rectangle {
                visible: root.useShortenedForm === 0 && !rightSectionRowLayout._swapMode
                       && trayInner.implicitWidth > 0
                Layout.fillHeight: false
                Layout.alignment: Qt.AlignVCenter
                Layout.preferredHeight: Appearance.sizes.barIslandHeight
                implicitWidth: trayInner.implicitWidth > 0 ? trayInner.implicitWidth + 14 : 0
                radius: Appearance.rounding.full
                color: Appearance.colors.colBarIsland
                border.width: 1
                border.color: Appearance.colors.colBarIslandBorder

                SysTray {
                    id: trayInner
                    anchors.centerIn: parent
                    Layout.fillWidth: false
                    Layout.fillHeight: true
                    invertSide: Config?.options.bar.bottom
                    showSeparator: false
                }
            }

            // ── Battle sub-tab pills — show on the bar's right side
            //    while shelf is open with Battle active. Sits between
            //    the SysTray and the centered spacer in the RTL layout.
            Row {
                Layout.alignment: Qt.AlignVCenter
                Layout.fillHeight: false
                Layout.rightMargin: Appearance.rounding.screenRounding
                spacing: 4
                opacity: (GlobalStates.shelfOpen && GlobalStates.shelfTab === "battle") ? 1 : 0
                visible: opacity > 0
                Behavior on opacity { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }

                readonly property var subTabs: {
                    const arr = (ShelfPaths.paths ?? []).map((p, i) => ({
                        id: i,
                        label: p.label ?? "Folder",
                        icon:  p.icon  ?? "folder"
                    }))
                    arr.push({ id: -1, label: qsTr("Manage"), icon: "settings" })
                    return arr
                }

                Repeater {
                    model: parent.subTabs
                    delegate: Rectangle {
                        required property var modelData
                        readonly property bool active: GlobalStates.shelfBattleIndex === modelData.id

                        implicitHeight: subRow.implicitHeight + 6
                        implicitWidth:  subRow.implicitWidth  + 14
                        radius: Appearance.rounding.full
                        color: active
                            ? Appearance.colors.colSecondaryContainer
                            : (subHov.hovered ? Appearance.colors.colLayer1Hover : ColorUtils.transparentize(Appearance.colors.colLayer1Hover))
                        Behavior on color { animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this) }

                        HoverHandler { id: subHov }
                        TapHandler { onTapped: GlobalStates.shelfBattleIndex = modelData.id }

                        Row {
                            id: subRow
                            anchors.centerIn: parent
                            spacing: 5
                            MaterialSymbol {
                                anchors.verticalCenter: parent.verticalCenter
                                text: modelData.icon
                                iconSize: Appearance.font.pixelSize.small
                                color: active
                                    ? Appearance.m3colors.m3onSecondaryContainer
                                    : Appearance.colors.colOnLayer0
                            }
                            StyledText {
                                anchors.verticalCenter: parent.verticalCenter
                                text: modelData.label
                                font.pixelSize: Appearance.font.pixelSize.smaller
                                font.weight: active ? Font.Medium : Font.Normal
                                color: active
                                    ? Appearance.m3colors.m3onSecondaryContainer
                                    : Appearance.colors.colOnLayer0
                            }
                        }
                    }
                }
            }

            // ── Corner-popup tabs — shown on the bar's right side while the
            //    corner popup is open, in place of the network/bluetooth
            //    cluster. Same swap pattern as the pills below.
            PillTabBar {
                id: cornerPopupTabs
                Layout.alignment: Qt.AlignVCenter | Qt.AlignRight
                Layout.rightMargin: Appearance.rounding.screenRounding
                implicitHeight: 30
                opacity: rightSectionRowLayout._cornerPopupMode ? 1 : 0
                visible: opacity > 0
                Behavior on opacity { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }

                tabs: [
                    { id: "media",   icon: "music_note",  label: Translation.tr("Media") },
                    { id: "sources", icon: "graphic_eq",  label: Translation.tr("Sources") },
                    { id: "files",   icon: "folder_open", label: Translation.tr("Files") },
                ]
                current: GlobalStates.cornerPopupTab
                onTabSelected: id => GlobalStates.cornerPopupTab = id
            }

            // ── Torrents filter pills — shown on the bar's right side
            //    while shelf is open with Files → Torrents active. Same
            //    pattern as the Battle sub-tab pills above.
            Row {
                id: torrentsPills
                Layout.alignment: Qt.AlignVCenter
                Layout.fillHeight: false
                Layout.rightMargin: Appearance.rounding.screenRounding
                spacing: 4
                opacity: rightSectionRowLayout._torrentsMode ? 1 : 0
                visible: opacity > 0
                Behavior on opacity { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }

                readonly property var filters: [
                    { id: "all",     label: qsTr("All"),         icon: "list" },
                    { id: "active",  label: qsTr("Downloading"), icon: "downloading" },
                    { id: "seeding", label: qsTr("Seeding"),     icon: "swap_vert" },
                    { id: "paused",  label: qsTr("Paused"),      icon: "pause" },
                    { id: "error",   label: qsTr("Issues"),      icon: "error_outline" },
                ]

                function _countFor(id) {
                    if (!Qbt.torrents) return 0
                    if (id === "all") return Qbt.torrents.length
                    let n = 0
                    for (let i = 0; i < Qbt.torrents.length; ++i) {
                        const s = Qbt.torrents[i].state || ""
                        if (id === "active"  && Qbt.isDownloadingState(s)) n++
                        if (id === "seeding" && Qbt.isSeedingState(s))     n++
                        if (id === "paused"  && Qbt.isPausedState(s))      n++
                        if (id === "error"   && Qbt.isErrorState(s))       n++
                    }
                    return n
                }

                Repeater {
                    model: torrentsPills.filters
                    delegate: Rectangle {
                        required property var modelData
                        readonly property bool active: GlobalStates.shelfTorrentsFilter === modelData.id
                        readonly property int count: torrentsPills._countFor(modelData.id)

                        implicitHeight: tRow.implicitHeight + 6
                        implicitWidth:  tRow.implicitWidth  + 14
                        radius: Appearance.rounding.full
                        color: active
                            ? Appearance.colors.colSecondaryContainer
                            : (tHov.hovered ? Appearance.colors.colLayer1Hover : ColorUtils.transparentize(Appearance.colors.colLayer1Hover))
                        Behavior on color { animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this) }

                        HoverHandler { id: tHov }
                        TapHandler { onTapped: GlobalStates.shelfTorrentsFilter = modelData.id }

                        Row {
                            id: tRow
                            anchors.centerIn: parent
                            spacing: 5
                            MaterialSymbol {
                                anchors.verticalCenter: parent.verticalCenter
                                text: modelData.icon
                                iconSize: Appearance.font.pixelSize.small
                                color: active
                                    ? Appearance.m3colors.m3onSecondaryContainer
                                    : Appearance.colors.colOnLayer0
                            }
                            StyledText {
                                anchors.verticalCenter: parent.verticalCenter
                                text: count > 0 ? `${modelData.label} · ${count}` : modelData.label
                                font.pixelSize: Appearance.font.pixelSize.smaller
                                font.weight: active ? Font.Medium : Font.Normal
                                color: active
                                    ? Appearance.m3colors.m3onSecondaryContainer
                                    : Appearance.colors.colOnLayer0
                            }
                        }
                    }
                }
            }

            Item {
                Layout.fillWidth: true
                Layout.fillHeight: true
            }

            // Weather
            Loader {
                Layout.leftMargin: 4
                visible: !rightSectionRowLayout._swapMode
                active: Config.options.bar.weather.enable

                sourceComponent: BarGroup {
                    WeatherBar {}
                }
            }
        }
    }
}
