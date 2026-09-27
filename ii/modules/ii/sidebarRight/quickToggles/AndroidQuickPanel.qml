import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Bluetooth

import qs.modules.ii.sidebarRight.quickToggles.androidStyle

AbstractQuickPanel {
    id: root
    readonly property var quickPanel: root
    property bool editMode: false
    // -1 means "use legacy single list at Config.options.sidebar.quickToggles.android.toggles"
    property int tabIndex: -1
    Layout.fillWidth: true

    // Exiting edit mode mid-drag (sidebar dismissed, panel collapsed, etc.)
    // would leave QuickToggleDragState.active = true forever — the next
    // press on any tile would inherit ghost drag visuals (z-lift, shadow,
    // scale). Force-end the drag whenever edit mode goes away.
    onEditModeChanged: {
        if (!editMode && QuickToggleDragState.active) QuickToggleDragState.end()
    }

    // Sizes
    // Out of edit mode the panel is just usedRows + (optional) container
    // drawer.  In edit mode the full contentItem (incl. tray) drives it.
    // The drawer animates its OWN height (see the Loader below); the
    // panel just sums whatever it currently is.
    readonly property real _drawerH:
        containerDrawer
            ? containerDrawer.height + (containerDrawer.height > 0 ? spacing : 0)
            : 0
    // In edit mode, also include _drawerH so a hold-to-preview drawer
    // (e.g. holding the ROG tile to peek at its children) actually gets
    // vertical space allocated. Without this the OpenContainerState flips
    // and the press-and-hold visual fires, but the drawer renders with
    // 0 effective height behind the edit tray.
    implicitHeight: (editMode
                       ? contentItem.implicitHeight + _drawerH
                       : usedRows.implicitHeight + _drawerH) + root.padding * 2
    Behavior on implicitHeight {
        animation: Appearance.animation.elementMove.numberAnimation.createObject(this)
    }
    property real spacing: 6
    property real padding: 6
    readonly property real baseCellWidth: {
        // This is the wrong calculation, but it looks correct in reality???
        // (theoretically spacing should be multiplied by 1 column less)
        const availableWidth = root.width - (root.padding * 2) - (root.spacing * (root.columns))
        return availableWidth / root.columns
    }
    readonly property real baseCellHeight: 56

    // Tile-style toggle types (rendered in the grid). Sliders/MIDI/ROG/
    // BluetoothDevices/Phone used to be full-width panels below the grid;
    // they're now ordinary tiles that default to a full row (size = columns).
    readonly property list<string> availableToggleTypes: ["network", "vpn", "bluetooth", "idleInhibitor", "sleepTimer", "easyEffects", "nightLight", "darkMode", "cloudflareWarp", "gameMode", "tabletMode", "screenSnip", "colorPicker", "onScreenKeyboard", "mic", "audio", "audioOutput", "notifications", "torrentKeepAlive", "powerProfile","musicRecognition", "antiFlashbang", "monitors", "lastfm", "miniMeters", "mounting", "offload", "rss", "email", "sliders", "devices", "midi", "rog", "phone", "volumeSlider", "brightnessSlider", "micSlider", "rogProfile", "rogGpu", "rogBattery", "rogCharge", "windows"]
    // Panel-only types are gone — kept as empty arrays so the (now inert)
    // panel-rendering code paths stay compile-safe.
    readonly property list<string> availablePanelTypes: []
    readonly property list<string> allWidgetTypes: availableToggleTypes
    readonly property var panelTypesSet: ({})

    // Items split into tiles (toggles list filtered for tile types) and panels.
    readonly property list<var> rawItems: toggles
    readonly property list<var> tileItems: rawItems.filter(t => t && !panelTypesSet[t.type])
    readonly property list<var> panelItems: rawItems.filter(t => t && panelTypesSet[t.type])
    readonly property int columns: Config.options.sidebar.quickToggles.android.columns
    readonly property list<var> toggles: {
        if (!Config.ready) return [];
        const cfg = Config.options.sidebar.quickToggles.android;
        if (root.tabIndex >= 0 && cfg.tabs && cfg.tabs[root.tabIndex])
            return cfg.tabs[root.tabIndex].toggles ?? [];
        return cfg.toggles;
    }
    readonly property list<var> toggleRows: toggleRowsForList(tileItems)
    // Tray shows ALL tile types every time — duplicates are allowed.
    // Toggles whose useful UI only fits in size 2 — they default to 2 when added.
    readonly property list<string> bigByDefault: ["lastfm", "mounting", "offload", "rss"]
    // Slider/ROG atoms need horizontal room — they're useless as 1×1 icons.
    readonly property list<string> wideByDefault: ["volumeSlider", "brightnessSlider", "micSlider",
                                                    "rogProfile", "rogGpu", "rogBattery", "rogCharge"]
    // Full-inline tiles (rich panel content) — default to a full row.
    readonly property list<string> fullRowByDefault: ["devices", "midi", "phone", "mounting"]
    function defaultSizeForType(type) {
        if (fullRowByDefault.includes(type)) return columns
        if (wideByDefault.includes(type)) return Math.max(2, Math.min(3, columns))
        if (bigByDefault.includes(type)) return 2
        return 1
    }

    // Atomic types that only make sense inside their parent container —
    // hide them from the tray so the user picks the container instead.
    // (They stay valid as top-level types when extracted via the
    // container's edit-mode × button.)
    readonly property list<string> hiddenFromTray: [
        "volumeSlider", "brightnessSlider", "micSlider",
        "rogProfile", "rogGpu", "rogBattery", "rogCharge"
    ]
    // Tray always renders compact 1×1 icons, regardless of the type's
    // default size. Tapping/dragging adds them to the user's tab at the
    // correct default size (handled in AndroidQuickToggleButton).
    readonly property list<var> unusedToggles: {
        const q = trayFilter.trim().toLowerCase()
        return availableToggleTypes
            .filter(type => !hiddenFromTray.includes(type))
            .filter(type => q === "" || String(type).toLowerCase().indexOf(q) >= 0)
            .map(type => ({ type: type, size: 1 }))
    }
    readonly property list<var> unusedToggleRows: toggleRowsForList(unusedToggles)

    // ── Tray categorization ─────────────────────────────────────────
    // Group the available-but-unplaced toggles by topic so the tray
    // becomes scannable. Each entry: { id, label, types: [...] }.
    // A toggle that isn't matched falls into "Other".
    readonly property var trayCategories: [
        { id: "connect", label: qsTr("Connect"), types: ["network","vpn","bluetooth","devices","cloudflareWarp","phone"] },
        { id: "audio",   label: qsTr("Audio"),   types: ["audio","mic","volumeSlider","micSlider","easyEffects","lastfm","miniMeters","musicRecognition","midi","sliders"] },
        { id: "display", label: qsTr("Display"), types: ["nightLight","darkMode","antiFlashbang","brightnessSlider","monitors","screenSnip","colorPicker","onScreenKeyboard"] },
        { id: "system",  label: qsTr("System"),  types: ["idleInhibitor","sleepTimer","gameMode","tabletMode","notifications","powerProfile","mounting","offload","email","rss","windows"] },
        { id: "rog",     label: qsTr("ROG"),     types: ["rog","rogProfile","rogGpu","rogBattery","rogCharge"] },
    ]
    readonly property var trayGroups: {
        // Build groups in declared order, then "Other" for orphans.
        const out = []
        const placed = {}
        for (const cat of trayCategories) {
            const tiles = unusedToggles.filter(t => cat.types.includes(t.type))
            for (const t of tiles) placed[t.type] = true
            if (tiles.length > 0) out.push({ id: cat.id, label: cat.label, tiles: tiles })
        }
        const others = unusedToggles.filter(t => !placed[t.type])
        if (others.length > 0) out.push({ id: "other", label: qsTr("Other"), tiles: others })
        return out
    }

    function toggleRowsForList(togglesList) {
        var rows = [];
        var row = [];
        var totalSize = 0; // Total cols taken in current row
        for (var i = 0; i < togglesList.length; i++) {
            const t = togglesList[i];
            if (!t) continue;
            // Skip malformed entries (no type, just stray data).  Saved
            // configs sometimes accumulate these from drag/edit churn —
            // their NaN size blew up totalSize math and prevented row
            // wrapping entirely.
            if (typeof t.type !== "string" || t.type.length === 0) continue;
            // Explicit row break — user added a `{ type: "rowBreak" }`
            // sentinel from the "+ New row" button to force a new row.
            if (t.type === "rowBreak") {
                if (row.length > 0) rows.push(row);
                row = [];
                totalSize = 0;
                continue;
            }
            const rawSize = parseInt(t.size, 10);
            const safeSize = (Number.isFinite(rawSize) && rawSize > 0) ? rawSize : 1;
            const effSize  = safeSize;
            if (totalSize + effSize > columns) {
                rows.push(row);
                row = [];
                totalSize = 0;
            }
            // Annotate each item with its source-cfg index so delegates
            // can splice/move the right entry even when rowBreaks shift
            // visual positions away from cfg.toggles indices.
            row.push(Object.assign({}, togglesList[i], { _cfgIdx: i, size: effSize }));
            totalSize += effSize;
        }
        if (row.length > 0) {
            rows.push(row);
        }
        return rows;
    }

    // Tray search filter — typed into the search field above the unused
    // toggle tray. Matches against the entry's type id (case-insensitive
    // substring). Empty string = no filter.
    property string trayFilter: ""

    Column {
        id: contentItem
        anchors {
            fill: parent
            margins: root.padding
        }
        spacing: 12

        // ── Edit-mode hint banner ────────────────────────────────────
        // Surfaces the otherwise-implicit gestures (drag / right-click /
        // hold) so users discover what edit mode can do.
        FadeLoader {
            shown: root.editMode
            anchors { left: parent?.left; right: parent?.right }
            sourceComponent: Rectangle {
                radius: Appearance.rounding.normal
                color: Appearance.colors.colLayer1Hover
                border.width: 1
                border.color: Appearance.colors.colLayer0Border
                implicitHeight: hintRow.implicitHeight + 14
                Row {
                    id: hintRow
                    anchors.fill: parent
                    anchors.leftMargin: 12
                    anchors.rightMargin: 12
                    anchors.topMargin: 7
                    anchors.bottomMargin: 7
                    spacing: 12
                    component HintChip: Row {
                        spacing: 4
                        property string icon
                        property string label
                        MaterialSymbol {
                            anchors.verticalCenter: parent.verticalCenter
                            text: icon; iconSize: 13
                            color: Appearance.colors.colPrimary
                        }
                        StyledText {
                            anchors.verticalCenter: parent.verticalCenter
                            text: label
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            color: Appearance.colors.colOnLayer1
                        }
                    }
                    HintChip { icon: "drag_indicator"; label: qsTr("drag to move") }
                    HintChip { icon: "mouse";          label: qsTr("right-click to resize") }
                    HintChip { icon: "touch_app";      label: qsTr("hold for drawer") }
                }
            }
        }

        Column {
            id: usedRows
            spacing: root.spacing

            Repeater {
                id: usedRowsRepeater
                model: ScriptModel {
                    values: Array(root.toggleRows.length)
                }
                delegate: ButtonGroup {
                    id: toggleRow
                    required property int index
                    property var modelData: root.toggleRows[index]
                    // First-item cfg index in this row.  Delegates inside
                    // this row use startingIndex + per-cell offset.  When
                    // rowBreak sentinels are present in the source list,
                    // this number jumps to skip them.
                    property int startingIndex:
                        (modelData && modelData[0] && modelData[0]._cfgIdx !== undefined)
                            ? modelData[0]._cfgIdx
                            : (function() {
                                const rows = root.toggleRows;
                                let sum = 0;
                                for (let i = 0; i < index; i++) sum += rows[i].length;
                                return sum;
                              })()
                    // When autoFill is on, scale this row so its tiles fill the panel width.
                    readonly property real rowCellWidth: {
                        const baseW = root.baseCellWidth;
                        if (!Config.options.sidebar.quickToggles.android.autoFill) return baseW;
                        const sizeSum = (modelData ?? []).reduce((acc, t) => acc + (t?.size ?? 1), 0);
                        if (sizeSum <= 0) return baseW;
                        const totalAvail = root.width - root.padding * 2 - root.spacing * Math.max(0, root.columns - 1);
                        return totalAvail / sizeSum;
                    }
                    spacing: root.spacing

                    Repeater {
                        model: ScriptModel {
                            values: toggleRow?.modelData ?? []
                            objectProp: "type"
                        }
                        delegate: AndroidToggleDelegateChooser {
                            startingIndex: toggleRow.startingIndex
                            tabIndex: root.tabIndex
                            editMode: root.editMode
                            baseCellWidth: toggleRow.rowCellWidth
                            baseCellHeight: root.baseCellHeight
                            spacing: root.spacing
                            onOpenAudioOutputDialog: root.openAudioOutputDialog()
                            onOpenAudioInputDialog: root.openAudioInputDialog()
                            onOpenDevicesDialog: root.openDevicesDialog()
                            onOpenNightLightDialog: root.openNightLightDialog()
                            onOpenWifiDialog: root.openWifiDialog()
                            onOpenKdeConnectDialog: root.openKdeConnectDialog()
                            onOpenMonitorsDialog: root.openMonitorsDialog()
                            onOpenRssDialog: root.openRssDialog()
                        }
                    }
                }
            }
        }


        // ── Container drawer ────────────────────────────────────────────
        // Sits directly below the grid in BOTH modes. Was previously the
        // last child of contentItem, which left it scrolled off-screen in
        // edit mode (the unused-tile tray is up to 280px tall and pushed
        // the drawer past the panel's visible area).
        Loader {
            id: containerDrawer
            width: parent.width - root.padding * 2
            x: root.padding
            // Only load while open OR briefly afterwards, so the drawer
            // doesn't permanently keep its content components in memory.
            active: containerDrawer._shown || _drawerKeepAlive.running
            sourceComponent: containerDrawerComp
            clip: true
            visible: height > 0.5
            height: 0

            readonly property bool _shown:
                OpenContainerState.isOpen
                && OpenContainerState.tabIndex === root.tabIndex
                && !(OpenContainerState.type === "rog" && OpenContainerState.buttonIndex >= 0)

            Behavior on height {
                NumberAnimation { duration: 240; easing.type: Easing.OutCubic }
            }

            on_ShownChanged: {
                if (_shown) _drawerKeepAlive.stop()
                else        _drawerKeepAlive.restart()
                height = _shown && item ? item.implicitHeight : 0
            }
            // Hold the drawer alive for 250 ms after close so the close
            // animation can finish before the Loader frees its content.
            Timer { id: _drawerKeepAlive; interval: 250; repeat: false }
            Connections {
                target: containerDrawer.item ?? null
                ignoreUnknownSignals: true
                function onImplicitHeightChanged() {
                    if (containerDrawer._shown)
                        containerDrawer.height = containerDrawer.item.implicitHeight
                }
            }
        }

        // ── New-row button (edit mode) ────────────────────────────────
        // Appends a `rowBreak` sentinel to the user's tab.  toggleRowsForList
        // splits the layout at each sentinel so the user can intentionally
        // start a new row instead of relying on auto-wrap.
        Rectangle {
            visible: root.editMode
            anchors { left: parent.left; right: parent.right }
            implicitHeight: root.editMode ? 28 : 0
            Behavior on implicitHeight { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
            radius: height / 2
            color: newRowHov.hovered
                ? Qt.alpha(Appearance.colors.colPrimary, 0.18)
                : Qt.alpha(Appearance.colors.colOnLayer0, 0.05)
            Behavior on color { ColorAnimation { duration: 120 } }
            HoverHandler { id: newRowHov }
            TapHandler {
                onTapped: {
                    const list = ((root.tabIndex >= 0 &&
                                   Config.options.sidebar.quickToggles.android.tabs?.[root.tabIndex]?.toggles)
                                  ?? Config.options.sidebar.quickToggles.android.toggles
                                  ?? []).slice()
                    list.push({ type: "rowBreak" })
                    if (root.tabIndex >= 0) {
                        const cfg  = Config.options.sidebar.quickToggles.android
                        const tabs = cfg.tabs.slice()
                        tabs[root.tabIndex] = Object.assign({}, tabs[root.tabIndex], { toggles: list })
                        cfg.tabs = tabs
                    } else {
                        Config.options.sidebar.quickToggles.android.toggles = list
                    }
                }
            }
            Row {
                anchors.centerIn: parent
                spacing: 6
                MaterialSymbol {
                    anchors.verticalCenter: parent.verticalCenter
                    text: "add"; iconSize: 14
                    color: Appearance.colors.colOnLayer1
                }
                StyledText {
                    anchors.verticalCenter: parent.verticalCenter
                    text: Translation.tr("New row")
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: Appearance.colors.colOnLayer1
                }
            }
            // Remove-last-rowbreak chip on the right — only visible if at
            // least one rowBreak exists.
            Rectangle {
                anchors { right: parent.right; verticalCenter: parent.verticalCenter; rightMargin: 6 }
                width: 22; height: 22; radius: 11
                visible: root.toggles.some(t => t && t.type === "rowBreak")
                color: undoHov.hovered
                    ? Qt.alpha(Appearance.m3colors.m3error, 0.20)
                    : ColorUtils.transparentize(Qt.alpha(Appearance.m3colors.m3error, 0.20))
                Behavior on color { ColorAnimation { duration: 120 } }
                HoverHandler { margin: Appearance.sizes.touchSlop; id: undoHov }
                TapHandler {
                    margin: Appearance.sizes.touchSlop
                    onTapped: {
                        const cfg  = Config.options.sidebar.quickToggles.android
                        const list = ((root.tabIndex >= 0
                                       ? cfg.tabs?.[root.tabIndex]?.toggles
                                       : cfg.toggles) ?? []).slice()
                        for (let i = list.length - 1; i >= 0; i--) {
                            if (list[i] && list[i].type === "rowBreak") {
                                list.splice(i, 1); break
                            }
                        }
                        if (root.tabIndex >= 0) {
                            const tabs = cfg.tabs.slice()
                            tabs[root.tabIndex] = Object.assign({}, tabs[root.tabIndex], { toggles: list })
                            cfg.tabs = tabs
                        } else {
                            cfg.toggles = list
                        }
                    }
                }
                MaterialSymbol {
                    anchors.centerIn: parent
                    text: "remove"; iconSize: 12
                    color: undoHov.hovered ? Appearance.m3colors.m3error : Appearance.colors.colSubtext
                }
            }
        }

        // Old chip cloud — kept hidden; superseded by the regular tray.
        Item {
            id: addModule
            visible: false
            anchors { left: parent.left; right: parent.right }
            implicitHeight: addBtn.implicitHeight + (open ? chipFlow.implicitHeight + 6 : 0)
            Behavior on implicitHeight { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
            property bool open: false

            // Trigger tile — same height & rounding as grid buttons.
            Rectangle {
                id: addBtn
                anchors { left: parent.left; right: parent.right; top: parent.top }
                implicitHeight: root.baseCellHeight
                radius: addModule.open ? Appearance.rounding.large : height / 2
                Behavior on radius { animation: Appearance.animation.elementMove.numberAnimation.createObject(this) }
                color: addBtnHov.hovered ? Appearance.colors.colLayer2Hover : Appearance.colors.colLayer2
                Behavior on color { animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this) }
                HoverHandler { id: addBtnHov }
                TapHandler { onTapped: addModule.open = !addModule.open }
                Row {
                    anchors.centerIn: parent
                    spacing: 8
                    MaterialSymbol {
                        anchors.verticalCenter: parent.verticalCenter
                        text: "add"; iconSize: 22
                        color: Appearance.colors.colOnLayer2
                    }
                    StyledText {
                        anchors.verticalCenter: parent.verticalCenter
                        text: Translation.tr("Add module")
                        font.pixelSize: Appearance.font.pixelSize.smallie
                        font.weight: Font.Medium
                        color: Appearance.colors.colOnLayer2
                    }
                    MaterialSymbol {
                        anchors.verticalCenter: parent.verticalCenter
                        text: "expand_more"; iconSize: 18
                        color: Appearance.colors.colSubtext
                        rotation: addModule.open ? 180 : 0
                        Behavior on rotation { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
                    }
                }
            }

            // Expanding chip cloud (clipped for smooth height anim).
            Item {
                id: chipClip
                anchors { left: parent.left; right: parent.right; top: addBtn.bottom; topMargin: 6 }
                clip: true
                implicitHeight: addModule.open ? chipFlow.implicitHeight : 0
                opacity: addModule.open ? 1 : 0
                Behavior on implicitHeight { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
                Behavior on opacity { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }

                Flow {
                    id: chipFlow
                    anchors { left: parent.left; right: parent.right; top: parent.top }
                    spacing: 6
                    Repeater {
                        model: [
                            { type: "sliders",          label: "Sliders",   icon: "tune" },
                            { type: "devices", label: "Devices", icon: "devices" },
                            { type: "midi",             label: "MIDI",      icon: "piano" },
                            { type: "rog",              label: "ROG",       icon: "memory" },
                            { type: "phone",            label: "Phone",     icon: "smartphone" },
                        ]
                        delegate: Rectangle {
                            required property var modelData
                            implicitWidth: addChipRow.implicitWidth + 22
                            implicitHeight: 36
                            radius: 18
                            color: addChipHov.hovered ? Appearance.colors.colPrimary : Appearance.colors.colLayer2
                            Behavior on color { animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this) }
                            HoverHandler { id: addChipHov }
                            TapHandler {
                                onTapped: {
                                    if (root.tabIndex < 0) return
                                    const cfg = Config.options.sidebar.quickToggles.android
                                    const tabs = cfg.tabs.slice()
                                    const list = (tabs[root.tabIndex].toggles ?? []).slice()
                                    list.push({ type: modelData.type, size: root.defaultSizeForType(modelData.type) })
                                    tabs[root.tabIndex] = Object.assign({}, tabs[root.tabIndex], { toggles: list })
                                    cfg.tabs = tabs
                                }
                            }
                            Row {
                                id: addChipRow
                                anchors.centerIn: parent; spacing: 6
                                MaterialSymbol {
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: parent.parent.modelData.icon; iconSize: 16
                                    color: addChipHov.hovered ? Appearance.colors.colOnPrimary : Appearance.colors.colOnLayer2
                                }
                                StyledText {
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: parent.parent.modelData.label
                                    font.pixelSize: Appearance.font.pixelSize.smaller
                                    color: addChipHov.hovered ? Appearance.colors.colOnPrimary : Appearance.colors.colOnLayer2
                                }
                            }
                        }
                    }
                }
            }
        }

        FadeLoader {
            shown: root.editMode
            anchors {
                left: parent.left
                right: parent.right
                leftMargin: root.baseCellHeight / 2
                rightMargin: root.baseCellHeight / 2
            }
            sourceComponent: Rectangle {
                implicitHeight: 1
                color: Appearance.colors.colOutlineVariant
            }
        }

        // ── Tray search field ────────────────────────────────────────
        // Filter the unused-toggle tray by typing.
        FadeLoader {
            shown: root.editMode
            anchors { left: parent?.left; right: parent?.right }
            sourceComponent: Rectangle {
                radius: 14
                color: Appearance.colors.colLayer1Base
                border.width: 1
                border.color: Appearance.colors.colLayer0Border
                implicitHeight: 28
                Row {
                    anchors.fill: parent
                    anchors.leftMargin: 10
                    anchors.rightMargin: 10
                    spacing: 6
                    MaterialSymbol {
                        anchors.verticalCenter: parent.verticalCenter
                        text: "search"
                        iconSize: 14
                        color: Appearance.colors.colSubtext
                    }
                    StyledTextInput {
                        id: trayFilterInput
                        anchors.verticalCenter: parent.verticalCenter
                        width: parent.width - 70
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        text: root.trayFilter
                        onTextChanged: root.trayFilter = text
                        StyledText {
                            anchors.verticalCenter: parent.verticalCenter
                            text: qsTr("Filter available tiles…")
                            font.pixelSize: trayFilterInput.font.pixelSize
                            color: Appearance.colors.colSubtext
                            visible: trayFilterInput.text.length === 0
                        }
                    }
                    MaterialSymbol {
                        anchors.verticalCenter: parent.verticalCenter
                        visible: root.trayFilter.length > 0
                        text: "close"
                        iconSize: 13
                        color: Appearance.colors.colSubtext
                        TapHandler { onTapped: { root.trayFilter = ""; trayFilterInput.text = "" } }
                    }
                }
            }
        }

        // ── Scrollable tray ──────────────────────────────────────────
        // Caps the tray height so the grouped category list can't push
        // adjacent UI (container drawer / right-edge close button) out
        // of reach. Scrolls internally with mouse wheel / touchpad.
        FadeLoader {
            shown: root.editMode
            anchors { left: parent?.left; right: parent?.right }
            sourceComponent: Flickable {
                id: trayScroll
                implicitHeight: Math.min(contentHeight, 280)
                contentWidth: width
                contentHeight: unusedGroupedTray.implicitHeight
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                flickDeceleration: 4000

                // The tray's height AND its content both change as you type in
                // the filter, and StopAtBounds only constrains dragging — it does
                // not pull an already-out-of-range contentY back. Filtering from
                // many tiles to few therefore left the view scrolled past the end,
                // showing a half-row clipped under the search field with nothing
                // below it.
                onContentHeightChanged: Qt.callLater(returnToBounds)
                onHeightChanged: Qt.callLater(returnToBounds)
                // A new filter is a new list; start at the top of it.
                Connections {
                    target: root
                    function onTrayFilterChanged() { trayScroll.contentY = 0 }
                }
                ScrollBar.vertical: ScrollBar {
                    policy: trayScroll.contentHeight > trayScroll.height
                        ? ScrollBar.AlwaysOn
                        : ScrollBar.AsNeeded
                }
                Column {
                    id: unusedGroupedTray
                    width: parent.width
                    spacing: 10

                // Empty-state when the search filter matches nothing.
                StyledText {
                    visible: root.trayGroups.length === 0
                    text: qsTr("No tiles match “%1”").arg(root.trayFilter)
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: Appearance.colors.colSubtext
                    anchors.horizontalCenter: parent.horizontalCenter
                }

                Repeater {
                    model: ScriptModel {
                        values: root.trayGroups
                        objectProp: "id"
                    }
                    delegate: Column {
                        id: trayGroupCol
                        required property var modelData     // { id, label, tiles }
                        readonly property var groupRows: root.toggleRowsForList(modelData.tiles)
                        spacing: 4

                        // Tiny category header.
                        StyledText {
                            text: trayGroupCol.modelData.label.toUpperCase()
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            font.weight: Font.Bold
                            font.letterSpacing: 1.2
                            color: Appearance.colors.colSubtext
                            leftPadding: 2
                        }

                        Repeater {
                            model: ScriptModel { values: trayGroupCol.groupRows }
                            delegate: ButtonGroup {
                                id: grpRow
                                required property int index
                                required property var modelData    // a row (array of tiles)
                                spacing: root.spacing
                                Repeater {
                                    model: ScriptModel {
                                        values: grpRow.modelData ?? []
                                        objectProp: "type"
                                    }
                                    delegate: AndroidToggleDelegateChooser {
                                        startingIndex: -1
                                        tabIndex: root.tabIndex
                                        inTray: true
                                        editMode: root.editMode
                                        baseCellWidth: root.baseCellWidth
                                        baseCellHeight: root.baseCellHeight
                                        spacing: root.spacing
                                    }
                                }
                            }
                        }
                    }
                }
                } // Column unusedGroupedTray
            } // Flickable trayScroll
        }

        // ── Container drawer ───────────────────────────────────────────
        // Renders the open container's rich content here, in the empty
        // area at the bottom of the panel — below the unapplied tray.
        // Pre-loaded drawer host: the Loader is always active so its
        // item.implicitHeight is known the instant the user opens it.
        // We mirror "is the drawer opened in this tab" into a property
        // and animate height between 0 and that natural height.
        Component {
            id: containerDrawerComp
            ContainerDrawer {
                editMode: root.editMode
                tabIndex: root.tabIndex
                buttonIndex: OpenContainerState.buttonIndex
                containerType: OpenContainerState.type
            }
        }
    }

    function showTileContextMenu(localX, localY, model) {
        tileContextMenu.popup(localX, localY, model);
    }

    PopupContextMenu {
        id: tileContextMenu
        z: 99999
    }
}
