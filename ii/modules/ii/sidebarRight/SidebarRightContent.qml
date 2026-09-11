import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Bluetooth
import Quickshell.Hyprland

import qs.modules.ii.sidebarRight.quickToggles
import qs.modules.ii.sidebarRight.quickToggles.classicStyle
import qs.modules.ii.sidebarRight.quickToggles.androidStyle

import qs.modules.ii.sidebarRight.bluetoothDevices
import qs.modules.ii.sidebarRight.nightLight
import qs.modules.ii.sidebarRight.volumeMixer
import qs.modules.ii.sidebarRight.wifiNetworks
import qs.modules.ii.sidebarRight.kdeConnect
import qs.modules.ii.sidebarRight.monitors
import qs.modules.ii.sidebarRight.rss
import qs.modules.ii.cornerPopup

Item {
    id: root
    property int sidebarWidth: Appearance.sizes.sidebarWidth
    property int sidebarPadding: 10
    property string settingsQmlPath: Quickshell.shellPath("settings.qml")
    property bool showAudioOutputDialog: false
    property bool showAudioInputDialog: false
    property bool showBluetoothDialog: false
    property bool showNightLightDialog: false
    property bool showWifiDialog: false
    property bool showKdeConnectDialog: false
    property bool showMonitorsDialog: false
    property bool showRssDialog: false
    property bool editMode: false
    property int topTab: 0
    // Number of user-customizable tabs (read from Config). All tabs are now generic.
    readonly property int userTabsCount: Config.ready
        ? Math.max(1, Config.options.sidebar.quickToggles.android.tabs?.length ?? 1)
        : 1

    Connections {
        target: GlobalStates
        function onSidebarRightOpenChanged() {
            if (!GlobalStates.sidebarRightOpen) {
                root.showWifiDialog = false;
                root.showBluetoothDialog = false;
                root.showAudioOutputDialog = false;
                root.showAudioInputDialog = false;
                root.showKdeConnectDialog = false;
                root.showMonitorsDialog = false;
                root.showRssDialog = false;
            }
        }
        // Cross-module open requests from the bar's Wi-Fi / Bluetooth icons.
        // Each is an int-counter that increments → treat any change as a
        // request. Ensures the sidebar is open so the dialog has a host.
        function onOpenWifiDialogRequestChanged() {
            GlobalStates.sidebarRightOpen = true
            root.showWifiDialog = true
        }
        function onOpenBluetoothDialogRequestChanged() {
            GlobalStates.sidebarRightOpen = true
            root.showBluetoothDialog = true
        }
    }

    implicitHeight: sidebarRightBackground.implicitHeight
    implicitWidth: sidebarRightBackground.implicitWidth

    StyledRectangularShadow {
        target: sidebarRightBackground
    }
    Rectangle {
        id: sidebarRightBackground

        anchors.fill: parent
        implicitHeight: parent.height - Appearance.sizes.hyprlandGapsOut * 2
        implicitWidth: sidebarWidth - Appearance.sizes.hyprlandGapsOut * 2
        color: Appearance.colors.colLayer0
        border.width: 1
        border.color: Appearance.colors.colLayer0Border
        radius: Appearance.rounding.screenRounding - Appearance.sizes.hyprlandGapsOut + 1

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: sidebarPadding
            spacing: sidebarPadding

            SystemButtonRow {
                Layout.fillHeight: false
                Layout.fillWidth: true
                // Layout.margins: 10
                Layout.topMargin: 5
                Layout.bottomMargin: 0
            }

            // ── Top widget area with scripted scroll + right dots ─────────
            Item {
                id: topWidgetArea
                Layout.fillWidth: true

                readonly property int tabCount: root.userTabsCount
                // Updated by whichever delegate matches root.topTab.
                property real activeTabHeight: 0

                implicitHeight: activeTabHeight > 0 ? activeTabHeight : 60
                Behavior on implicitHeight {
                    NumberAnimation {
                        duration: Appearance.animation.elementMove.duration
                        easing.type: Appearance.animation.elementMove.type
                        easing.bezierCurve: Appearance.animation.elementMove.bezierCurve
                    }
                }

                property bool scrollCooldown: false

                function goTo(idx) {
                    const next = Math.max(0, Math.min(idx, tabCount - 1))
                    if (next === root.topTab || scrollCooldown) return
                    root.topTab = next
                    scrollCooldown = true
                    cooldownTimer.restart()
                }

                Timer {
                    id: cooldownTimer
                    interval: 600
                    repeat: false
                    onTriggered: topWidgetArea.scrollCooldown = false
                }

                // Scroll to change tab (mouse / touchpad)
                //
                // Off in edit mode. This handler covers the whole toggle area,
                // and edit mode puts a scrollable tile tray inside that area —
                // so a wheel meant for the tray was flipping the tab instead,
                // which reads as "scrolling is broken" rather than as a binding
                // doing its job. Tab dots still switch tabs while editing.
                WheelHandler {
                    enabled: !root.editMode
                    target: null
                    acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
                    onWheel: event => {
                        if (event.angleDelta.y < 0) topWidgetArea.goTo(root.topTab + 1)
                        else                        topWidgetArea.goTo(root.topTab - 1)
                    }
                }

                // Finger / stylus horizontal swipe to change tab.
                // Tap handlers on the toggles only see press/release, not
                // drags, so this doesn't interfere with normal tile taps.
                DragHandler {
                    acceptedDevices: PointerDevice.TouchScreen | PointerDevice.Stylus
                    target: null
                    xAxis.enabled: true
                    yAxis.enabled: false
                    property real startX: 0
                    onActiveChanged: {
                        if (active) {
                            startX = centroid.position.x
                        } else {
                            const dx = centroid.position.x - startX
                            if (Math.abs(dx) > 60) {
                                if (dx < 0) topWidgetArea.goTo(root.topTab + 1)
                                else        topWidgetArea.goTo(root.topTab - 1)
                            }
                        }
                    }
                }

                // Clipped sliding viewport
                Item {
                    id: viewport
                    anchors { left: parent.left; right: tabDots.left; rightMargin: 6 }
                    implicitHeight: topWidgetArea.implicitHeight
                    height: implicitHeight
                    clip: true

                    // Sliding strip — all tabs side by side
                    Item {
                        id: strip
                        width: viewport.width * topWidgetArea.tabCount
                        height: parent.height
                        x: -root.topTab * viewport.width
                        Behavior on x {
                            NumberAnimation {
                                duration: Appearance.animation.elementMove.duration
                                easing.type: Appearance.animation.elementMove.type
                                easing.bezierCurve: Appearance.animation.elementMove.bezierCurve
                            }
                        }

                        // User-customizable tabs — each holds tile widgets and panel widgets.
                        Repeater {
                            id: userTabsRepeater
                            model: root.userTabsCount
                            delegate: ColumnLayout {
                                id: userTabContent
                                required property int index
                                x: index * viewport.width
                                width: viewport.width
                                spacing: root.sidebarPadding

                                readonly property bool isActiveTab: index === root.topTab
                                onImplicitHeightChanged: if (isActiveTab) topWidgetArea.activeTabHeight = implicitHeight
                                onIsActiveTabChanged:    if (isActiveTab) topWidgetArea.activeTabHeight = implicitHeight
                                Component.onCompleted:   if (isActiveTab) topWidgetArea.activeTabHeight = implicitHeight

                                // The current tab's items list (panel filter)
                                readonly property var tabItems: {
                                    if (!Config.ready) return []
                                    const tabs = Config.options.sidebar.quickToggles.android.tabs
                                    return tabs?.[userTabContent.index]?.toggles ?? []
                                }
                                // Panel widgets migrated into the toggle grid as tile widgets.
                                // Empty set => the panel rendering Repeater below produces nothing.
                                readonly property var panelTypesSet: ({})

                                // Tile grid (Android quicktoggles)
                                LoaderedQuickPanelImplementation {
                                    styleName: "classic"
                                    visible: userTabContent.index === 0 && active
                                    active: userTabContent.index === 0 && Config.options.sidebar.quickToggles.style === "classic"
                                    sourceComponent: ClassicQuickPanel {}
                                }
                                LoaderedQuickPanelImplementation {
                                    styleName: "android"
                                    sourceComponent: AndroidQuickPanel {
                                        editMode: root.editMode
                                        tabIndex: userTabContent.index
                                    }
                                }

                                // Panel widgets (full-width). Each entry in items with a panel-type renders here.
                                Repeater {
                                    model: ScriptModel {
                                        values: userTabContent.tabItems.filter(t => t && userTabContent.panelTypesSet[t.type])
                                    }
                                    delegate: Item {
                                        id: panelHost
                                        required property var modelData
                                        required property int index
                                        Layout.fillWidth: true
                                        // In edit mode show the dropdown shell; otherwise the actual panel.
                                        implicitHeight: root.editMode
                                            ? editShell.implicitHeight
                                            : (panelLoader.item ? panelLoader.item.implicitHeight : 0)

                                        readonly property var labelMap: ({
                                            "sliders":          { name: "Sliders",   icon: "tune" },
                                            "bluetoothDevices": { name: "Bluetooth", icon: "devices_other" },
                                            "midi":             { name: "MIDI",      icon: "piano" },
                                            "rog":              { name: "ROG",       icon: "memory" },
                                            "phone":            { name: "Phone",     icon: "smartphone" },
                                        })
                                        readonly property var info: labelMap[modelData.type] ?? { name: modelData.type, icon: "widgets" }

                                        // The N-th occurrence index in the tab's items array (used for writing children back).
                                        function nthIndexInTab() {
                                            const list = userTabContent.tabItems
                                            const t = panelHost.modelData.type
                                            let seen = 0
                                            for (let i = 0; i < list.length; i++) {
                                                if (list[i] && list[i].type === t) {
                                                    if (seen === panelHost.index) return i
                                                    seen++
                                                }
                                            }
                                            return -1
                                        }

                                        // ── View mode: render actual panel content ──
                                        Loader {
                                            id: panelLoader
                                            visible: !root.editMode
                                            anchors.fill: parent
                                            sourceComponent: switch (panelHost.modelData.type) {
                                                case "sliders":          return slidersComp
                                                case "bluetoothDevices": return btComp
                                                case "midi":             return midiComp
                                                case "rog":              return rogComp
                                                case "phone":            return phoneComp
                                                default:                 return null
                                            }
                                        }

                                        // ── Edit mode: dropdown shell with header + collapsible body ──
                                        ColumnLayout {
                                            id: editShell
                                            visible: root.editMode
                                            anchors { left: parent.left; right: parent.right; top: parent.top }
                                            spacing: 4

                                            property bool open: false

                                            // Header row: styled like a grid tile (colLayer2 / pill / 56px).
                                            Item {
                                                Layout.fillWidth: true
                                                implicitHeight: 56

                                                Rectangle {
                                                    id: hdrTile
                                                    anchors.fill: parent
                                                    radius: editShell.open ? Appearance.rounding.large : height / 2
                                                    Behavior on radius { animation: Appearance.animation.elementMove.numberAnimation.createObject(this) }
                                                    color: hdrHov.hovered ? Appearance.colors.colLayer2Hover : Appearance.colors.colLayer2
                                                    Behavior on color { animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this) }
                                                    HoverHandler { id: hdrHov }
                                                    TapHandler { onTapped: editShell.open = !editShell.open }

                                                    RowLayout {
                                                        anchors { fill: parent; leftMargin: 12; rightMargin: 14 }
                                                        spacing: 10
                                                        // Icon block — mirrors the small-toggle tile's icon BG
                                                        Rectangle {
                                                            Layout.alignment: Qt.AlignVCenter
                                                            Layout.preferredWidth: 44
                                                            Layout.preferredHeight: 44
                                                            radius: editShell.open ? Appearance.rounding.normal : 22
                                                            Behavior on radius { animation: Appearance.animation.elementMove.numberAnimation.createObject(this) }
                                                            color: Appearance.colors.colLayer3
                                                            MaterialSymbol {
                                                                anchors.centerIn: parent
                                                                text: panelHost.info.icon; iconSize: 22
                                                                color: Appearance.colors.colOnLayer3
                                                            }
                                                        }
                                                        ColumnLayout {
                                                            Layout.alignment: Qt.AlignVCenter
                                                            Layout.fillWidth: true
                                                            spacing: -2
                                                            StyledText {
                                                                text: panelHost.info.name
                                                                font.pixelSize: Appearance.font.pixelSize.smallie
                                                                font.weight: Font.DemiBold
                                                                color: Appearance.colors.colOnLayer2
                                                                elide: Text.ElideRight
                                                            }
                                                            StyledText {
                                                                text: editShell.open
                                                                    ? Translation.tr("%1 inside").arg((panelHost.modelData.children ?? []).length)
                                                                    : Translation.tr("Tap to expand")
                                                                font.pixelSize: Appearance.font.pixelSize.smaller
                                                                color: Appearance.colors.colSubtext
                                                                elide: Text.ElideRight
                                                            }
                                                        }
                                                        MaterialSymbol {
                                                            Layout.alignment: Qt.AlignVCenter
                                                            text: "expand_more"; iconSize: 18
                                                            color: Appearance.colors.colSubtext
                                                            rotation: editShell.open ? 180 : 0
                                                            Behavior on rotation { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
                                                        }
                                                    }
                                                }

                                                // × overlay — bigger hit area, MouseArea absorbs the click reliably.
                                                Rectangle {
                                                    anchors { top: parent.top; right: parent.right; topMargin: -4; rightMargin: -4 }
                                                    z: 100
                                                    width: 22; height: 22; radius: 11
                                                    color: closeMa.containsMouse ? Appearance.colors.colPrimary : Appearance.colors.colLayer3
                                                    Behavior on color { animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this) }
                                                    MouseArea {
                                                        id: closeMa
                                                        anchors.fill: parent
                                                        anchors.margins: -Appearance.sizes.touchSlop
                                                        hoverEnabled: true
                                                        cursorShape: Qt.PointingHandCursor
                                                        preventStealing: true
                                                        onClicked: {
                                                            const cfg = Config.options.sidebar.quickToggles.android
                                                            const tabs = cfg.tabs.slice()
                                                            const list = (tabs[userTabContent.index].toggles ?? []).slice()
                                                            const idx = panelHost.nthIndexInTab()
                                                            if (idx >= 0) {
                                                                list.splice(idx, 1)
                                                                tabs[userTabContent.index] = Object.assign({}, tabs[userTabContent.index], { toggles: list })
                                                                cfg.tabs = tabs
                                                            }
                                                        }
                                                    }
                                                    MaterialSymbol {
                                                        anchors.centerIn: parent
                                                        text: "close"; iconSize: 14
                                                        horizontalAlignment: Text.AlignHCenter
                                                        verticalAlignment: Text.AlignVCenter
                                                        color: closeMa.containsMouse ? Appearance.colors.colOnPrimary : Appearance.colors.colOnLayer3
                                                    }
                                                }
                                            } // close header wrapper Item

                                            // Collapsible body: nested children tiles + add picker
                                            Item {
                                                Layout.fillWidth: true
                                                clip: true
                                                implicitHeight: editShell.open ? bodyCol.implicitHeight + 8 : 0
                                                opacity: editShell.open ? 1 : 0
                                                Behavior on implicitHeight { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
                                                Behavior on opacity { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }

                                                ColumnLayout {
                                                    id: bodyCol
                                                    anchors { left: parent.left; right: parent.right; top: parent.top; topMargin: 4 }
                                                    spacing: 6

                                                    readonly property var children_: panelHost.modelData.children ?? []

                                                    // Nested toggle tiles (chips)
                                                    Flow {
                                                        Layout.fillWidth: true
                                                        spacing: 6
                                                        Repeater {
                                                            model: ScriptModel {
                                                                values: bodyCol.children_
                                                                objectProp: "type"
                                                            }
                                                            delegate: Rectangle {
                                                                id: nestedChip
                                                                required property var modelData
                                                                required property int index
                                                                implicitWidth: nestedRow.implicitWidth + 18
                                                                implicitHeight: 28
                                                                radius: 14
                                                                color: nestedHov.hovered
                                                                    ? Appearance.m3colors.m3surfaceContainerHighest
                                                                    : Appearance.m3colors.m3surfaceContainer

                                                                // Drag-to-reorder offset
                                                                property real dragX: 0
                                                                property real dragY: 0
                                                                property bool dragging: false
                                                                transform: Translate { x: nestedChip.dragX; y: nestedChip.dragY }
                                                                z: dragging ? 100 : 0
                                                                opacity: dragging ? 0.85 : 1

                                                                HoverHandler { id: nestedHov }
                                                                MouseArea {
                                                                    anchors.fill: parent
                                                                    acceptedButtons: Qt.LeftButton
                                                                    cursorShape: nestedChip.dragging ? Qt.ClosedHandCursor : Qt.OpenHandCursor
                                                                    preventStealing: nestedChip.dragging
                                                                    property real pressX: 0
                                                                    property real pressY: 0
                                                                    property bool dragStarted: false
                                                                    onPressed: (e) => { pressX = e.x; pressY = e.y; dragStarted = false }
                                                                    onPositionChanged: (e) => {
                                                                        if (!(e.buttons & Qt.LeftButton)) return
                                                                        const dx = e.x - pressX, dy = e.y - pressY
                                                                        if (!dragStarted && (Math.abs(dx) > 8 || Math.abs(dy) > 8)) {
                                                                            dragStarted = true
                                                                            nestedChip.dragging = true
                                                                            pressX = e.x; pressY = e.y
                                                                            return
                                                                        }
                                                                        if (dragStarted) { nestedChip.dragX = dx; nestedChip.dragY = dy }
                                                                    }
                                                                    onReleased: (e) => {
                                                                        if (!dragStarted) return
                                                                        // Snap to neighbour based on drag distance: each chip ~ width.
                                                                        const w = nestedChip.width + 6
                                                                        const offset = Math.round(nestedChip.dragX / w)
                                                                        if (offset !== 0) {
                                                                            const cfg = Config.options.sidebar.quickToggles.android
                                                                            const tabs = cfg.tabs.slice()
                                                                            const list = (tabs[userTabContent.index].toggles ?? []).slice()
                                                                            const idx = panelHost.nthIndexInTab()
                                                                            if (idx >= 0) {
                                                                                const ch = (list[idx].children ?? []).slice()
                                                                                const target = Math.max(0, Math.min(ch.length - 1, nestedChip.index + offset))
                                                                                const moved = ch.splice(nestedChip.index, 1)[0]
                                                                                ch.splice(target, 0, moved)
                                                                                list[idx] = Object.assign({}, list[idx], { children: ch })
                                                                                tabs[userTabContent.index] = Object.assign({}, tabs[userTabContent.index], { toggles: list })
                                                                                cfg.tabs = tabs
                                                                            }
                                                                        }
                                                                        nestedChip.dragging = false
                                                                        nestedChip.dragX = 0
                                                                        nestedChip.dragY = 0
                                                                        dragStarted = false
                                                                    }
                                                                    onCanceled: {
                                                                        nestedChip.dragging = false
                                                                        nestedChip.dragX = 0
                                                                        nestedChip.dragY = 0
                                                                        dragStarted = false
                                                                    }
                                                                }
                                                                Row {
                                                                    id: nestedRow
                                                                    anchors.centerIn: parent; spacing: 6
                                                                    MaterialSymbol {
                                                                        anchors.verticalCenter: parent.verticalCenter
                                                                        text: "drag_indicator"; iconSize: 12
                                                                        color: Appearance.colors.colSubtext
                                                                    }
                                                                    StyledText {
                                                                        anchors.verticalCenter: parent.verticalCenter
                                                                        text: parent.parent.modelData.type
                                                                        font.pixelSize: Appearance.font.pixelSize.smaller
                                                                        color: Appearance.m3colors.m3onSurface
                                                                    }
                                                                    Rectangle {
                                                                        anchors.verticalCenter: parent.verticalCenter
                                                                        width: 16; height: 16; radius: 8
                                                                        color: rmHov.hovered ? Appearance.m3colors.m3errorContainer : "transparent"
                                                                        HoverHandler { margin: Appearance.sizes.touchSlop; id: rmHov }
                                                                        TapHandler {
                                                                            margin: Appearance.sizes.touchSlop
                                                                            onTapped: {
                                                                                const cfg = Config.options.sidebar.quickToggles.android
                                                                                const tabs = cfg.tabs.slice()
                                                                                const list = (tabs[userTabContent.index].toggles ?? []).slice()
                                                                                const idx = panelHost.nthIndexInTab()
                                                                                if (idx >= 0) {
                                                                                    const newChildren = (list[idx].children ?? []).slice()
                                                                                    newChildren.splice(parent.parent.parent.index, 1)
                                                                                    list[idx] = Object.assign({}, list[idx], { children: newChildren })
                                                                                    tabs[userTabContent.index] = Object.assign({}, tabs[userTabContent.index], { toggles: list })
                                                                                    cfg.tabs = tabs
                                                                                }
                                                                            }
                                                                        }
                                                                        MaterialSymbol {
                                                                            anchors.centerIn: parent
                                                                            text: "close"; iconSize: 10
                                                                            color: rmHov.hovered ? Appearance.m3colors.m3onErrorContainer : Appearance.colors.colSubtext
                                                                        }
                                                                    }
                                                                }
                                                            }
                                                        }
                                                    }

                                                    // Add inner toggle dropdown
                                                    Item {
                                                        id: addInner
                                                        Layout.fillWidth: true
                                                        property bool open: false
                                                        implicitHeight: addHdr.implicitHeight + (open ? addBody.implicitHeight + 4 : 0)
                                                        Behavior on implicitHeight { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }

                                                        Rectangle {
                                                            id: addHdr
                                                            anchors { left: parent.left; right: parent.right; top: parent.top }
                                                            implicitHeight: 30
                                                            radius: 15
                                                            color: addHdrHov.hovered
                                                                ? Appearance.m3colors.m3surfaceContainerHighest
                                                                : "transparent"
                                                            border.width: 1
                                                            border.color: Appearance.colors.colOutlineVariant
                                                            HoverHandler { id: addHdrHov }
                                                            TapHandler { onTapped: addInner.open = !addInner.open }
                                                            Row {
                                                                anchors.centerIn: parent; spacing: 6
                                                                MaterialSymbol {
                                                                    anchors.verticalCenter: parent.verticalCenter
                                                                    text: "add"; iconSize: 14
                                                                    color: Appearance.m3colors.m3onSurface
                                                                }
                                                                StyledText {
                                                                    anchors.verticalCenter: parent.verticalCenter
                                                                    text: Translation.tr("Add toggle inside")
                                                                    font.pixelSize: Appearance.font.pixelSize.smaller
                                                                    color: Appearance.m3colors.m3onSurface
                                                                }
                                                            }
                                                        }

                                                        Item {
                                                            id: addBody
                                                            anchors { left: parent.left; right: parent.right; top: addHdr.bottom; topMargin: 4 }
                                                            clip: true
                                                            implicitHeight: addInner.open ? innerFlow.implicitHeight : 0
                                                            opacity: addInner.open ? 1 : 0
                                                            Behavior on implicitHeight { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
                                                            Behavior on opacity { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }

                                                            Flow {
                                                                id: innerFlow
                                                                anchors { left: parent.left; right: parent.right; top: parent.top }
                                                                spacing: 4
                                                                Repeater {
                                                                    model: ["network","bluetooth","kdeconnect","mic","audio","nightLight","idleInhibitor","gameMode","darkMode","screenSnip","colorPicker","onScreenKeyboard","notifications","powerProfile","musicRecognition","antiFlashbang","easyEffects","cloudflareWarp"]
                                                                    delegate: Rectangle {
                                                                        required property string modelData
                                                                        implicitWidth: addChipText.implicitWidth + 18
                                                                        implicitHeight: 24
                                                                        radius: 12
                                                                        color: addChipHov.hovered ? Appearance.colors.colPrimary : Appearance.m3colors.m3surfaceContainer
                                                                        Behavior on color { animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this) }
                                                                        HoverHandler { id: addChipHov }
                                                                        TapHandler {
                                                                            onTapped: {
                                                                                const cfg = Config.options.sidebar.quickToggles.android
                                                                                const tabs = cfg.tabs.slice()
                                                                                const list = (tabs[userTabContent.index].toggles ?? []).slice()
                                                                                const idx = panelHost.nthIndexInTab()
                                                                                if (idx >= 0) {
                                                                                    const newChildren = (list[idx].children ?? []).slice()
                                                                                    newChildren.push({ type: modelData, size: 1 })
                                                                                    list[idx] = Object.assign({}, list[idx], { children: newChildren })
                                                                                    tabs[userTabContent.index] = Object.assign({}, tabs[userTabContent.index], { toggles: list })
                                                                                    cfg.tabs = tabs
                                                                                }
                                                                            }
                                                                        }
                                                                        StyledText {
                                                                            id: addChipText
                                                                            anchors.centerIn: parent
                                                                            text: "+ " + modelData
                                                                            font.pixelSize: Appearance.font.pixelSize.smaller
                                                                            color: addChipHov.hovered
                                                                                ? Appearance.colors.colOnPrimary
                                                                                : Appearance.m3colors.m3onSurface
                                                                        }
                                                                    }
                                                                }
                                                            }
                                                        }
                                                    }
                                                }
                                            }
                                        }

                                        Component { id: slidersComp; QuickSliders {} }
                                        Component { id: btComp; BluetoothDevicesView { popupRounding: sidebarRightBackground.radius; isSidebar: true } }
                                        Component { id: midiComp; MidiView { popupRounding: sidebarRightBackground.radius; isSidebar: true } }
                                        Component { id: rogComp; RogView {} }
                                        Component {
                                            id: phoneComp
                                            // Phone widget — single unified surface (matches RogView style).
                                            // Header row at the top, action grid + media card below; no
                                            // visible separator between them.
                                            Rectangle {
                                                implicitHeight: phoneCol.implicitHeight + 12
                                                radius: Appearance.rounding.normal
                                                color: Appearance.colors.colLayer1

                                                ColumnLayout {
                                                    id: phoneCol
                                                    anchors {
                                                        left: parent.left; right: parent.right
                                                        top: parent.top
                                                        leftMargin: 6; rightMargin: 6; topMargin: 6
                                                    }
                                                    spacing: 6

                                                    // Header row — pill that opens the full dialog.
                                                    Rectangle {
                                                        Layout.fillWidth: true
                                                        implicitHeight: 56
                                                        radius: phoneHov.hovered ? Appearance.rounding.large : height / 2
                                                        color: phoneHov.hovered
                                                            ? Appearance.colors.colLayer2Hover
                                                            : Appearance.colors.colLayer2
                                                        Behavior on color  { ColorAnimation { duration: 120 } }
                                                        Behavior on radius { animation: Appearance.animation.elementMove.numberAnimation.createObject(this) }
                                                        HoverHandler { id: phoneHov }
                                                        TapHandler { onTapped: root.showKdeConnectDialog = true }

                                                        RowLayout {
                                                            anchors { fill: parent; leftMargin: 8; rightMargin: 12 }
                                                            spacing: 10
                                                            Rectangle {
                                                                Layout.alignment: Qt.AlignVCenter
                                                                Layout.preferredWidth: 40; Layout.preferredHeight: 40
                                                                radius: 20
                                                                color: KdeConnectService.anyConnected
                                                                    ? Appearance.colors.colPrimary
                                                                    : Appearance.colors.colLayer3
                                                                Behavior on color { ColorAnimation { duration: 120 } }
                                                                MaterialSymbol {
                                                                    anchors.centerIn: parent
                                                                    text: KdeConnectService.anyConnected ? "smartphone" : "phonelink_off"
                                                                    iconSize: 20
                                                                    color: KdeConnectService.anyConnected
                                                                        ? Appearance.colors.colOnPrimary
                                                                        : Appearance.colors.colOnLayer3
                                                                }
                                                            }
                                                            ColumnLayout {
                                                                Layout.fillWidth: true
                                                                spacing: -2
                                                                StyledText {
                                                                    text: KdeConnectService.firstDevice?.name ?? Translation.tr("No phone paired")
                                                                    font.pixelSize: Appearance.font.pixelSize.smallie
                                                                    font.weight: Font.DemiBold
                                                                    elide: Text.ElideRight
                                                                    color: Appearance.colors.colOnLayer1
                                                                }
                                                                StyledText {
                                                                    readonly property var d: KdeConnectService.firstDevice
                                                                    text: d
                                                                        ? (d.reachable
                                                                            ? (d.battery >= 0 ? Translation.tr("Connected · %1%").arg(d.battery) : Translation.tr("Connected"))
                                                                            : Translation.tr("Offline"))
                                                                        : Translation.tr("Open KDE Connect on your phone")
                                                                    font.pixelSize: Appearance.font.pixelSize.smaller
                                                                    elide: Text.ElideRight
                                                                    color: Appearance.colors.colSubtext
                                                                }
                                                            }
                                                            MaterialSymbol {
                                                                Layout.alignment: Qt.AlignVCenter
                                                                text: "open_in_new"; iconSize: 16
                                                                color: Appearance.colors.colSubtext
                                                            }
                                                        }
                                                    }

                                                    KdeConnectActions {
                                                        Layout.fillWidth: true
                                                        device: KdeConnectService.firstDevice
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }

                                // (Add-module dropdown now lives inside AndroidQuickPanel, in the grid.)
                            }
                        }
                    }
                }

                // Right-side vertical dot indicators (with edit-mode controls)
                Column {
                    id: tabDots
                    anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                    // Cap total height to viewport — squeeze spacing down if many tabs.
                    readonly property int slotCount: topWidgetArea.tabCount + (root.editMode ? 1 : 0)
                    readonly property int approxItemH: 14
                    spacing: {
                        const max = viewport.height - slotCount * approxItemH;
                        if (slotCount <= 1) return 6;
                        return Math.max(2, Math.min(6, max / (slotCount - 1)));
                    }

                    Repeater {
                        model: topWidgetArea.tabCount
                        delegate: Item {
                            id: dotItem
                            required property int index
                            readonly property bool isUserTab: true
                            readonly property bool isActive: root.topTab === index
                            readonly property bool dragOver: QuickToggleDragState.active && dotHov.hovered

                            width: root.editMode ? 18 : 12
                            height: isActive ? 22 : 14
                            Behavior on width  { NumberAnimation { duration: 150; easing.type: Easing.OutCubic } }
                            Behavior on height { NumberAnimation { duration: 150; easing.type: Easing.OutCubic } }

                            HoverHandler {
                                id: dotHov
                                onHoveredChanged: {
                                    if (QuickToggleDragState.active) {
                                        if (hovered && dotItem.isUserTab) {
                                            QuickToggleDragState.dropTab = dotItem.index
                                        } else if (!hovered && QuickToggleDragState.dropTab === dotItem.index) {
                                            QuickToggleDragState.dropTab = -2
                                        }
                                    }
                                }
                            }
                            TapHandler { onTapped: root.topTab = dotItem.index }

                            // The pill itself
                            Rectangle {
                                id: dot
                                anchors.centerIn: parent
                                width: dotItem.dragOver ? 10 : 3
                                height: dotItem.isActive
                                    ? 20
                                    : dotItem.dragOver ? 18 : 8
                                radius: width / 2
                                color: dotItem.isActive
                                    ? Appearance.colors.colPrimary
                                    : (dotItem.dragOver ? Appearance.colors.colPrimary
                                                        : (dotHov.hovered ? Appearance.colors.colOnLayer1 : Appearance.colors.colOutlineVariant))
                                Behavior on width  { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }
                                Behavior on height { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }
                                Behavior on color  { animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this) }

                            }

                            // Remove button (× on user tabs in edit mode, when more than one user tab exists)
                            Rectangle {
                                anchors.right: parent.right
                                anchors.top: parent.top
                                anchors.topMargin: -8
                                width: 14; height: 14; radius: 7
                                color: Appearance.colors.colError
                                visible: root.editMode && dotItem.isUserTab && root.userTabsCount > 1 && (dotHov.hovered || Appearance.touchUi)
                                MaterialSymbol {
                                    anchors.centerIn: parent
                                    text: "close"; iconSize: 10
                                    color: Appearance.colors.colOnPrimary
                                }
                                TapHandler {
                                    margin: Appearance.sizes.touchSlop
                                    onTapped: {
                                        const cfg = Config.options.sidebar.quickToggles.android
                                        const tabs = cfg.tabs.slice()
                                        tabs.splice(dotItem.index, 1)
                                        cfg.tabs = tabs
                                        if (root.topTab >= tabs.length) root.topTab = Math.max(0, tabs.length - 1)
                                    }
                                }
                            }
                        }
                    }

                    // Add-tab button (only in edit mode)
                    Rectangle {
                        visible: root.editMode
                        width: 18; height: 18; radius: 9
                        color: addHov.hovered ? Appearance.colors.colPrimaryHover : Appearance.colors.colPrimary
                        Behavior on color { animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this) }
                        HoverHandler { margin: Appearance.sizes.touchSlop; id: addHov }
                        TapHandler {
                            margin: Appearance.sizes.touchSlop
                            onTapped: {
                                const cfg = Config.options.sidebar.quickToggles.android
                                const tabs = (cfg.tabs ?? []).slice()
                                tabs.push({ name: "Tab " + (tabs.length + 1), icon: "tune", toggles: [] })
                                cfg.tabs = tabs
                                root.topTab = tabs.length - 1
                            }
                        }
                        MaterialSymbol {
                            anchors.centerIn: parent
                            text: "add"; iconSize: 14
                            color: Appearance.colors.colOnPrimary
                        }
                    }
                }
            }

            CenterWidgetGroup {
                Layout.alignment: Qt.AlignHCenter
                Layout.fillHeight: true
                Layout.fillWidth: true
            }

            BottomWidgetGroup {
                Layout.alignment: Qt.AlignHCenter
                Layout.fillHeight: false
                Layout.fillWidth: true
                Layout.preferredHeight: implicitHeight
            }
        }
    }

    ToggleDialog {
        shownPropertyString: "showAudioOutputDialog"
        dialog: VolumeDialog {
            isSink: true
        }
    }

    ToggleDialog {
        shownPropertyString: "showAudioInputDialog"
        dialog: VolumeDialog {
            isSink: false
        }
    }

    ToggleDialog {
        shownPropertyString: "showBluetoothDialog"
        dialog: BluetoothDialog {}
        onShownChanged: {
            if (!shown) {
                Bluetooth.defaultAdapter.discovering = false;
            } else {
                Bluetooth.defaultAdapter.enabled = true;
                Bluetooth.defaultAdapter.discovering = true;
            }
        }
    }

    ToggleDialog {
        shownPropertyString: "showNightLightDialog"
        dialog: NightLightDialog {}
    }

    ToggleDialog {
        shownPropertyString: "showWifiDialog"
        dialog: WifiDialog {}
        onShownChanged: {
            if (!shown) return;
            Network.enableWifi();
            Network.rescanWifi();
        }
    }

    ToggleDialog {
        shownPropertyString: "showKdeConnectDialog"
        dialog: KdeConnectDialog {}
        onShownChanged: if (shown) KdeConnectService.refresh()
    }

    ToggleDialog {
        shownPropertyString: "showMonitorsDialog"
        dialog: MonitorsDialog {}
        onShownChanged: if (shown) MonitorManager.refresh()
    }

    ToggleDialog {
        shownPropertyString: "showRssDialog"
        dialog: RssDialog {}
        onShownChanged: if (shown) Rss.refresh()
    }

    component ToggleDialog: Loader {
        id: toggleDialogLoader
        required property string shownPropertyString
        property alias dialog: toggleDialogLoader.sourceComponent
        readonly property bool shown: root[shownPropertyString]
        anchors.fill: parent

        onShownChanged: if (shown) toggleDialogLoader.active = true;
        active: shown
        onActiveChanged: {
            if (active) {
                item.show = true;
                item.forceActiveFocus();
            }
        }
        Connections {
            target: toggleDialogLoader.item
            function onDismiss() {
                toggleDialogLoader.item.show = false
                root[toggleDialogLoader.shownPropertyString] = false;
            }
            function onVisibleChanged() {
                if (!toggleDialogLoader.item.visible && !root[toggleDialogLoader.shownPropertyString]) toggleDialogLoader.active = false;
            }
        }
    }

    component LoaderedQuickPanelImplementation: Loader {
        id: quickPanelImplLoader
        required property string styleName
        Layout.alignment: item?.Layout.alignment ?? Qt.AlignHCenter
        Layout.fillWidth: item?.Layout.fillWidth ?? false
        visible: active
        active: Config.options.sidebar.quickToggles.style === styleName
        Connections {
            target: quickPanelImplLoader.item
            function onOpenAudioOutputDialog() {
                root.showAudioOutputDialog = true;
            }
            function onOpenAudioInputDialog() {
                root.showAudioInputDialog = true;
            }
            function onOpenBluetoothDialog() {
                root.showBluetoothDialog = true;
            }
            function onOpenNightLightDialog() {
                root.showNightLightDialog = true;
            }
            function onOpenWifiDialog() {
                root.showWifiDialog = true;
            }
            function onOpenKdeConnectDialog() {
                root.showKdeConnectDialog = true;
            }
            function onOpenMonitorsDialog() {
                root.showMonitorsDialog = true;
            }
            function onOpenRssDialog() {
                root.showRssDialog = true;
            }
        }
    }

    component SystemButtonRow: Item {
        implicitHeight: Math.max(uptimeContainer.implicitHeight, systemButtonsRow.implicitHeight)

        Rectangle {
            id: uptimeContainer
            anchors {
                top: parent.top
                bottom: parent.bottom
                left: parent.left
            }
            // Tapping it opens the system hub — the index of every settings
            // panel. It was a dead label before, which is a lot of prime
            // sidebar real estate spent on a number.
            color: uptimeHov.hovered ? Appearance.colors.colLayer1Hover
                                     : Appearance.colors.colLayer1
            Behavior on color { ColorAnimation { duration: 140 } }
            radius: height / 2
            implicitWidth: uptimeRow.implicitWidth + 24
            implicitHeight: uptimeRow.implicitHeight + 8

            HoverHandler { id: uptimeHov; cursorShape: Qt.PointingHandCursor }
            TapHandler { onTapped: GlobalStates.systemHubOpen = true }
            StyledToolTip { text: Translation.tr("Open everything — all settings panels") }

            Row {
                id: uptimeRow
                anchors.centerIn: parent
                spacing: 8
                CustomIcon {
                    id: distroIcon
                    anchors.verticalCenter: parent.verticalCenter
                    width: 25
                    height: 25
                    source: SystemInfo.distroIcon
                    colorize: true
                    color: Appearance.colors.colOnLayer0
                }
                StyledText {
                    anchors.verticalCenter: parent.verticalCenter
                    font.pixelSize: Appearance.font.pixelSize.normal
                    color: Appearance.colors.colOnLayer0
                    text: Translation.tr("Up %1").arg(DateTime.uptime)
                    textFormat: Text.MarkdownText
                }
                MaterialSymbol {
                    anchors.verticalCenter: parent.verticalCenter
                    text: "chevron_right"
                    iconSize: 18
                    color: Appearance.colors.colSubtext
                }
            }
        }

        ButtonGroup {
            id: systemButtonsRow
            anchors {
                top: parent.top
                bottom: parent.bottom
                right: parent.right
            }
            color: Appearance.colors.colLayer1
            padding: 4

            QuickToggleButton {
                toggled: root.editMode
                visible: Config.options.sidebar.quickToggles.style === "android"
                buttonIcon: "edit"
                onClicked: root.editMode = !root.editMode
                StyledToolTip {
                    text: Translation.tr("Edit quick toggles") + (root.editMode ? Translation.tr("\nDrag tiles to move within / between tabs\nDrop on a tab dot to switch tab\n× corner to remove\nRMB to resize") : "")
                }
            }
            QuickToggleButton {
                id: autoFillBtn
                readonly property bool show: root.editMode && Config.options.sidebar.quickToggles.style === "android"
                visible: implicitWidth > 1
                toggled: Config.options.sidebar.quickToggles.android.autoFill
                buttonIcon: toggled ? "view_compact" : "view_module"
                baseWidth: show ? 40 : 0
                horizontalPadding: show ? 8 : 0
                opacity: show ? 1 : 0
                clip: true
                Behavior on baseWidth          { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
                Behavior on horizontalPadding  { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
                Behavior on opacity            { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
                onClicked: if (show) Config.options.sidebar.quickToggles.android.autoFill = !Config.options.sidebar.quickToggles.android.autoFill
                StyledToolTip {
                    text: Translation.tr("Toggle auto-fill alignment")
                }
            }
            QuickToggleButton {
                toggled: false
                buttonIcon: "restart_alt"
                onClicked: {
                    HyprDispatch.run("reload");
                    Quickshell.reload(true);
                }
                StyledToolTip {
                    text: Translation.tr("Reload Hyprland & Quickshell")
                }
            }
            QuickToggleButton {
                toggled: false
                buttonIcon: "settings"
                onClicked: {
                    GlobalStates.sidebarRightOpen = false;
                    SettingsApp.open();
                }
                StyledToolTip {
                    text: Translation.tr("Settings")
                }
            }
            QuickToggleButton {
                toggled: false
                buttonIcon: "power_settings_new"
                onClicked: {
                    GlobalStates.sessionOpen = true;
                }
                StyledToolTip {
                    text: Translation.tr("Session")
                }
            }
        }
    }
}
