pragma ComponentBehavior: Bound
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import Qt5Compat.GraphicalEffects
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import Quickshell.Io

Item {
    id: root
    required property var screen
    readonly property HyprlandMonitor monitor: Hyprland.monitorFor(screen)
    readonly property var toplevels: ToplevelManager.toplevels
    readonly property var visibleWindows: ToplevelManager.toplevels.values.filter((toplevel) => {
        const address = `0x${toplevel.HyprlandToplevel?.address}`
        var win = windowByAddress[address]
        const inWorkspaceGroup = (root.workspaceGroup * root.workspacesShown < win?.workspace?.id && win?.workspace?.id <= (root.workspaceGroup + 1) * root.workspacesShown)
        return inWorkspaceGroup;
    })
    property int keyboardSelectedIndex: -1
    onVisibleWindowsChanged: {
        if (keyboardSelectedIndex >= visibleWindows.length) {
            keyboardSelectedIndex = visibleWindows.length - 1;
        }
    }

    readonly property int workspacesShown: Config.options.overview.rows * Config.options.overview.columns
    // The "real" group containing the currently focused workspace. Guarded:
    // a missing activeWorkspace (startup, monitor hotplug) would otherwise make
    // this NaN and poison every workspace number in the grid.
    readonly property int activeGroup: {
        const id = monitor?.activeWorkspace?.id ?? 1
        return Math.max(0, Math.floor((id - 1) / workspacesShown))
    }
    // The group being viewed, stored absolutely; -1 follows the active group.
    // An offset relative to activeGroup would slide the view a whole page
    // whenever the active workspace crossed a group boundary while open.
    property int viewGroup: -1
    // The group whose workspaces are currently rendered.
    readonly property int workspaceGroup: viewGroup >= 0 ? viewGroup : activeGroup
    readonly property bool viewingActiveGroup: workspaceGroup === activeGroup

    // Highest group holding real workspaces (or the active one). The pager may
    // walk one page past it, never further.
    readonly property int maxGroup: {
        let m = activeGroup
        const list = HyprlandData.workspaces ?? []
        for (let i = 0; i < list.length; i++) {
            const ws = list[i]
            if (ws && ws.id > 0)
                m = Math.max(m, Math.floor((ws.id - 1) / workspacesShown))
        }
        return m + 1
    }

    // Group indices that should be rendered as pills. We only show
    // groups that hold at least one known (non-empty) workspace, plus
    // whichever group is currently active or being viewed — so the
    // pager always reflects "real" places the user can land instead of
    // a long row of empty dots.
    readonly property var dotGroups: {
        const set = new Set()
        set.add(activeGroup)
        set.add(workspaceGroup)
        const list = HyprlandData.workspaces ?? []
        for (let i = 0; i < list.length; i++) {
            const ws = list[i]
            if (ws && ws.id > 0) {
                set.add(Math.floor((ws.id - 1) / workspacesShown))
            }
        }
        return Array.from(set).filter(g => g >= 0).sort((a, b) => a - b)
    }

    Connections {
        target: GlobalStates
        function onOverviewOpenChanged() {
            if (GlobalStates.overviewOpen) {
                root.viewGroup = -1
            } else {
                root.keyboardSelectedIndex = -1
            }
        }
    }

    /**
     * Step the viewed group by `direction` (±1). Snaps to the next/prev
     * non-empty group in dotGroups; if there isn't one in that direction,
     * walks one step into an adjacent empty group (clamped to 0..maxGroup).
     */
    function stepGroup(direction) {
        const list = root.dotGroups
        const cur = root.workspaceGroup
        const idx = list.indexOf(cur)
        let target = cur
        if (direction > 0) {
            target = (idx >= 0 && idx < list.length - 1)
                ? list[idx + 1]
                : (list.length > 0 ? list[list.length - 1] + 1 : cur + 1)
        } else if (direction < 0) {
            target = (idx > 0)
                ? list[idx - 1]
                : cur - 1
        }
        root.viewGroup = Math.max(0, Math.min(root.maxGroup, target))
    }
    property bool monitorIsFocused: (Hyprland.focusedMonitor?.name == monitor.name)
    property var windows: HyprlandData.windowList
    property var windowByAddress: HyprlandData.windowByAddress
    property var windowAddresses: HyprlandData.addresses
    property var monitorData: HyprlandData.monitors.find(m => m.id === root.monitor?.id)
    property real scale: Config.options.overview.scale
    property color activeBorderColor: Appearance.colors.colSecondary

    property real workspaceImplicitWidth: (monitorData?.transform % 2 === 1) ? 
        ((monitor.height - monitorData?.reserved[0] - monitorData?.reserved[2]) * root.scale / monitor.scale) :
        ((monitor.width - monitorData?.reserved[0] - monitorData?.reserved[2]) * root.scale / monitor.scale)
    property real workspaceImplicitHeight: (monitorData?.transform % 2 === 1) ? 
        ((monitor.width - monitorData?.reserved[1] - monitorData?.reserved[3]) * root.scale / monitor.scale) :
        ((monitor.height - monitorData?.reserved[1] - monitorData?.reserved[3]) * root.scale / monitor.scale)
    property real largeWorkspaceRadius: Appearance.rounding.large
    property real smallWorkspaceRadius: Appearance.rounding.verysmall

    property real workspaceNumberMargin: 80
    property real workspaceNumberSize: 250 * monitor.scale
    property int workspaceZ: 0
    property int windowZ: 1
    property int windowDraggingZ: 99999
    property real workspaceSpacing: 5

    property int draggingFromWorkspace: -1
    property int draggingTargetWorkspace: -1

    implicitWidth: overviewBackground.implicitWidth + Appearance.sizes.elevationMargin * 2
    implicitHeight: overviewBackground.implicitHeight + Appearance.sizes.elevationMargin * 2

    property Component windowComponent: OverviewWindow {}

    // One instance for the whole grid: a menu per tile would build dozens of
    // popup windows for something only one of them can show at a time.
    OverviewWindowMenu {
        id: windowMenu
        anchorItem: root
    }
    property list<OverviewWindow> windowWidgets: []
    
    function getWsRow(ws) {
        // 1-indexed workspace, 0-indexed row
        var normalRow = Math.floor((ws - 1) / Config.options.overview.columns) % Config.options.overview.rows;
        return (Config.options.overview.orderBottomUp ? Config.options.overview.rows - normalRow - 1 : normalRow);
    }
    function getWsColumn(ws) {
        // 1-indexed workspace, 0-indexed column
        var normalCol = (ws - 1) % Config.options.overview.columns;
        return (Config.options.overview.orderRightLeft ? Config.options.overview.columns - normalCol - 1 : normalCol);
    }
    function getWsInCell(ri, ci) {
        // 1-indexed workspace, 0-indexed row and column index
        return (Config.options.overview.orderBottomUp ? Config.options.overview.rows - ri - 1 : ri) * Config.options.overview.columns + (Config.options.overview.orderRightLeft ? Config.options.overview.columns - ci - 1 : ci) + 1
    }

    StyledRectangularShadow {
        target: overviewBackground
    }
    Rectangle { // Background
        id: overviewBackground
        property real padding: 10
        // Reserved bottom strip for the group-indicator pills.
        readonly property real pagerHeight: groupPager.implicitHeight + 8
        anchors.fill: parent
        anchors.margins: Appearance.sizes.elevationMargin

        implicitWidth: workspaceColumnLayout.implicitWidth + padding * 2
        implicitHeight: workspaceColumnLayout.implicitHeight + padding * 2 + pagerHeight
        radius: root.largeWorkspaceRadius + padding
        color: Appearance.colors.colBackgroundSurfaceContainer

        // Wheel / touchpad scroll → step between non-empty groups.
        // Accumulator throttles so a normal mouse wheel notch advances
        // exactly one group; high-resolution touchpads don't fly past.
        WheelHandler {
            target: null
            acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
            property real accum: 0
            onWheel: (event) => {
                accum += event.angleDelta.y
                while (accum >= 120)  { root.stepGroup(-1); accum -= 120 }
                while (accum <= -120) { root.stepGroup(+1); accum += 120 }
                event.accepted = true
            }
        }

        Column { // Workspaces
            id: workspaceColumnLayout

            z: root.workspaceZ
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.top: parent.top
            anchors.topMargin: parent.padding
            spacing: workspaceSpacing
            
            Repeater {
                model: Config.options.overview.rows
                delegate: Row {
                    id: row
                    required property int index
                    spacing: workspaceSpacing

                    Repeater { // Workspace repeater
                        model: Config.options.overview.columns
                        Rectangle { // Workspace
                            id: workspace
                            required property int index
                            property int colIndex: index
                            property int workspaceValue: root.workspaceGroup * root.workspacesShown + getWsInCell(row.index, colIndex)
                            property color defaultWorkspaceColor: Appearance.colors.colSurfaceContainerLow
                            property color hoveredWorkspaceColor: ColorUtils.mix(defaultWorkspaceColor, Appearance.colors.colLayer1Hover, 0.1)
                            property color hoveredBorderColor: Appearance.colors.colLayer2Hover
                            // Derived, not set by hand: the highlight can then
                            // never outlive the drag that caused it, whether or
                            // not DropArea gets to emit its exit.
                            readonly property bool hoveredWhileDragging: root.draggingFromWorkspace !== -1
                                && root.draggingTargetWorkspace === workspaceValue
                                && root.draggingFromWorkspace !== workspaceValue

                            function getContextMenuModel() {
                                const val = workspace.workspaceValue
                                const activeId = HyprlandData.activeWorkspace?.id ?? 1
                                const model = [
                                    { icon: "visibility", label: "Switch to Workspace", onTriggered: () => {
                                        GlobalFocusGrab.cancelRestore()
                                        GlobalStates.overviewOpen = false
                                        HyprDispatch.run("workspace " + val)
                                    }},
                                    { icon: "drive_file_move", label: "Move Active Window Here", onTriggered: () => {
                                        HyprDispatch.run("movetoworkspace " + val)
                                    }},
                                    { icon: "input", label: "Move Active Here (Silently)", onTriggered: () => {
                                        HyprDispatch.run("movetoworkspacesilent " + val)
                                    }},
                                    { separator: true },
                                    { icon: "arrow_upward", label: "Move All Windows to Active", onTriggered: () => {
                                        const cmds = [];
                                        HyprlandData.windowList.forEach(w => {
                                            if (w.workspace.id === val) {
                                                cmds.push("movetoworkspacesilent " + activeId + ", address:" + w.address);
                                            }
                                        });
                                        batchExecutor.startDetached(["hyprctl", "--batch", cmds.join(" ; ")]);
                                    }},
                                    { icon: "arrow_downward", label: "Move Active Windows Here", onTriggered: () => {
                                        const cmds = [];
                                        HyprlandData.windowList.forEach(w => {
                                            if (w.workspace.id === activeId) {
                                                cmds.push("movetoworkspacesilent " + val + ", address:" + w.address);
                                            }
                                        });
                                        batchExecutor.startDetached(["hyprctl", "--batch", cmds.join(" ; ")]);
                                    }},
                                    { separator: true },
                                    { icon: "grid_view", label: "Tile All Windows Here", onTriggered: () => {
                                        const cmds = [];
                                        HyprlandData.windowList.forEach(w => {
                                            if (w.workspace.id === val && w.floating) {
                                                cmds.push("togglefloating address:" + w.address);
                                            }
                                        });
                                        batchExecutor.startDetached(["hyprctl", "--batch", cmds.join(" ; ")]);
                                    }},
                                    { icon: "layers", label: "Float All Windows Here", onTriggered: () => {
                                        const cmds = [];
                                        HyprlandData.windowList.forEach(w => {
                                            if (w.workspace.id === val && !w.floating) {
                                                cmds.push("togglefloating address:" + w.address);
                                            }
                                        });
                                        batchExecutor.startDetached(["hyprctl", "--batch", cmds.join(" ; ")]);
                                    }},
                                    { icon: "push_pin", label: "Pin All Windows Here", onTriggered: () => {
                                        const cmds = [];
                                        HyprlandData.windowList.forEach(w => {
                                            if (w.workspace.id === val) {
                                                if (!w.floating) {
                                                    cmds.push("togglefloating address:" + w.address);
                                                }
                                                cmds.push("pin address:" + w.address);
                                            }
                                        });
                                        batchExecutor.startDetached(["hyprctl", "--batch", cmds.join(" ; ")]);
                                    }},
                                    { icon: "gavel", label: "Unpin All Windows Here", onTriggered: () => {
                                        const cmds = [];
                                        HyprlandData.windowList.forEach(w => {
                                            if (w.workspace.id === val && w.pinned) {
                                                cmds.push("pin address:" + w.address);
                                            }
                                        });
                                        batchExecutor.startDetached(["hyprctl", "--batch", cmds.join(" ; ")]);
                                    }}
                                ];

                                if (HyprlandData.monitors && HyprlandData.monitors.length > 0) {
                                    model.push({ separator: true });
                                    HyprlandData.monitors.forEach(mon => {
                                        model.push({
                                            icon: mon.focused ? "star" : "desktop_windows",
                                            label: "Move to " + mon.name + (mon.focused ? " (active)" : ""),
                                            onTriggered: () => {
                                                HyprDispatch.run("moveworkspacetomonitor " + val + " " + mon.name);
                                            }
                                        });
                                    });
                                }

                                model.push({ separator: true });
                                model.push({
                                    icon: "close",
                                    danger: true,
                                    label: "Close All Windows Here",
                                    onTriggered: () => {
                                        const cmds = [];
                                        HyprlandData.windowList.forEach(w => {
                                            if (w.workspace.id === val) {
                                                cmds.push("closewindow address:" + w.address);
                                            }
                                        });
                                        batchExecutor.startDetached(["hyprctl", "--batch", cmds.join(" ; ")]);
                                    }
                                });

                                return model;
                            }

                            implicitWidth: root.workspaceImplicitWidth
                            implicitHeight: root.workspaceImplicitHeight
                            color: hoveredWhileDragging ? hoveredWorkspaceColor : defaultWorkspaceColor
                            property bool workspaceAtLeft: colIndex === 0
                            property bool workspaceAtRight: colIndex === Config.options.overview.columns - 1
                            property bool workspaceAtTop: row.index === 0
                            property bool workspaceAtBottom: row.index === Config.options.overview.rows - 1
                            topLeftRadius: (workspaceAtLeft && workspaceAtTop) ? root.largeWorkspaceRadius : root.smallWorkspaceRadius
                            topRightRadius: (workspaceAtRight && workspaceAtTop) ? root.largeWorkspaceRadius : root.smallWorkspaceRadius
                            bottomLeftRadius: (workspaceAtLeft && workspaceAtBottom) ? root.largeWorkspaceRadius : root.smallWorkspaceRadius
                            bottomRightRadius: (workspaceAtRight && workspaceAtBottom) ? root.largeWorkspaceRadius : root.smallWorkspaceRadius
                            border.width: 2
                            border.color: hoveredWhileDragging ? hoveredBorderColor : "transparent"

                            StyledText {
                                anchors.centerIn: parent
                                text: workspace.workspaceValue
                                font {
                                    pixelSize: root.workspaceNumberSize * root.scale
                                    weight: Font.DemiBold
                                    family: Appearance.font.family.expressive
                                }
                                color: ColorUtils.transparentize(Appearance.colors.colOnLayer1, 0.8)
                                horizontalAlignment: Text.AlignHCenter
                                verticalAlignment: Text.AlignVCenter
                            }

                            MouseArea {
                                id: workspaceArea
                                anchors.fill: parent
                                acceptedButtons: Qt.LeftButton | Qt.RightButton
                                onPressed: (mouse) => {
                                    if (mouse.button === Qt.RightButton) {
                                        const globalPos = mapToItem(overviewBackground, mouse.x, mouse.y)
                                        workspaceContextMenu.popup(globalPos.x, globalPos.y, workspace.getContextMenuModel())
                                    }
                                }
                                // Switch on a released click, not on press — a bare press
                                // fired instantly, so a stray tap jumped workspaces.
                                onClicked: (mouse) => {
                                    if (mouse.button === Qt.LeftButton && root.draggingTargetWorkspace === -1) {
                                        GlobalFocusGrab.cancelRestore()
                                        GlobalStates.overviewOpen = false
                                        HyprDispatch.run(`workspace ${workspace.workspaceValue}`)
                                    }
                                }
                            }

                            DropArea {
                                anchors.fill: parent
                                onEntered: root.draggingTargetWorkspace = workspace.workspaceValue
                                onExited: {
                                    if (root.draggingTargetWorkspace === workspace.workspaceValue) root.draggingTargetWorkspace = -1
                                }
                            }

                        }
                    }
                }
            }
        }

        Item { // Windows & focused workspace indicator
            id: windowSpace
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.top: workspaceColumnLayout.top
            implicitWidth: workspaceColumnLayout.implicitWidth
            implicitHeight: workspaceColumnLayout.implicitHeight

            Repeater { // Window repeater
                model: ScriptModel {
                    values: root.visibleWindows
                }
                delegate: OverviewWindow {
                    id: window
                    required property var modelData
                    required property int index
                    keyboardSelected: index === root.keyboardSelectedIndex
                    property int monitorId: windowData?.monitor
                    property var monitor: HyprlandData.monitors.find(m => m.id == monitorId)
                    property var address: `0x${modelData.HyprlandToplevel.address}`
                    toplevel: modelData
                    monitorData: this.monitor
                    scale: root.scale
                    widgetMonitor: HyprlandData.monitors.find(m => m.id == root.monitor.id)
                    windowData: windowByAddress[address]

                    property bool atInitPosition: (initX == x && initY == y)

                    // Offset on the canvas
                    property int workspaceColIndex: getWsColumn(windowData?.workspace.id)
                    property int workspaceRowIndex: getWsRow(windowData?.workspace.id)
                    xOffset: (root.workspaceImplicitWidth + workspaceSpacing) * workspaceColIndex
                    yOffset: (root.workspaceImplicitHeight + workspaceSpacing) * workspaceRowIndex
                    property real xWithinWorkspaceWidget: Math.max((windowData?.at[0] - (monitor?.x ?? 0) - monitorData?.reserved[0]) * root.scale, 0)
                    property real yWithinWorkspaceWidget: Math.max((windowData?.at[1] - (monitor?.y ?? 0) - monitorData?.reserved[1]) * root.scale, 0)

                    // Radius
                    property real minRadius: Appearance.rounding.small
                    property bool workspaceAtLeft: workspaceColIndex === 0
                    property bool workspaceAtRight: workspaceColIndex === Config.options.overview.columns - 1
                    property bool workspaceAtTop: workspaceRowIndex === 0
                    property bool workspaceAtBottom: workspaceRowIndex === Config.options.overview.rows - 1
                    property bool workspaceAtTopLeft: (workspaceAtLeft && workspaceAtTop) 
                    property bool workspaceAtTopRight: (workspaceAtRight && workspaceAtTop) 
                    property bool workspaceAtBottomLeft: (workspaceAtLeft && workspaceAtBottom) 
                    property bool workspaceAtBottomRight: (workspaceAtRight && workspaceAtBottom) 
                    property real distanceFromLeftEdge: xWithinWorkspaceWidget
                    property real distanceFromRightEdge: root.workspaceImplicitWidth - (xWithinWorkspaceWidget + targetWindowWidth)
                    property real distanceFromTopEdge: yWithinWorkspaceWidget
                    property real distanceFromBottomEdge: root.workspaceImplicitHeight - (yWithinWorkspaceWidget + targetWindowHeight)
                    property real distanceFromTopLeftCorner: Math.max(distanceFromLeftEdge, distanceFromTopEdge)
                    property real distanceFromTopRightCorner: Math.max(distanceFromRightEdge, distanceFromTopEdge)
                    property real distanceFromBottomLeftCorner: Math.max(distanceFromLeftEdge, distanceFromBottomEdge)
                    property real distanceFromBottomRightCorner: Math.max(distanceFromRightEdge, distanceFromBottomEdge)
                    topLeftRadius: Math.max((workspaceAtTopLeft ? root.largeWorkspaceRadius : root.smallWorkspaceRadius) - distanceFromTopLeftCorner, minRadius)
                    topRightRadius: Math.max((workspaceAtTopRight ? root.largeWorkspaceRadius : root.smallWorkspaceRadius) - distanceFromTopRightCorner, minRadius)
                    bottomLeftRadius: Math.max((workspaceAtBottomLeft ? root.largeWorkspaceRadius : root.smallWorkspaceRadius) - distanceFromBottomLeftCorner, minRadius)
                    bottomRightRadius: Math.max((workspaceAtBottomRight ? root.largeWorkspaceRadius : root.smallWorkspaceRadius) - distanceFromBottomRightCorner, minRadius)

                    Timer {
                        id: updateWindowPosition
                        interval: Config.options.hacks.arbitraryRaceConditionDelay
                        repeat: false
                        running: false
                        onTriggered: {
                            window.x = Math.round(xWithinWorkspaceWidget + xOffset)
                            window.y = Math.round(yWithinWorkspaceWidget + yOffset)
                        }
                    }

                    // Smaller windows sit ABOVE larger ones, because each tile
                    // fills its own rect with a MouseArea: give two tiles the
                    // same z and a window that covers the workspace swallows
                    // every click meant for the ones beneath it. That is why a
                    // small window next to a maximised one could not be
                    // dragged or clicked at all.
                    readonly property real windowArea:
                        (windowData?.size[0] ?? 0) * (windowData?.size[1] ?? 0)
                    z: Drag.active ? root.windowDraggingZ
                        : root.windowZ
                          + (windowData?.floating ? 1000 : 0)
                          + Math.max(0, 900 - Math.round(windowArea / 10000))
                    Drag.hotSpot.x: width / 2
                    Drag.hotSpot.y: height / 2
                    MouseArea {
                        id: dragArea
                        anchors.fill: parent
                        hoverEnabled: true
                        onEntered: hovered = true // For hover color change
                        onExited: hovered = false // For hover color change
                        acceptedButtons: Qt.LeftButton | Qt.MiddleButton | Qt.RightButton
                        drag.target: parent
                        onPressed: (mouse) => {
                            if (mouse.button === Qt.RightButton) {
                                windowMenu.anchorItem = window
                                windowMenu.openFor(window.windowData)
                                mouse.accepted = true
                                return
                            }
                            root.draggingFromWorkspace = windowData?.workspace.id
                            window.pressed = true
                            window.Drag.active = true
                            window.Drag.source = window
                            window.Drag.hotSpot.x = mouse.x
                            window.Drag.hotSpot.y = mouse.y
                            // console.log(`[OverviewWindow] Dragging window ${windowData?.address} from position (${window.x}, ${window.y})`)
                        }
                        onReleased: {
                            const targetWorkspace = root.draggingTargetWorkspace
                            window.pressed = false
                            window.Drag.active = false
                            // Cleared here, up front — the tiled branch below
                            // returns early, and a target left set makes the
                            // workspace click handler ignore every later click.
                            root.draggingFromWorkspace = -1
                            root.draggingTargetWorkspace = -1
                            if (targetWorkspace !== -1 && targetWorkspace !== windowData?.workspace.id) {
                                HyprDispatch.run(`movetoworkspacesilent ${targetWorkspace}, address:${window.windowData?.address}`)
                                updateWindowPosition.restart()
                            }
                            else {
                                if (!window.windowData.floating) {
                                    updateWindowPosition.restart()
                                    return
                                }
                                // Canvas coords → absolute layout pixels: the exact
                                // inverse of xWithinWorkspaceWidget above, landing
                                // back in the same space windowData.at is given in.
                                // Percentages used to go out here, but Hyprland's
                                // Lua dispatcher takes pixels only and rejected the
                                // whole call, so a dragged window never moved.
                                const targetX = Math.round((window.x - xOffset) / root.scale
                                    + (monitor?.x ?? 0) + (monitor?.reserved?.[0] ?? 0))
                                const targetY = Math.round((window.y - yOffset) / root.scale
                                    + (monitor?.y ?? 0) + (monitor?.reserved?.[1] ?? 0))
                                HyprDispatch.run(`movewindowpixel exact ${targetX} ${targetY}, address:${window.windowData?.address}`)
                            }
                        }
                        onClicked: (event) => {
                            if (!windowData) return;

                            if (event.button === Qt.LeftButton) {
                                GlobalFocusGrab.cancelRestore()
                                GlobalStates.overviewOpen = false
                                HyprDispatch.run(`focuswindow address:${windowData.address}`)
                                event.accepted = true
                            } else if (event.button === Qt.MiddleButton) {
                                HyprDispatch.run(`closewindow address:${windowData.address}`)
                                event.accepted = true
                            }
                        }

                        StyledToolTip {
                            extraVisibleCondition: false
                            alternativeVisibleCondition: dragArea.containsMouse && !window.Drag.active
                            text: `${windowData?.title}\n[${windowData?.class}] ${windowData?.xwayland ? "[XWayland] " : ""}`
                        }
                    }
                }
            }

            Rectangle { // Focused workspace indicator
                id: focusedWorkspaceIndicator
                // Only meaningful while viewing the active group; the
                // index would otherwise point at the wrong cell.
                visible: root.viewingActiveGroup
                property int rowIndex: getWsRow(monitor.activeWorkspace?.id)
                property int colIndex: getWsColumn(monitor.activeWorkspace?.id)
                x: (root.workspaceImplicitWidth + workspaceSpacing) * colIndex
                y: (root.workspaceImplicitHeight + workspaceSpacing) * rowIndex
                z: root.windowZ
                width: root.workspaceImplicitWidth
                height: root.workspaceImplicitHeight
                color: "transparent"
                property bool workspaceAtLeft: colIndex === 0
                property bool workspaceAtRight: colIndex === Config.options.overview.columns - 1
                property bool workspaceAtTop: rowIndex === 0
                property bool workspaceAtBottom: rowIndex === Config.options.overview.rows - 1
                topLeftRadius: (workspaceAtLeft && workspaceAtTop) ? root.largeWorkspaceRadius : root.smallWorkspaceRadius
                topRightRadius: (workspaceAtRight && workspaceAtTop) ? root.largeWorkspaceRadius : root.smallWorkspaceRadius
                bottomLeftRadius: (workspaceAtLeft && workspaceAtBottom) ? root.largeWorkspaceRadius : root.smallWorkspaceRadius
                bottomRightRadius: (workspaceAtRight && workspaceAtBottom) ? root.largeWorkspaceRadius : root.smallWorkspaceRadius
                border.width: 2
                border.color: root.activeBorderColor
                Behavior on x {
                    animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                }
                Behavior on y {
                    animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                }
                Behavior on topLeftRadius {
                    animation: Appearance.animation.elementMoveEnter.numberAnimation.createObject(this)
                }
                Behavior on topRightRadius {
                    animation: Appearance.animation.elementMoveEnter.numberAnimation.createObject(this)
                }
                Behavior on bottomLeftRadius {
                    animation: Appearance.animation.elementMoveEnter.numberAnimation.createObject(this)
                }
                Behavior on bottomRightRadius {
                    animation: Appearance.animation.elementMoveEnter.numberAnimation.createObject(this)
                }
            }
        }

        // ── Group indicator pills ──────────────────────────────────────
        // A row of small shapes under the workspace grid. The currently
        // viewed group is a wider pill in the primary color; the other
        // groups are dots. The active workspace's group additionally
        // shows an outline so you can see "where you actually are" while
        // paging. Tap any shape to view that group.
        Row {
            id: groupPager
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: parent.bottom
            anchors.bottomMargin: parent.padding - 2
            spacing: 6
            z: 10

            Repeater {
                model: root.dotGroups
                delegate: Item {
                    required property int modelData    // group index
                    readonly property int groupIndex: modelData
                    readonly property bool isViewed: groupIndex === root.workspaceGroup
                    readonly property bool isActive: groupIndex === root.activeGroup

                    implicitWidth: isViewed ? 18 : 8
                    implicitHeight: 8
                    Behavior on implicitWidth {
                        NumberAnimation { duration: 160; easing.type: Easing.OutCubic }
                    }

                    Rectangle {
                        anchors.fill: parent
                        radius: height / 2
                        color: parent.isViewed
                            ? Appearance.colors.colPrimary
                            : (dotHov.hovered
                                ? Appearance.colors.colLayer2Hover
                                : Appearance.colors.colLayer2)
                        border.width: parent.isActive && !parent.isViewed ? 1 : 0
                        border.color: Appearance.colors.colPrimary
                        opacity: parent.isViewed ? 1 : 0.7
                        Behavior on color { ColorAnimation { duration: 130 } }

                        HoverHandler { id: dotHov }
                        TapHandler {
                            onTapped: root.viewGroup = parent.parent.groupIndex
                        }
                    }
                }
            }
        }
    }

    Process {
        id: batchExecutor
    }

    PopupContextMenu {
        id: workspaceContextMenu
    }
}

