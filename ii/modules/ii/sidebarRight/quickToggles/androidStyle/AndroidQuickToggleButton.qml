import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.models.quickToggles
import qs.modules.common.functions
import qs.modules.common.widgets

GroupButton {
    id: root
    mouseArea.enabled: !root._showExpandedDelegate
    
    // Info to be passed to by repeater
    required property int buttonIndex
    required property var buttonData
    required property bool expandedSize
    required property real baseCellWidth
    required property real baseCellHeight
    required property real cellSpacing
    required property int cellSize

    // Signals
    signal openMenu()

    // Declared in specific toggles
    property QuickToggleModel toggleModel
    property string name: toggleModel?.name ?? ""
    property string statusText: (toggleModel?.hasStatusText) ? (toggleModel?.statusText || (toggled ? Translation.tr("Active") : Translation.tr("Inactive"))) : ""
    property string tooltipText: toggleModel?.tooltipText ?? ""
    property string buttonIcon: toggleModel?.icon ?? "close"
    property string buttonIconImage: toggleModel?.iconImage ?? ""
    property bool available: toggleModel?.available ?? true
    toggled: toggleModel?.toggled ?? false
    property var mainAction: toggleModel?.mainAction ?? null
    readonly property var settingsAction: toggleModel?.hasMenu ? (() => root.openMenu()) : (toggleModel?.altAction ?? null)
    altAction: (event) => root.openContextMenu(event, false)

    // Edit mode state
    property bool editMode: false
    // -1 means edits target the legacy single list; otherwise the indexed tab.
    property int tabIndex: -1
    // True when the tile is being rendered in the unused-toggle tray (no × overlay, tap-to-add).
    property bool inTray: false

    // Edit mode toggling off while a tile is being dragged would skip the
    // MouseArea's onReleased/onCanceled (the area hides), leaving dragging /
    // dragX / dragY stuck — so the tile renders with its lift scale and
    // shadow on the next edit session. Clear the local visual state here.
    onEditModeChanged: {
        if (!editMode && (root.dragging || root.dragX !== 0 || root.dragY !== 0)) {
            root.dragging = false
            root.dragX = 0
            root.dragY = 0
        }
    }

    // Helper to fetch the live toggles array we should edit.
    function _activeList() {
        const cfg = Config.options.sidebar.quickToggles.android;
        if (root.tabIndex >= 0 && cfg.tabs && cfg.tabs[root.tabIndex])
            return cfg.tabs[root.tabIndex].toggles;
        return cfg.toggles;
    }
    function _writeActiveList(arr) {
        const cfg = Config.options.sidebar.quickToggles.android;
        if (root.tabIndex >= 0 && cfg.tabs && cfg.tabs[root.tabIndex]) {
            // Reassign the tab object so the JsonObject notices the change.
            const tabs = cfg.tabs.slice();
            tabs[root.tabIndex] = Object.assign({}, tabs[root.tabIndex], { toggles: arr });
            cfg.tabs = tabs;
        } else {
            cfg.toggles = arr;
        }
    }

    // Sizing shenanigans
    // Container tiles are always 1 cell wide — we don't want autoFill
    // stretching them across a half-empty row, since they're meant to
    // look like compact icon buttons that the drawer expands. When the
    // container is "open" the tile animates into a full-row card so its
    // children render inline (instead of in a panel-level drawer).
    readonly property int _columns:
        (Config?.options?.sidebar?.quickToggles?.android?.columns) ?? 5
    baseWidth: containerType !== ""
        ? (root._isContainerOpen
            ? (root.baseCellWidth * root._columns + cellSpacing * (root._columns - 1))
            : root.baseCellHeight)
        : root.baseCellWidth * cellSize + cellSpacing * (cellSize - 1)
    // Tiles with a custom expanded delegate (LastFm media etc.) get
    // 2× height so they have room for the richer content.
    // tallTile: true opts into letting the expanded delegate's
    // implicitHeight drive the tile (used by panel-style widgets like
    // Sliders/MIDI/ROG/Phone that need full panel height).
    property bool tallTile: false
    // When true, an expanded tile keeps the standard cell height (~56)
    // instead of growing to 2× — used by atoms whose styled content (a
    // single pill) is meant to look the same height as a normal toggle
    // tile (WLAN, Bluetooth).
    property bool compactExpanded: false
    // Open container tiles take whatever height their expandedDelegate
    // wants, the same way `tallTile` already does for non-container tiles.
    readonly property bool _showExpandedDelegate:
        (root.expandedSize || root._isContainerOpen) && root.expandedDelegate !== null
    baseHeight: _showExpandedDelegate
        ? (root.compactExpanded
            ? root.baseCellHeight
            : ((root.tallTile || root._isContainerOpen) && expandedLoader.item
                ? Math.max(root.baseCellHeight,
                           expandedLoader.item.implicitHeight + root.verticalPadding * 2)
                : root.baseCellHeight * 2 + cellSpacing))
        : root.baseCellHeight
    // Stretch every tile to the tallest sibling in its row — when one
    // tile uses an expanded delegate (2× height), the other tiles in
    // the same row grow to match instead of staying short.
    Layout.fillHeight: true
    enableImplicitWidthAnimation: !editMode && root.mouseArea.containsMouse
    enableImplicitHeightAnimation: !editMode && root.mouseArea.containsMouse
    // Per-tile size-animation duration.  Defaults to the global elementMove
    // duration; tiles that should resize instantly (e.g. Bluetooth's
    // inline panel tile) set this to 0.
    property int sizeAnimDuration: Appearance.animation.elementMove.duration
    Behavior on baseWidth {
        NumberAnimation {
            duration: root.sizeAnimDuration
            easing.type: Appearance.animation.elementMove.type
            easing.bezierCurve: Appearance.animation.elementMove.bezierCurve
        }
    }
    Behavior on baseHeight {
        NumberAnimation {
            duration: root.sizeAnimDuration
            easing.type: Appearance.animation.elementMove.type
            easing.bezierCurve: Appearance.animation.elementMove.bezierCurve
        }
    }
    opacity: 0
    Component.onCompleted: {
        opacity = 1
        if (root.mouseArea)
            root.mouseArea.pressAndHoldInterval = root.holdDurationMs
    }
    Behavior on opacity {
        animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
    }

    enabled: available || editMode
    padding: 6
    horizontalPadding: padding
    verticalPadding: padding

    // While a hold is in progress, the tile's pill background fades out
    // so only the rotating cookie shape remains visible.
    colBackground: root._holdPressed
        ? "transparent"
        : Appearance.colors.colLayer2
    colBackgroundToggled: root._holdPressed
        ? "transparent"
        : ((settingsAction && expandedSize) ? Appearance.colors.colLayer2 : Appearance.colors.colPrimary)
    colBackgroundToggledHover: root._holdPressed
        ? "transparent"
        : ((settingsAction && expandedSize) ? Appearance.colors.colLayer2Hover : Appearance.colors.colPrimaryHover)
    colBackgroundToggledActive: root._holdPressed
        ? "transparent"
        : ((settingsAction && expandedSize) ? Appearance.colors.colLayer2Active : Appearance.colors.colPrimaryActive)
    // Compact 1×1 tiles use stadium-pill rounding (height/2). Anything
    // multi-cell / expanded / with a custom expanded delegate (RSS,
    // mounting, lastfm, …) falls back to chunky large rounding so the
    // bigger widgets don't look like giant capsules.
    readonly property bool _isCompactPill:
           !expandedSize
        && cellSize === 1
        && expandedDelegate === null
    // When a 1×1 tile is stretched tall by fillHeight (to match a tall
    // sibling like RSS), height/2 makes it an egg. Cap the pill radius
    // at the short edge AND at large-rounding so it doesn't look weird.
    buttonRadius: _isCompactPill
        ? Math.min(width, height) / 2
        : Appearance.rounding.large
    buttonRadiusPressed: Appearance.rounding.normal
    property color colText: root._holdPressed
        ? Appearance.colors.colOnPrimary
        : ((toggled && !(settingsAction && expandedSize) && enabled)
            ? Appearance.colors.colOnPrimary
            : ColorUtils.transparentize(Appearance.colors.colOnLayer2, enabled ? 0 : 0.7))
    property color colIcon: root._holdPressed
        ? Appearance.colors.colOnPrimary
        : (expandedSize
            ? ((root.toggled) ? Appearance.colors.colOnPrimary : Appearance.colors.colOnLayer3)
            : colText)
    Behavior on colText { ColorAnimation { duration: root.holdDurationMs * 0.9 } }
    Behavior on colIcon { ColorAnimation { duration: root.holdDurationMs * 0.9 } }

    // When true, left-clicking the tile flips its grid size between
    // 1 (compact icon) and `expandedCellSize` (default = columns, full row).
    // Used by panel-style tiles that expand inline (LastFm, Mounting, …).
    property bool expandOnClick: false
    property int  expandedCellSize: -1   // -1 → use columns

    // Container tiles set this to a short string ("rog" / "sliders" / …).
    // When set, left-click opens or closes the panel-wide drawer (managed
    // by OpenContainerState) instead of resizing the tile. The tile itself
    // stays 1×1 in the grid; its rich content renders in the drawer below.
    property string containerType: ""
    readonly property bool _isContainerOpen:
        containerType !== "" &&
        OpenContainerState.isOpen &&
        OpenContainerState.tabIndex === root.tabIndex &&
        OpenContainerState.buttonIndex === root.buttonIndex

    // Atomic widgets (e.g. rogProfile, volumeSlider) set this to their
    // parent container's type ("rog" / "sliders").  Long-pressing the
    // tile then opens that container's drawer — finds an existing one
    // in the same tab if there is one, otherwise adds one.
    property string parentContainerType: ""

    // ── Long-press / hold action ─────────────────────────────────────
    // Tray container icon  →  add to tab + open its drawer
    // Atomic widget on grid →  open parent container drawer
    // Otherwise            →  toggle tile size (legacy behavior)
    function _holdAction() {
        const wantedType = root.inTray
            ? root.containerType
            : (root.parentContainerType || root.containerType);
        if (wantedType === "" || root.tabIndex < 0) return;

        // If the matching drawer is already open, hold = close it.
        if (OpenContainerState.isOpen
            && OpenContainerState.tabIndex === root.tabIndex
            && OpenContainerState.type === wantedType) {
            OpenContainerState.close();
            return;
        }

        // Find an existing container of the wanted type in this tab.
        const cfg = Config.options.sidebar.quickToggles.android;
        const tab = cfg.tabs?.[root.tabIndex];
        const list = tab?.toggles ?? [];
        const idx = list.findIndex(t => t && t.type === wantedType);

        // If a container is already in the grid → open *it* (real entry,
        // edits persist).  Otherwise open the drawer in preview mode
        // (buttonIndex -1, no grid addition, edits don't persist).
        OpenContainerState.open(root.tabIndex, wantedType, idx, false);
    }

    // ── Hold-progress visualization ──────────────────────────────────
    readonly property int holdDurationMs: 550
    readonly property int holdVisualDelayMs: Appearance.animDur(120)   // 0 when animationSpeedFactor=0
    readonly property bool _hasHoldAction:
        !editMode ||
        (containerType !== "") ||
        (parentContainerType !== "" && !inTray)
    property bool _pressActive: false      // mouseArea.pressed mirror
    property bool _holdPressed: false      // visual flag, after delay
    property bool _heldFired:   false      // true if the long-press has fired

    // When the tile flips into "showing inline container content", the hold
    // MouseArea that started the press gets disabled before its onReleased
    // fires — leaving _pressActive / _holdPressed stuck true and the
    // SineCookie pulsing forever. Force a reset on the transition.
    readonly property bool _suppressHoldVisual:
        root.containerType !== "" && root._showExpandedDelegate
    on_SuppressHoldVisualChanged: {
        if (_suppressHoldVisual) {
            _pressActive = false
            _holdPressed = false
            holdVisualTimer.stop()
        }
    }

    Timer {
        id: holdVisualTimer
        interval: root.holdVisualDelayMs
        repeat: false
        onTriggered: {
            if (root._pressActive) root._holdPressed = true
        }
    }

    // Hold detection — disabled while the tile is rendering an inline
    // container (the children themselves are interactive, so a hold visual
    // on the tile would obscure them) and while in edit mode (the edit
    // MouseArea owns presses there).
    Connections {
        target: root.mouseArea
        enabled: root._hasHoldAction && !root.editMode
            && !(root.containerType !== "" && root._showExpandedDelegate)
        function onPressed(mouse) {
            root._pressActive = true
            root._heldFired = false
            holdVisualTimer.restart()
        }
        function onReleased(mouse) {
            root._pressActive = false
            root._holdPressed = false
            holdVisualTimer.stop()
        }
        function onCanceled() {
            root._pressActive = false
            root._holdPressed = false
            holdVisualTimer.stop()
        }
        function onPressAndHold(mouse) {
            root._heldFired = true
            if (root.altAction) root.altAction(mouse)
        }
    }


    onClicked: {
        // Suppress the click that follows a successful long-press.
        if (root._heldFired) {
            root._heldFired = false
            return;
        }
        // Chip MouseAreas inside the expanded ContainerDrawer consume their
        // own presses, so a chip tap no longer leaks here as a tile click —
        // we don't need to gate on _showExpandedDelegate.
        if (root.containerType !== "") {
            // Toggle the panel-wide drawer for this container tile.
            OpenContainerState.toggle(root.tabIndex, root.containerType, root.buttonIndex)
            return;
        }
        if (root.expandOnClick) {
            const cols = (Config?.options?.sidebar?.quickToggles?.android?.columns) ?? 5;
            const expanded = root.expandedCellSize > 0
                ? Math.max(2, Math.min(cols, root.expandedCellSize))
                : cols;
            const list = root._activeList().slice();
            const idx = root.buttonIndex;
            if (idx >= 0 && idx < list.length && list[idx]) {
                const cur = list[idx].size ?? 1;
                const next = cur > 1 ? 1 : expanded;
                list[idx] = Object.assign({}, list[idx], { size: next });
                root._writeActiveList(list);
            }
            return;
        }
        if (root.expandedSize && root.settingsAction) root.settingsAction();
        else root.mainAction();
    }

    // Optional override for the inner layout when the tile is in
    // expanded form. When set, it REPLACES the default icon+text row
    // (used by the LastFm/media tile to render album art + controls).
    property Component expandedDelegate: null

    contentItem: Item {
        // Hold-progress visual — same SineCookie squircle that the touch
        // edge hint chip uses.  Sits behind the icon, swells in, spins
        // continuously while held, and fades back smoothly on release.
        SineCookie {
            id: holdCookie
            anchors.centerIn: parent
            implicitSize: Math.min(parent.width, parent.height) * 1.1
            sides: root._holdPressed ? 8 : 4
            color: Appearance.colors.colPrimary
            constantlyRotate: root._holdPressed
            opacity: root._holdPressed ? 1.0 : 0
            // Cookie starts tiny (0.3), then swells past tile size (1.15)
            // as the hold progresses.
            scale: root._holdPressed ? 1.15 : 0.3
            visible: root._hasHoldAction && opacity > 0.01
            // Cookie renders BELOW the icon so the icon stays visible on
            // top of the rotating shape during hold.
            z: -1
            Behavior on opacity { NumberAnimation { duration: root.holdDurationMs * 0.9; easing.type: Easing.OutCubic } }
            Behavior on scale   { NumberAnimation { duration: root.holdDurationMs * 0.9; easing.type: Easing.OutCubic } }
        }

        // Custom expanded layout — only when both an override is supplied
        // and the tile is in expanded size.

        Loader {
            id: expandedLoader
            anchors.fill: parent
            anchors.margins: root.horizontalPadding
            active: root._showExpandedDelegate
            sourceComponent: root.expandedDelegate
            visible: active
            // Disable input on the rich content while editing — TapHandlers
            // inside (RSS refresh/popup/rows, lastfm play, etc.) used to
            // swallow drag presses, making the tile undraggable.
            enabled: !root.editMode || root.containerType !== ""
            // Dim the rich content so the edit overlay (name, drag hint,
            // close button) is the focal point while editing — UNLESS this
            // is an open container, in which case the inline children are
            // exactly what the user wants to see while configuring.
            opacity: (root.editMode && !root._isContainerOpen) ? 0.35 : 1
            Behavior on opacity { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
        }

        // Edit-mode overlay for tiles with a custom expanded delegate —
        // shows the tile NAME + a drag-hint icon over the dimmed content
        // so the user can identify what they're rearranging.
        Item {
            anchors.fill: parent
            visible: root.editMode && root.expandedSize && root.expandedDelegate !== null
                && !root._isContainerOpen
            Row {
                anchors.centerIn: parent
                spacing: 8
                MaterialSymbol {
                    anchors.verticalCenter: parent.verticalCenter
                    text: "drag_indicator"
                    iconSize: 22
                    color: Appearance.colors.colOnLayer2
                }
                StyledText {
                    anchors.verticalCenter: parent.verticalCenter
                    text: root.toggleModel?.name ?? root.buttonText ?? root.buttonData?.type ?? ""
                    font.pixelSize: Appearance.font.pixelSize.normal
                    font.weight: Font.DemiBold
                    color: Appearance.colors.colOnLayer2
                }
            }
        }

        // Default layout — hidden when the custom expanded delegate is active.
        RowLayout {
        id: contentItem
        visible: !root._showExpandedDelegate
        spacing: 4
        anchors {
            centerIn: root.expandedSize ? undefined : parent
            fill: root.expandedSize ? parent : undefined
            leftMargin: root.horizontalPadding
            rightMargin: root.horizontalPadding
        }

        // Icon
        MouseArea {
            id: iconMouseArea
            hoverEnabled: true
            acceptedButtons: (root.expandedSize && root.settingsAction) ? Qt.LeftButton : Qt.NoButton
            Layout.alignment: Qt.AlignHCenter
            Layout.fillHeight: true
            Layout.topMargin: root.verticalPadding
            Layout.bottomMargin: root.verticalPadding
            implicitHeight: iconBackground.implicitHeight
            implicitWidth: iconBackground.implicitWidth
            cursorShape: Qt.PointingHandCursor

            onClicked: root.mainAction()

            Rectangle {
                id: iconBackground
                anchors.fill: parent
                implicitWidth: height
                radius: root.radius - root.verticalPadding
                color: {
                    const baseColor = root.toggled ? Appearance.colors.colPrimary : Appearance.colors.colLayer3
                    const transparentizeAmount = (root.settingsAction && root.expandedSize) ? 0 : 1
                    return ColorUtils.transparentize(baseColor, transparentizeAmount)
                }

                Behavior on radius {
                    animation: Appearance.animation.elementMove.numberAnimation.createObject(this)
                }
                Behavior on color {
                    animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
                }

                MaterialSymbol {
                    anchors.centerIn: parent
                    visible: root.buttonIconImage.length === 0
                    fill: root.toggled ? 1 : 0
                    iconSize: root.expandedSize ? 22 : 24
                    color: root.colIcon
                    text: root.buttonIcon
                }

                // Album art / avatar (used by the Last.fm tile) — shown
                // when iconImage is non-empty. Inset by the parent's
                // radius so the corners stay inside the rounded shape
                // even though clip: true on a rounded Rectangle only
                // clips to the bounding box.
                Image {
                    id: iconImg
                    visible: status === Image.Ready && root.buttonIconImage.length > 0
                    anchors.centerIn: parent
                    width:  parent.width  - 6
                    height: parent.height - 6
                    source: root.buttonIconImage
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                    smooth: true
                    cache: true
                    sourceSize.width:  64
                    sourceSize.height: 64
                }

                // State layer
                Loader {
                    anchors.fill: parent
                    active: (root.expandedSize && root.settingsAction)
                    sourceComponent: Rectangle {
                        radius: iconBackground.radius
                        color: ColorUtils.transparentize(root.colIcon, iconMouseArea.containsPress ? 0.88 : iconMouseArea.containsMouse ? 0.95 : 1)
                        Behavior on color {
                            animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
                        }
                    }
                }
            }
        }

        // Text column for expanded size
        Loader {
            Layout.alignment: Qt.AlignVCenter
            Layout.fillWidth: true
            visible: root.expandedSize
            active: visible
            sourceComponent: Column {
                spacing: -2

                StyledText {
                    anchors {
                        left: parent.left
                        right: parent.right
                    }
                    font.pixelSize: Appearance.font.pixelSize.smallie
                    font.weight: 600
                    color: root.colText
                    elide: Text.ElideRight
                    text: root.name
                }

                StyledText {
                    visible: root.statusText
                    anchors {
                        left: parent.left
                        right: parent.right
                    }
                    font {
                        pixelSize: Appearance.font.pixelSize.smaller
                        weight: 100
                    }
                    color: root.colText
                    elide: Text.ElideRight
                    text: root.statusText
                }
            }
        }
        } // end of default-layout RowLayout
    }

    // Drag-to-reorder visual offset. No Behavior — we want pixel-perfect tracking
    function _defaultSize(type) {
        const cols = (Config?.options?.sidebar?.quickToggles?.android?.columns) ?? 5;
        if (["bluetoothDevices","midi","phone"].includes(type)) return cols;
        if (["volumeSlider","brightnessSlider","micSlider",
             "rogProfile","rogGpu","rogBattery","rogCharge"].includes(type))
            return Math.max(2, Math.min(3, cols));
        if (["lastfm","mounting","offload","rss"].includes(type)) return 2;
        return 1;
    }

    function _setSize(size) {
        const list = root._activeList().slice();
        const index = root.buttonIndex;
        if (index >= 0 && index < list.length && list[index]) {
            list[index] = Object.assign({}, list[index], { size: size });
            root._writeActiveList(list);
        }
    }

    function openContextMenu(event, isEditMode) {
        const mx = event ? event.x : root.width / 2;
        const my = event ? event.y : root.height / 2;
        const pt = root.mapToItem(quickPanel, mx, my);

        const items = [];

        if (isEditMode) {
            if (root.inTray) {
                const cfg = Config.options.sidebar.quickToggles.android;
                const tabs = cfg.tabs ?? [];
                for (let i = 0; i < tabs.length; i++) {
                    const tabName = tabs[i].name;
                    const tabIdx = i;
                    items.push({
                        icon: tabs[i].icon || "tab",
                        label: Translation.tr("Add to %1").arg(tabName),
                        onTriggered: () => {
                            const list = (tabs[tabIdx].toggles ?? []).slice();
                            list.push({ type: root.buttonData.type, size: root._defaultSize(root.buttonData.type) });
                            const newTabs = cfg.tabs.slice();
                            newTabs[tabIdx] = Object.assign({}, tabs[tabIdx], { toggles: list });
                            cfg.tabs = newTabs;
                            if (root.containerType !== "") {
                                OpenContainerState.open(tabIdx, root.containerType, list.length - 1, false);
                            }
                        }
                    });
                }
            } else {
                items.push({
                    icon: "delete",
                    danger: true,
                    label: Translation.tr("Remove"),
                    onTriggered: () => {
                        const list = root._activeList().slice();
                        list.splice(root.buttonIndex, 1);
                        root._writeActiveList(list);
                    }
                });

                items.push({ separator: true });

                const cols = (Config?.options?.sidebar?.quickToggles?.android?.columns) ?? 5;
                if (root.cellSize !== 1) {
                    items.push({
                        icon: "photo_size_select_small",
                        label: Translation.tr("Make Compact (1x1)"),
                        onTriggered: () => root._setSize(1)
                    });
                }
                if (root.cellSize !== 2 && cols >= 2) {
                    items.push({
                        icon: "aspect_ratio",
                        label: Translation.tr("Make Medium (2x1)"),
                        onTriggered: () => root._setSize(2)
                    });
                }
                if (root.cellSize !== cols && cols > 2) {
                    items.push({
                        icon: "fullscreen",
                        label: Translation.tr("Make Full Row"),
                        onTriggered: () => root._setSize(cols)
                    });
                }

                const cfg = Config.options.sidebar.quickToggles.android;
                const tabs = cfg.tabs ?? [];
                if (tabs.length > 1 && root.tabIndex >= 0) {
                    items.push({ separator: true });
                    for (let i = 0; i < tabs.length; i++) {
                        if (i === root.tabIndex) continue;
                        const tabName = tabs[i].name;
                        const tabIdx = i;
                        items.push({
                            icon: "move_up",
                            label: Translation.tr("Move to %1").arg(tabName),
                            onTriggered: () => {
                                const fromList = root._activeList().slice();
                                const moved = fromList.splice(root.buttonIndex, 1)[0];
                                if (moved) {
                                    root._writeActiveList(fromList);
                                    const toList = (tabs[tabIdx].toggles ?? []).slice();
                                    toList.push(moved);
                                    const newTabs = cfg.tabs.slice();
                                    newTabs[root.tabIndex] = Object.assign({}, tabs[root.tabIndex], { toggles: fromList });
                                    newTabs[tabIdx] = Object.assign({}, tabs[tabIdx], { toggles: toList });
                                    cfg.tabs = newTabs;
                                }
                            }
                        });
                    }
                }
            }
        } else {
            items.push({
                icon: root.toggled ? "toggle_on" : "toggle_off",
                label: root.toggled ? Translation.tr("Deactivate") : Translation.tr("Activate"),
                onTriggered: () => root.mainAction()
            });

            const altAct = root.settingsAction;
            if (altAct) {
                items.push({
                    icon: "settings",
                    label: Translation.tr("Settings"),
                    onTriggered: () => altAct()
                });
            }

            items.push({ separator: true });

            items.push({
                icon: "edit",
                label: Translation.tr("Edit Layout"),
                onTriggered: () => { quickPanel.editMode = true; }
            });

            items.push({
                icon: "delete",
                danger: true,
                label: Translation.tr("Remove"),
                onTriggered: () => {
                    const list = root._activeList().slice();
                    list.splice(root.buttonIndex, 1);
                    root._writeActiveList(list);
                }
            });
        }

        quickPanel.showTileContextMenu(pt.x, pt.y, items);
    }

    // Drag-to-reorder visual offset. No Behavior — we want pixel-perfect tracking
    // during drag and an instant snap on release (no bounce-back animation).
    property real dragX: 0
    property real dragY: 0
    property bool dragging: false
    transform: Translate { x: root.dragX; y: root.dragY }
    z: dragging ? 100 : 0

    // Drag-lift feedback — when this tile is being dragged, scale it up
    // slightly and drop a soft shadow so it visibly "lifts" off the grid.
    scale: dragging ? 1.06 : 1
    Behavior on scale { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }
    Loader {
        anchors.fill: parent
        z: -1
        active: root.dragging
        sourceComponent: Rectangle {
            anchors.fill: parent
            radius: root.buttonRadius
            color: "transparent"
            border.width: 0
            // Soft dark drop shadow approximation: a slightly larger
            // dark rectangle behind, offset by ~3 px on Y.
            Rectangle {
                anchors.fill: parent
                anchors.margins: -2
                anchors.topMargin: 1
                radius: parent.radius + 2
                color: Qt.alpha("black", 0.25)
                z: -1
            }
        }
    }

    MouseArea { // Blocking MouseArea for edit interactions
        id: editModeInteraction
        // Hide whenever a container tile is rendering its inline children
        // (either explicitly opened via hold, or just sized > 1) so the
        // children's own drag/chip MouseAreas receive the press. Close the
        // container or shrink the tile if you want to drag it as a whole.
        visible: root.editMode
            && !(root.containerType !== "" && root._showExpandedDelegate)
        z: 100   // sit above GroupButton's internal MouseArea & expanded delegate
        anchors.fill: parent
        cursorShape: root.dragging ? Qt.ClosedHandCursor : Qt.PointingHandCursor
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        // preventStealing keeps the drag glued to this tile while moving across siblings,
        // but causes weirdness on release. Use it only after drag actually starts.
        preventStealing: dragStarted

        property real pressX: 0
        property real pressY: 0
        property bool dragStarted: false
        property bool holdFired: false   // set true by onPressAndHold so onReleased can skip
        readonly property real dragThreshold: 4

        function _defaultSize(type) {
            const cols = (Config?.options?.sidebar?.quickToggles?.android?.columns) ?? 5;
            if (["bluetoothDevices","midi","phone"].includes(type)) return cols;
            if (["volumeSlider","brightnessSlider","micSlider",
                 "rogProfile","rogGpu","rogBattery","rogCharge"].includes(type))
                return Math.max(2, Math.min(3, cols));
            if (["lastfm","mounting","offload","rss"].includes(type)) return 2;
            return 1;
        }

        function toggleEnabled() {
            const list = root._activeList().slice();
            const index = root.buttonIndex;
            const buttonType = root.buttonData.type;
            if (!list.find(t => t && t.type === buttonType)) {
                list.push({ type: buttonType, size: _defaultSize(buttonType) });
                root._writeActiveList(list);
            } else {
                list.splice(index, 1);
                root._writeActiveList(list);
            }
        }

        function toggleSize() {
            const list = root._activeList().slice();
            const index = root.buttonIndex;
            const buttonType = root.buttonData.type;
            if (!list.find(t => t && t.type === buttonType)) return;
            const cols = (Config?.options?.sidebar?.quickToggles?.android?.columns) ?? 5;
            const cur = list[index].size ?? 1;
            // Cycle 1 → 2 → cols → 1.  Lets widget-style tiles (RSS,
            // mounting, lastfm, …) reach full-row width via right-click.
            let next;
            if (cur <= 1) next = 2;
            else if (cur < cols) next = cols;
            else next = 1;
            list[index] = Object.assign({}, list[index], { size: next });
            root._writeActiveList(list);
        }

        function movePositionBy(offset) {
            const list = root._activeList().slice();
            const index = root.buttonIndex;
            const buttonType = root.buttonData.type;
            if (!list.find(t => t && t.type === buttonType)) return;
            // Splice-based move: pull this tile out, then re-insert at the
            // target index. Lets tiles glide *through* rowBreak sentinels
            // (which used to block via swap-locking) and lets a tile drop
            // into a freshly-added empty row.
            const moved = list.splice(index, 1)[0];
            let targetIndex = index + offset;
            if (targetIndex < 0) targetIndex = 0;
            if (targetIndex > list.length) targetIndex = list.length;
            list.splice(targetIndex, 0, moved);
            root._writeActiveList(list);
        }

        // Track press in the PARENT's coord space so the tile's own Translate
        // doesn't feed back into event.x/event.y.
        function _pp(event) {
            return root.parent ? root.mapToItem(root.parent, event.x, event.y) : Qt.point(event.x, event.y);
        }

        // Use the same hold interval as the non-edit TapHandler so both
        // paths feel identical.
        pressAndHoldInterval: root.holdDurationMs

        onPressed: (event) => {
            if (event.button === Qt.LeftButton) {
                const p = _pp(event);
                pressX = p.x; pressY = p.y;
                dragStarted = false;
                holdFired  = false;
                if (root._hasHoldAction) {
                    root._pressActive = true;
                    holdVisualTimer.restart();
                }
            } else if (event.button === Qt.RightButton) {
                root.openContextMenu(event, true);
            }
        }
        onPositionChanged: (event) => {
            if (!(event.buttons & Qt.LeftButton)) return;
            const p = _pp(event);
            const dx = p.x - pressX;
            const dy = p.y - pressY;
            if (!dragStarted && (Math.abs(dx) > dragThreshold || Math.abs(dy) > dragThreshold)) {
                dragStarted = true;
                root.dragging = true;
                // Cancel any pending hold visual now that the user is dragging.
                root._pressActive = false;
                root._holdPressed = false;
                holdVisualTimer.stop();
                // Anchor at current cursor position so the tile doesn't snap by `dragThreshold`.
                pressX = p.x; pressY = p.y;
                QuickToggleDragState.begin(root.tabIndex, root.buttonIndex, root.buttonData.type);
                return;
            }
            if (dragStarted) {
                root.dragX = dx;
                root.dragY = dy;
            }
        }
        onReleased: (event) => {
            if (event.button !== Qt.LeftButton) return;
            root._pressActive = false;
            root._holdPressed = false;
            holdVisualTimer.stop();
            if (!dragStarted) {
                // If a long-press already fired (opened a container drawer
                // or toggled size), don't run the tap/click handler too.
                if (holdFired) { holdFired = false; return; }
                // Tray tiles: tap adds normal toggles. Container tiles
                // (rog / sliders / phone / midi / bluetoothDevices) are
                // intentionally NOT added on tap — they're added by
                // drag-and-drop into a tab, so a stray click can't
                // pollute the grid with a giant container.
                if (root.inTray && root.containerType === "") toggleEnabled();
                return;
            }
            // Drag finished — decide what to do.
            const dropTab = QuickToggleDragState.dropTab;
            const dropCT  = QuickToggleDragState.dropContainerTab;
            const dropCI  = QuickToggleDragState.dropContainerIndex;
            const fromTray = root.inTray;

            // ── Drop INTO a container? ─────────────────────────────────
            if (dropCT >= 0 && dropCI >= 0) {
                const cfg = Config.options.sidebar.quickToggles.android;
                const tabs = cfg.tabs.slice();
                const tab  = tabs[dropCT];
                if (tab) {
                    const list = (tab.toggles ?? []).slice();
                    let containerIdx = dropCI;
                    // If source is in same tab AND ahead of the container in
                    // the list, removing it shifts the container index left.
                    if (!fromTray && root.tabIndex === dropCT
                        && root.buttonIndex >= 0
                        && root.buttonIndex < list.length
                        && root.buttonIndex !== dropCI) {
                        if (root.buttonIndex < containerIdx) containerIdx -= 1;
                        list.splice(root.buttonIndex, 1);
                    }
                    const container = list[containerIdx];
                    if (container) {
                        const childList = (container.children ?? []).slice();
                        if (!childList.find(c => c && c.type === root.buttonData.type)) {
                            childList.push({ type: root.buttonData.type });
                            list[containerIdx] = Object.assign({}, container, { children: childList });
                        }
                        tabs[dropCT] = Object.assign({}, tab, { toggles: list });
                        cfg.tabs = tabs;
                    }
                }
                root.dragging = false; root.dragX = 0; root.dragY = 0;
                QuickToggleDragState.end();
                dragStarted = false;
                return;
            }

            if (fromTray && dropTab >= 0) {
                // Add tray toggle to the dropped tab.
                const cfg = Config.options.sidebar.quickToggles.android;
                const tabs = cfg.tabs.slice();
                const toList = (tabs[dropTab].toggles ?? []).slice();
                toList.push({ type: root.buttonData.type, size: _defaultSize(root.buttonData.type) });
                tabs[dropTab] = Object.assign({}, tabs[dropTab], { toggles: toList });
                cfg.tabs = tabs;
                // If a container was dropped, pop its drawer open so the
                // user can immediately see what they just added.
                if (root.containerType !== "") {
                    OpenContainerState.open(dropTab, root.containerType, toList.length - 1, false);
                }
            } else if (fromTray) {
                // Released without target — add to current tab so user can grab phone back.
                // Container tiles should NOT be auto-applied when released/held from the tray.
                if (root.tabIndex >= 0 && root.containerType === "") {
                    toggleEnabled();
                }
            } else if (dropTab >= 0 && dropTab !== root.tabIndex && root.tabIndex >= 0) {
                // Move existing tile to another tab.
                const cfg = Config.options.sidebar.quickToggles.android;
                const tabs = cfg.tabs.slice();
                const fromList = (tabs[root.tabIndex].toggles ?? []).slice();
                const moved = fromList.splice(root.buttonIndex, 1)[0];
                if (moved) {
                    const toList = (tabs[dropTab].toggles ?? []).slice();
                    toList.push(moved);
                    tabs[root.tabIndex] = Object.assign({}, tabs[root.tabIndex], { toggles: fromList });
                    tabs[dropTab]      = Object.assign({}, tabs[dropTab],      { toggles: toList   });
                    cfg.tabs = tabs;
                }
            } else {
                // Within-tab reorder: snap to nearest neighbor based on drag distance.
                const w = root.width + (root.cellSpacing ?? 6);
                const h = root.height + (root.cellSpacing ?? 6);
                const colShift = Math.round(root.dragX / w);
                const rowShift = Math.round(root.dragY / h);
                // Approximate as flat-list move by colShift + rowShift * columns.
                const columns = Config.options.sidebar.quickToggles.android.columns ?? 3;
                const offset = colShift + rowShift * columns;
                if (offset !== 0) movePositionBy(offset);
            }
            root.dragging = false;
            root.dragX = 0;
            root.dragY = 0;
            QuickToggleDragState.end();
            dragStarted = false;
        }
        onCanceled: {
            root.dragging = false;
            root.dragX = 0;
            root.dragY = 0;
            QuickToggleDragState.end();
            dragStarted = false;
        }
        onPressAndHold: (event) => {
            if (dragStarted) return;
            holdFired = true;
            if (root._hasHoldAction) {
                root._holdAction();
                return;
            }
            toggleSize();
        }
        onWheel: (event) => {
            if (event.angleDelta.y < 0) movePositionBy(1);
            else if (event.angleDelta.y > 0) movePositionBy(-1);
            event.accepted = true;
        }
    }

    // × overlay: in edit mode, only on tiles already placed in a tab. Matches the design's tonal palette.
    Rectangle {
        id: removeBtn
        visible: root.editMode && !root.inTray && !root.dragging
        opacity: 1
        anchors {
            top: parent.top; right: parent.right
            topMargin: -3; rightMargin: -3
        }
        z: 200
        width: 18; height: 18; radius: 9
        color: removeHov.hovered ? Appearance.colors.colPrimary : Appearance.colors.colLayer3
        Behavior on color { animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this) }
        HoverHandler { margin: Appearance.sizes.touchSlop; id: removeHov }
        TapHandler {
            margin: Appearance.sizes.touchSlop
            onTapped: {
                const list = root._activeList().slice();
                list.splice(root.buttonIndex, 1);
                root._writeActiveList(list);
            }
        }
        MaterialSymbol {
            anchors.fill: parent
            text: "close"
            iconSize: 12
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
            color: removeHov.hovered ? Appearance.colors.colOnPrimary : Appearance.colors.colOnLayer3
        }
    }

    StyledToolTip {
        extraVisibleCondition: root.tooltipText !== ""
        text: root.tooltipText
    }
}
