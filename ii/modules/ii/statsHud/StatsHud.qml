pragma ComponentBehavior: Bound
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland

/**
 * On-screen stats overlay — FPS, network, CPU/GPU/RAM, temperature.
 *
 * Click-through by design (`mask: Region {}`): this sits on top of whatever
 * you are doing, so it must never eat a click. It is also the reason the
 * settings live in a separate panel rather than on the overlay itself.
 *
 * Layouts are not cosmetic variants — each one trades space for detail:
 *   bar       one horizontal strip, for the top/bottom edge
 *   stack     vertical column, for a screen corner
 *   compact   FPS only, the smallest thing that is still useful in a game
 *   detailed  everything, with labels, for debugging
 */
Scope {
    id: root

    // All shared state and formatting lives in StatsHudBridge, so the
    // settings panel — a separate surface that cannot reach in here — works
    // from exactly the same definitions.
    readonly property var cfg: StatsHudBridge.cfg
    readonly property bool shown: GlobalStates.statsHudOpen

    // Drives the whole service. This was lost in a refactor and nothing
    // polled at all — every stat sat at zero, which looked like "the network
    // stat is broken" but was actually "nothing is being read".
    onShownChanged: {
        SysStats.active = root.shown;
        // Persist, so the overlay comes back by itself after a reload.
        if (Config.options.statsHud.enabled !== root.shown)
            Config.options.statsHud.enabled = root.shown;
    }
    Component.onCompleted: {
        // Restore the saved state on startup.
        if (Config.options.statsHud.enabled) GlobalStates.statsHudOpen = true;
        SysStats.active = root.shown;
    }

    // ── Fullscreen ──────────────────────────────────────────────────────
    // A fullscreen window covers the bar, but the bar's exclusive zone is
    // still reserved — so respecting it would leave the overlay floating in
    // dead space below a bar nobody can see. In fullscreen the overlay
    // ignores reservations and sits where the position setting actually says.
    readonly property bool anyFullscreen: {
        const ws = HyprlandData.activeWorkspace?.id;
        const wl = HyprlandData.windowList ?? [];
        for (let i = 0; i < wl.length; ++i) {
            const w = wl[i];
            if (w && w.workspace?.id === ws && w.fullscreen > 0) return true;
        }
        return false;
    }

    IpcHandler {
        target: "statsHud"
        function toggle(): void { GlobalStates.statsHudOpen = !GlobalStates.statsHudOpen }
        function open(): void   { GlobalStates.statsHudOpen = true }
        function close(): void  { GlobalStates.statsHudOpen = false }
        function edit(): void {
            GlobalStates.statsHudOpen = true;
            GlobalStates.statsHudEdit = !GlobalStates.statsHudEdit;
        }
    }

    // Placement is stored as CORNER + offset rather than absolute x/y: the
    // overlay then keeps its relationship to the nearest edge when the
    // resolution changes, instead of drifting into the middle of the screen.
    function commitPlacement(cx, cy, w, h, sw, sh) {
        const right = cx + w / 2 > sw / 2;
        const bottom = cy + h / 2 > sh / 2;
        const corner = (bottom ? "bottom" : "top") + "-" + (right ? "right" : "left");
        Config.options.statsHud.position = corner;
        // Never negative: a negative margin is a card parked off the edge of
        // the screen, which is exactly the state you cannot drag your way out
        // of. The drag already clamps; this stops a bad value being SAVED.
        Config.options.statsHud.marginX = Math.max(0, Math.round(right ? (sw - (cx + w)) : cx));
        Config.options.statsHud.marginY = Math.max(0, Math.round(bottom ? (sh - (cy + h)) : cy));
    }

    // Move the stat at `from` by however many slots `dx` pixels spans (avg =
    // one pill's width). Editing the order on a preset adopts it as custom.
    function reorderField(from, dx, avg) {
        const fields = StatsHudBridge.fields(Config.options.statsHud.layout).slice();
        if (fields.length < 2 || avg <= 0) return;
        const to = Math.max(0, Math.min(fields.length - 1, from + Math.round(dx / avg)));
        if (to === from) return;
        if (Config.options.statsHud.layout !== "custom")
            Config.options.statsHud.layout = "custom";
        const item = fields.splice(from, 1)[0];
        fields.splice(to, 0, item);
        Config.options.statsHud.fields = fields;
    }

    // Feed the fullscreen game's PID to SysStats so the "played" stat can time
    // it. Returns 0 while the overlay is hidden so SysStats stops reading it.
    Binding {
        target: SysStats
        property: "gamePid"
        value: {
            if (!root.shown) return 0;
            const ws = HyprlandData.activeWorkspace?.id;
            const wl = HyprlandData.windowList ?? [];
            for (let i = 0; i < wl.length; ++i) {
                const w = wl[i];
                if (w && w.workspace?.id === ws && w.fullscreen > 0) return w.pid ?? 0;
            }
            return 0;
        }
    }

    GlobalShortcut {
        name: "statsHudToggle"
        description: "Toggle the on-screen stats overlay"
        onPressed: GlobalStates.statsHudOpen = !GlobalStates.statsHudOpen
    }

    // ── Edit mode ───────────────────────────────────────────────────────
    // A separate, FULL-SCREEN interactive surface. The normal overlay is
    // click-through by design, so it cannot also be draggable — and a
    // full-screen surface is what makes edge snapping possible at all, since
    // the card needs room to move before it commits to a corner.
    Loader {
        active: root.shown && GlobalStates.statsHudEdit

        sourceComponent: PanelWindow {
            id: edit
            WlrLayershell.namespace: "quickshell:statsHudEdit"
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand
            // Same frame as the live overlay, so a position chosen while
            // dragging is the position you get.
            exclusiveZone: 0
            color: "transparent"
            anchors { top: true; bottom: true; left: true; right: true }

            readonly property int snap: Config.options.statsHud.snapPx ?? 26
            readonly property int gridSize: Math.max(6, Config.options.statsHud.gridSize ?? 20)
            // Every line the card can magnet to: the four edges, and the two
            // centre axes. Centres matter as much as edges — "centred at the
            // top" is a placement people actually want and cannot hit by hand.
            readonly property var snapX: [0, (width - ghost.width) / 2, width - ghost.width]
            readonly property var snapY: [0, (height - ghost.height) / 2, height - ghost.height]
            property int hitX: -1
            property int hitY: -1

            function magnet(v, targets, out) {
                let best = v, bestI = -1, bestD = edit.snap;
                for (let i = 0; i < targets.length; ++i) {
                    const d = Math.abs(v - targets[i]);
                    if (d < bestD) { bestD = d; best = targets[i]; bestI = i; }
                }
                if (out === "x") edit.hitX = bestI; else edit.hitY = bestI;
                return best;
            }

            // Dimmed backdrop so it is obvious the screen is in a mode.
            Rectangle {
                anchors.fill: parent
                color: Qt.alpha("#000000", 0.35)
                // Only the empty backdrop exits edit mode — a tap on the bar is
                // ignored here (so the bar no longer needs a grab-stealing tap
                // handler that would block the reorder/move drags).
                TapHandler {
                    onTapped: (ep) => {
                        const p = ghost.mapFromItem(null, ep.scenePosition.x, ep.scenePosition.y);
                        if (p.x >= 0 && p.x <= ghost.width && p.y >= 0 && p.y <= ghost.height) return;
                        GlobalStates.statsHudEdit = false;
                    }
                }
            }

            // dotted alignment grid — repaints when the grid size changes
            Canvas {
                id: gridCanvas
                anchors.fill: parent
                visible: Config.options.statsHud.showGrid ?? true
                renderStrategy: Canvas.Cooperative
                onPaint: {
                    const ctx = getContext("2d");
                    ctx.reset();
                    const g = edit.gridSize;
                    const dot = Qt.rgba(Appearance.colors.colPrimary.r,
                                        Appearance.colors.colPrimary.g,
                                        Appearance.colors.colPrimary.b, 1);
                    // Brighter, larger dots on the major (every 5th) lines so
                    // the grid reads as a grid, not TV static.
                    for (let x = g; x < width; x += g)
                        for (let y = g; y < height; y += g) {
                            const major = (Math.round(x / g) % 5 === 0)
                                       && (Math.round(y / g) % 5 === 0);
                            ctx.beginPath();
                            ctx.fillStyle = major
                                ? Qt.alpha(dot, 0.85) : Qt.alpha(dot, 0.35);
                            ctx.arc(x, y, major ? 1.8 : 1.0, 0, 2 * Math.PI);
                            ctx.fill();
                        }
                }
            }
            onGridSizeChanged: gridCanvas.requestPaint()

            // Window outlines — a placement reference. Screen coords minus the
            // edit surface's own offset (the reserved bar strip).
            property int winRounding: 18
            readonly property int offX: (HyprlandData.monitors[0]?.reserved?.[0]) ?? 0
            readonly property int offY: (HyprlandData.monitors[0]?.reserved?.[1]) ?? 0
            Process {
                running: true
                command: ["hyprctl", "getoption", "decoration:rounding", "-j"]
                stdout: StdioCollector {
                    onStreamFinished: { try { edit.winRounding = JSON.parse(text).int } catch (e) {} }
                }
            }
            Repeater {
                model: HyprlandData.windowList ?? []
                delegate: Rectangle {
                    required property var modelData
                    // Skip background windows occluded by a fullscreen app —
                    // outlining them makes a fullscreen game look "windowed".
                    visible: !root.anyFullscreen
                          && (modelData.workspace?.id === HyprlandData.activeWorkspace?.id)
                          && modelData.mapped && !modelData.hidden && modelData.fullscreen === 0
                    x: (modelData.at?.[0] ?? 0) - edit.offX
                    y: (modelData.at?.[1] ?? 0) - edit.offY
                    width: modelData.size?.[0] ?? 0
                    height: modelData.size?.[1] ?? 0
                    radius: edit.winRounding
                    color: "transparent"
                    border.width: 1
                    border.color: Qt.alpha(Appearance.colors.colPrimary, 0.3)
                }
            }

            // Snap guides, drawn only while a magnet is engaged.
            Rectangle {
                visible: edit.hitX >= 0 && drag.active
                x: edit.snapX[Math.max(0, edit.hitX)] + (edit.hitX === 1 ? ghost.width / 2 : 0)
                width: 1; height: parent.height
                color: Appearance.colors.colPrimary
                opacity: 0.7
            }
            Rectangle {
                visible: edit.hitY >= 0 && drag.active
                y: edit.snapY[Math.max(0, edit.hitY)] + (edit.hitY === 1 ? ghost.height / 2 : 0)
                height: 1; width: parent.width
                color: Appearance.colors.colPrimary
                opacity: 0.7
            }

            Rectangle {
                id: ghost
                readonly property var cfg: Config.options.statsHud
                readonly property bool atRight: String(cfg.position).endsWith("right")
                readonly property bool atBottom: String(cfg.position).startsWith("bottom")

                // sized to real content
                width: ghostContent.implicitWidth + 20
                height: ghostContent.implicitHeight + 12
                // not win.isDock — win is unloaded in edit mode
                radius: (ghost.cfg.mode === "dock") ? 0 : Appearance.rounding.small

                color: Qt.alpha("#0B0B0F", ghost.cfg.opacity ?? 0.55)
                border.width: 2
                border.color: Qt.alpha(Appearance.colors.colPrimary, drag.active ? 1.0 : 0.6)
                Behavior on border.color { ColorAnimation { duration: 140 } }

                // Seeded from the saved corner + offsets, then owned by the
                // drag. Not a binding: a binding would fight the DragHandler.
                //
                // Seeded on a REAL size, not in Component.onCompleted. A
                // layer-shell surface is configured asynchronously by the
                // compositor, so at onCompleted edit.width is still 0 — and
                // for a right-anchored card that made the seed
                // `0 - width - marginX`, i.e. most of a screen off the left
                // edge. The drag grip is the leftmost thing in the row, so it
                // went off-screen with it and the card became impossible to
                // grab: edit mode opened with the HUD stuck at the left edge
                // and no way to move it back.
                property bool seeded: false

                function clampIntoView() {
                    if (edit.width <= 0 || edit.height <= 0) return;
                    ghost.x = Math.max(0, Math.min(edit.width - ghost.width, ghost.x));
                    ghost.y = Math.max(0, Math.min(edit.height - ghost.height, ghost.y));
                }

                function seed() {
                    if (ghost.seeded) return;
                    // Both the surface AND the card have to have measured
                    // themselves, or the right/bottom maths is off by the
                    // card's own size.
                    if (edit.width <= 0 || edit.height <= 0) return;
                    if (ghost.width <= 0 || ghost.height <= 0) return;
                    ghost.seeded = true;
                    ghost.x = ghost.atRight
                        ? (edit.width - ghost.width - cfg.marginX) : cfg.marginX;
                    ghost.y = ghost.atBottom
                        ? (edit.height - ghost.height - cfg.marginY) : cfg.marginY;
                    ghost.clampIntoView();
                }

                Component.onCompleted: ghost.seed()
                onWidthChanged: ghost.seeded ? ghost.clampIntoView() : ghost.seed()
                onHeightChanged: ghost.seeded ? ghost.clampIntoView() : ghost.seed()
                Connections {
                    target: edit
                    function onWidthChanged()  { ghost.seeded ? ghost.clampIntoView() : ghost.seed() }
                    function onHeightChanged() { ghost.seeded ? ghost.clampIntoView() : ghost.seed() }
                }

                RowLayout {
                    id: ghostContent
                    anchors.centerIn: parent
                    spacing: 0

                    // Move handle — drag to reposition the whole bar. Kept on its
                    // own grip so it never fights the per-stat reorder drag for
                    // the same press. Delta-based (capture start, apply offset),
                    // so snap and clamp can override without stutter.
                    MaterialSymbol {
                        text: "drag_indicator"
                        iconSize: 17
                        color: Qt.alpha(Appearance.colors.colOnLayer0, drag.active ? 0.95 : 0.45)
                        Layout.rightMargin: 9
                        HoverHandler { cursorShape: Qt.SizeAllCursor }
                        DragHandler {
                            id: drag
                            target: null
                            property real ox: 0
                            property real oy: 0
                            property real sx: 0
                            property real sy: 0
                            onActiveChanged: {
                                if (active) {
                                    drag.ox = ghost.x; drag.oy = ghost.y;
                                    drag.sx = centroid.scenePosition.x;
                                    drag.sy = centroid.scenePosition.y;
                                    return;
                                }
                                edit.hitX = -1; edit.hitY = -1;
                                root.commitPlacement(ghost.x, ghost.y, ghost.width, ghost.height,
                                                     edit.width, edit.height);
                            }
                            onCentroidChanged: {
                                if (!active) return;
                                let nx = drag.ox + (centroid.scenePosition.x - drag.sx);
                                let ny = drag.oy + (centroid.scenePosition.y - drag.sy);
                                if (Config.options.statsHud.snapDots) {
                                    const g = edit.gridSize;
                                    nx = Math.round(nx / g) * g;
                                    ny = Math.round(ny / g) * g;
                                }
                                if (Config.options.statsHud.snapGrid) {
                                    nx = edit.magnet(nx, edit.snapX, "x");
                                    ny = edit.magnet(ny, edit.snapY, "y");
                                }
                                ghost.x = Math.max(0, Math.min(edit.width - ghost.width, nx));
                                ghost.y = Math.max(0, Math.min(edit.height - ghost.height, ny));
                            }
                        }
                    }

                    Repeater {
                        model: StatsHudBridge.fields(ghost.cfg.layout ?? "bar")
                        delegate: RowLayout {
                            id: gpill
                            required property var modelData
                            required property int index
                            readonly property var f: StatsHudBridge.statFor(modelData)
                            property real dragDX: 0
                            spacing: 0
                            z: pillDrag.active ? 5 : 0
                            opacity: pillDrag.active ? 0.85 : 1.0
                            transform: Translate { x: gpill.dragDX }
                            HoverHandler {
                                cursorShape: pillDrag.active ? Qt.ClosedHandCursor : Qt.OpenHandCursor
                            }
                            // Drag a stat sideways to change its order in the bar.
                            DragHandler {
                                id: pillDrag
                                target: null
                                yAxis.enabled: false
                                // Scene coords, not local: the pill carries its own
                                // Translate, so a LOCAL centroid is measured through
                                // that transform and fed back on itself — the drag
                                // never tracked. Scene position is transform-free.
                                property real sx: 0
                                onActiveChanged: {
                                    if (active) { pillDrag.sx = centroid.scenePosition.x; return; }
                                    const cnt = StatsHudBridge.fields(ghost.cfg.layout ?? "bar").length;
                                    root.reorderField(gpill.index, gpill.dragDX,
                                                      cnt > 0 ? ghostContent.width / cnt : 40);
                                    gpill.dragDX = 0;
                                }
                                onCentroidChanged: {
                                    if (pillDrag.active) gpill.dragDX = centroid.scenePosition.x - pillDrag.sx;
                                }
                            }
                            Rectangle {
                                visible: index > 0
                                implicitWidth: 1; implicitHeight: 13
                                Layout.leftMargin: 9; Layout.rightMargin: 9
                                color: Qt.alpha(Appearance.colors.colOnLayer0, 0.14)
                            }
                            MaterialSymbol {
                                visible: ghost.cfg.showIcons ?? true
                                text: f.icon; iconSize: 14
                                color: Qt.alpha(Appearance.colors.colPrimary, 0.85)
                                Layout.rightMargin: 5
                            }
                            StyledText {
                                text: f.value
                                font.family: Appearance.font.family.monospace
                                font.pixelSize: Appearance.font.pixelSize.smaller
                                font.bold: true
                                color: Appearance.colors.colOnLayer0
                            }
                        }
                    }
                }
            }

            // Bottom control bar — live grid settings while placing.
            Rectangle {
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.bottom: parent.bottom
                anchors.bottomMargin: 24
                // Consume taps so clicking the bar doesn't hit the backdrop's
                // tap-to-exit and drop you out of edit mode.
                TapHandler { gesturePolicy: TapHandler.WithinBounds }
                implicitWidth: 500
                implicitHeight: 52
                radius: Appearance.rounding.normal
                color: Appearance.colors.colLayer1
                border.width: 1
                border.color: Appearance.colors.colLayer0Border

                // Quick toggle for a Config bool, styled for the bottom bar.
                component BarToggle: MaterialSymbol {
                    property string key: ""
                    property bool def: false
                    iconSize: 19
                    readonly property bool on: Config.options.statsHud[key] ?? def
                    color: on ? Appearance.colors.colPrimary : Appearance.colors.colSubtext
                    HoverHandler { cursorShape: Qt.PointingHandCursor }
                    TapHandler { onTapped: Config.options.statsHud[parent.key] = !parent.on }
                    StyledToolTip { text: parent.key }
                }

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 14
                    anchors.rightMargin: 14
                    spacing: 12
                    BarToggle { text: "grid_4x4";        key: "showGrid"; def: true  }   // show grid
                    BarToggle { text: "grid_on";         key: "snapDots"; def: false }   // snap to dots
                    BarToggle { text: "border_outer";    key: "snapGrid"; def: true  }   // snap to edges/centre
                    BarToggle { text: "monitoring";      key: "showIcons"; def: true }   // show icons
                    Rectangle {
                        implicitWidth: 1; implicitHeight: 22
                        color: Qt.alpha(Appearance.colors.colOnLayer0, 0.15)
                    }
                    StyledSlider {
                        Layout.fillWidth: true
                        from: 7; to: 120
                        value: Config.options.statsHud.gridSize
                        onMoved: Config.options.statsHud.gridSize = Math.round(value)
                    }
                    StyledText {
                        Layout.minimumWidth: 42
                        horizontalAlignment: Text.AlignRight
                        text: Config.options.statsHud.gridSize + "px"
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        font.family: Appearance.font.family.monospace
                        color: Appearance.colors.colPrimary
                    }
                }
            }

            // Small hint, pinned opposite the card.
            Rectangle {
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.top: ghost.y < edit.height / 2 ? parent.top : undefined
                anchors.bottom: ghost.y < edit.height / 2 ? undefined : parent.bottom
                anchors.topMargin: 40
                anchors.bottomMargin: 90
                implicitWidth: hint.implicitWidth + 24
                implicitHeight: 30
                radius: 15
                color: Appearance.colors.colLayer1
                StyledText {
                    id: hint
                    anchors.centerIn: parent
                    text: "Drag to place · click the backdrop to finish"
                    font.pixelSize: Appearance.font.pixelSize.smallest
                    color: Appearance.colors.colOnLayer1
                }
            }
        }
    }

    Loader {
        // The live overlay hides while editing — the ghost stands in for it,
        // so you are not dragging next to a duplicate of the thing you move.
        active: root.shown && !GlobalStates.statsHudEdit

        sourceComponent: PanelWindow {
            id: win
            WlrLayershell.namespace: "quickshell:statsHud"
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
            // -1, not 0: with 0 the surface is placed inside the area left by
            // other exclusive-zone layers, so it would sit below the bar
            // instead of where the user asked for it.
            color: "transparent"
            // Only the visible bar takes input; the rest of the surface stays
            // click-through. Right-click a tag cycles its format. In collapsed
            // peek only the trigger strip is interactive (hover to reveal).
            mask: Region { item: (win.isPeek && !win.peeking) ? hoverZone : card }

            Item {
                id: hoverZone
                anchors.fill: parent
                HoverHandler {
                    id: peekHover
                    enabled: win.isPeek
                    onHoveredChanged: {
                        if (hovered) { collapseTimer.stop(); win.peeking = true; }
                        else collapseTimer.restart();
                    }
                }
                // A short grace period: without it, crossing a 5px strip makes
                // the card flicker open and shut.
                Timer {
                    id: collapseTimer
                    interval: 350
                    onTriggered: win.peeking = false
                }
            }

            readonly property string pos: root.cfg?.position ?? "top-right"
            readonly property string mode: Config.options.statsHud.mode ?? "always"
            readonly property bool isDock: mode === "dock"
            readonly property bool isPeek: mode === "peek"
            // Peek starts collapsed and expands while hovered. Kept here rather
            // than on the card so the WINDOW can resize too — a surface that
            // stayed card-sized would keep covering the screen while collapsed.
            property bool peeking: false

            anchors.top: pos.startsWith("top")
            anchors.bottom: pos.startsWith("bottom")
            // A dock spans its edge; a floating card only touches one corner.
            anchors.left: isDock || pos.endsWith("left")
            anchors.right: isDock || pos.endsWith("right")
            margins.top: root.cfg?.marginY ?? 8
            margins.bottom: root.cfg?.marginY ?? 8
            margins.left: root.cfg?.marginX ?? 8
            margins.right: root.cfg?.marginX ?? 8

            implicitWidth: isDock ? 0 : card.implicitWidth
            implicitHeight: (isPeek && !peeking)
                ? Math.max(3, Config.options.statsHud.peekSize)
                : card.implicitHeight
            Behavior on implicitHeight {
                NumberAnimation { duration: 160; easing.type: Easing.OutCubic }
            }
            // A dock may reserve space so windows tile around it instead of
            // being covered — the one case where an overlay should push back.
            // 0, not -1: -1 ignores every other layer's exclusive zone, which
            // put the overlay level with (or above) the bar. 0 makes the
            // compositor place it AFTER whatever the bar and any other
            // reserved strip take, so it always lands below a visible bar —
            // and follows automatically if the bar moves or is hidden.
            exclusiveZone: (isDock && Config.options.statsHud.dockReserve)
                ? card.implicitHeight
                : (root.anyFullscreen ? -1 : 0)

            Rectangle {
                id: card
                // Collapsed peek shows only a tinted sliver, so you can see
                // where to aim without the numbers being readable.
                opacity: (win.isPeek && !win.peeking) ? 0.0 : 1.0
                Behavior on opacity { NumberAnimation { duration: 140 } }
                readonly property string layout: root.cfg?.layout ?? "bar"
                readonly property bool vertical: layout === "stack" || layout === "detailed"
                readonly property var shownFields: StatsHudBridge.fields(card.layout)

                implicitWidth: win.isDock ? win.width : content.implicitWidth + 20
                implicitHeight: content.implicitHeight + 12
                // A dock is edge-to-edge, so rounding only its inner corners
                // reads as attached rather than as a floating bar that happens
                // to be wide.
                radius: win.isDock ? 0 : Appearance.rounding.small
                color: Qt.alpha("#0B0B0F", root.cfg?.opacity ?? 0.55)
                border.width: 1
                border.color: Qt.alpha(Appearance.colors.colOnLayer0, 0.12)

                GridLayout {
                    id: content
                    visible: !(win.isPeek && !win.peeking)
                    anchors.centerIn: parent
                    columns: card.vertical ? 1 : card.shownFields.length
                    rowSpacing: card.vertical ? 3 : 0
                    columnSpacing: 0

                    Repeater {
                        model: card.shownFields
                        delegate: RowLayout {
                            id: pill
                            required property var modelData
                            required property int index
                            readonly property var f: StatsHudBridge.statFor(modelData)
                            spacing: 0

                            // divider between stats
                            Rectangle {
                                visible: pill.index > 0 && !card.vertical
                                implicitWidth: 1
                                implicitHeight: 13
                                Layout.leftMargin: 9
                                Layout.rightMargin: 9
                                color: Qt.alpha(Appearance.colors.colOnLayer0, 0.14)
                            }

                            MaterialSymbol {
                                visible: root.cfg?.showIcons ?? true
                                text: f.icon
                                iconSize: 14
                                // Tinted toward the accent (dimmed) so the icons
                                // read as a set and the eye lands on the value.
                                color: f.warn ? Appearance.m3colors.m3error
                                     : Qt.alpha(Appearance.colors.colPrimary, 0.85)
                                Layout.rightMargin: 5
                            }
                            StyledText {
                                visible: card.layout === "detailed"
                                text: f.label
                                font.pixelSize: Appearance.font.pixelSize.smallest
                                color: Appearance.colors.colSubtext
                                Layout.rightMargin: 4
                            }
                            StyledText {
                                text: f.value
                                // Monospace digits: without it the whole row
                                // shifts every time a number changes width,
                                // which is very visible at 1Hz.
                                font.family: Appearance.font.family.monospace
                                font.pixelSize: Appearance.font.pixelSize.smaller
                                font.bold: true
                                color: f.warn ? Appearance.m3colors.m3error
                                              : Appearance.colors.colOnLayer0
                            }
                        }
                    }
                }

                // Right-click a tag to cycle its display format (e.g. GB↔%).
                MouseArea {
                    anchors.fill: content
                    visible: content.visible
                    acceptedButtons: Qt.RightButton
                    hoverEnabled: true
                    cursorShape: (hoveredField && StatsHudBridge.formats[hoveredField]?.length > 1)
                                 ? Qt.PointingHandCursor : Qt.ArrowCursor
                    property string hoveredField: {
                        const c = content.childAt(mouseX, mouseY);
                        return (c && c.modelData) ? String(c.modelData) : "";
                    }
                    onClicked: (mouse) => {
                        if (hoveredField) StatsHudBridge.cycleUnit(hoveredField);
                    }
                }
            }
        }
    }

}













