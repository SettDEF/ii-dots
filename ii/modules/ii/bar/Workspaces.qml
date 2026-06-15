import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import Quickshell.Widgets
import Quickshell.Io
import Qt5Compat.GraphicalEffects

Item {
    id: root
    property bool vertical: false
    property bool borderless: Config.options.bar.borderless
    property int widgetPadding: 0 // kept for BarContent.qml compatibility

    readonly property HyprlandMonitor monitor: Hyprland.monitorFor(root.QsWindow.window?.screen)
    readonly property Toplevel activeWindow: ToplevelManager.activeToplevel

    // ── Slot list ────────────────────────────────────────────────────────────
    // The bar shows the standard 1–10 group (anchored to the lowest
    // existing workspace's group), PLUS any extra existing workspace
    // outside that group as additional trailing slots — so a "special"
    // workspace like ws 61 on the other monitor is always reachable
    // from either bar without yanking ws 1–3 out of view when focus
    // follows the mouse across monitors.
    readonly property int focusedWsId: Hyprland.focusedWorkspace?.id ?? monitor?.activeWorkspace?.id ?? 1
    readonly property int workspacesPerGroup: 10
    readonly property int _anchorWsId: {
        let lo = -1
        const v = Hyprland.workspaces.values
        for (let i = 0; i < v.length; i++) {
            const id = v[i]?.id ?? 0
            if (id > 0 && (lo < 0 || id < lo)) lo = id
        }
        return lo > 0 ? lo : 1
    }
    readonly property int currentGroup: Math.floor((_anchorWsId - 1) / workspacesPerGroup)
    readonly property int groupStart: currentGroup * workspacesPerGroup + 1

    // Sorted array of workspace ids the bar should render slots for.
    // It contains the standard contiguous group plus any out-of-group
    // existing workspaces (e.g. ws 61). Recomputes only when the
    // workspace list changes.
    readonly property var slotWsIds: {
        const ids = []
        for (let i = 0; i < workspacesPerGroup; i++) ids.push(groupStart + i)
        const v = Hyprland.workspaces.values
        for (let i = 0; i < v.length; i++) {
            const id = v[i]?.id ?? 0
            if (id > 0 && (id < groupStart || id >= groupStart + workspacesPerGroup))
                ids.push(id)
        }
        ids.sort((a, b) => a - b)
        return ids
    }
    readonly property int slotCount: slotWsIds.length

    // Index of the currently-focused workspace within slotWsIds, or -1
    // if it isn't shown (shouldn't happen now we always include it).
    readonly property int activeIdxInGroup: slotWsIds.indexOf(focusedWsId)

    // ── Workspace data arrays ─────────────────────────────────────────────────
    property var workspaceOccupied: []
    property var workspaceNames: []
    property var workspaceWindowCounts: []

    function updateWorkspaceData() {
        let occ = [], names = [], counts = []
        const ids = slotWsIds
        for (let i = 0; i < ids.length; i++) {
            const wsId = ids[i]
            const ws = Hyprland.workspaces.values.find(w => w.id === wsId)
            occ.push(!!ws)
            names.push(ws ? (ws.name ?? "") : "")
            counts.push(ws ? (ws.windows ?? 0) : 0)
        }
        workspaceOccupied = occ
        workspaceNames = names
        workspaceWindowCounts = counts
    }

    Connections {
        target: Hyprland.workspaces
        function onValuesChanged() { root.updateWorkspaceData() }
    }
    Connections {
        target: Hyprland
        function onFocusedWorkspaceChanged() {
            root.updateWorkspaceData()
            root.switchFlashActive = true
            switchFlashTimer.restart()
        }
    }
    onCurrentGroupChanged: updateWorkspaceData()

    // ── Hover ─────────────────────────────────────────────────────────────────
    property bool isHovered: false

    // ── Recording detection ───────────────────────────────────────────────────
    property bool micRecording: false
    property bool screenRecording: false
    readonly property bool isRecording: micRecording || screenRecording
    // Debounce counters — require 2 consecutive positives to avoid false flickers
    property int _micPositiveCount: 0
    property int _screenPositiveCount: 0

    Process {
        id: micCheckProc
        stdout: StdioCollector {
            onStreamFinished: {
                const active = parseInt(text.trim()) > 0
                if (active) {
                    root._micPositiveCount = Math.min(root._micPositiveCount + 1, 2)
                } else {
                    root._micPositiveCount = 0
                }
                root.micRecording = root._micPositiveCount >= 2
            }
        }
    }

    Process {
        id: screenRecordProc
        stdout: StdioCollector {
            onStreamFinished: {
                const active = text.trim() !== ""
                if (active) {
                    root._screenPositiveCount = Math.min(root._screenPositiveCount + 1, 2)
                } else {
                    root._screenPositiveCount = 0
                }
                root.screenRecording = root._screenPositiveCount >= 2
            }
        }
    }

    Timer {
        interval: 3000
        running: true
        repeat: true
        onTriggered: {
            micCheckProc.exec({ command: ["bash", "-c", "pactl list source-outputs | awk 'BEGIN{RS=\"Source Output\"} /Corked: no/ && !/MiniMeters/' | wc -l"] })
            screenRecordProc.exec({ command: ["bash", "-c", "pgrep -x wf-recorder"] })
        }
    }

    // ── Roman numeral flash ───────────────────────────────────────────────────
    readonly property var romanNumerals: ["I","II","III","IV","V","VI","VII","VIII","IX","X"]
    property bool showNumerals: false
    property bool switchFlashActive: false

    Timer {
        id: periodicFlashTimer
        interval: 9000
        running: true
        repeat: true
        onTriggered: {
            root.showNumerals = true
            numeralHideTimer.restart()
        }
    }
    Timer {
        id: numeralHideTimer
        interval: 1000
        repeat: false
        onTriggered: root.showNumerals = false
    }
    Timer {
        id: switchFlashTimer
        interval: 1000
        repeat: false
        onTriggered: root.switchFlashActive = false
    }

    // ── Context slot (media / notification) ──────────────────────────────────
    readonly property string _currentTrack: MprisController.activePlayer?.trackTitle ?? ""
    property bool _trackJustChanged: false
    property bool _scrolledOnce: false   // true after marquee has done one full pass
    readonly property bool _nearEnd: {
        const p = MprisController.activePlayer
        return p && p.length > 0 && (p.length - p.position) < 20
    }
    // After the title finishes its 4 s show, the wavy progress line takes
    // over for 2 s — then we collapse to the bare icon.
    property bool _wavyShowing: false
    on_CurrentTrackChanged: {
        if (_currentTrack.length > 0) {
            _trackJustChanged = true
            _scrolledOnce = false
            _trackShowTimer.restart()
            _wavyShowTimer.stop()
            _wavyShowing = false
        }
    }
    Timer {
        id: _trackShowTimer
        interval: 4000
        repeat: false
        onTriggered: {
            if (root._nearEnd) return
            root._trackJustChanged = false
            // Title just disappeared → flash the wavy progress for 2 s.
            root._wavyShowing = true
            _wavyShowTimer.restart()
        }
    }
    Timer {
        id: _wavyShowTimer
        interval: 2000
        repeat: false
        onTriggered: root._wavyShowing = false
    }
    // Called by the marquee animation when one full pass completes
    function onScrollPassDone() {
        _scrolledOnce = true
        // Only hide early if the 6s haven't elapsed yet — timer handles it otherwise
    }

    // Hysteresis on the context-slot hover so cursor jitter doesn't
    // flip width/state between media-controls (120 px) and media-collapsed
    // (28 px) on every mouse move. Stays in "controls" for 90 ms after
    // the cursor actually leaves the probe.
    property bool _ctxHoverSticky: false
    Connections {
        target: ctxSlotHover
        function onHoveredChanged() {
            if (ctxSlotHover.hovered) {
                root._ctxHoverSticky = true
                ctxHoverHold.stop()
                // Hovering kills the lingering "just-changed" title +
                // wavy stages so they don't pop back in after the cursor
                // leaves — the user has clearly seen the track already.
                root._trackJustChanged = false
                root._wavyShowing = false
                _trackShowTimer.stop()
                _wavyShowTimer.stop()
            } else {
                ctxHoverHold.restart()
            }
        }
    }
    Timer {
        id: ctxHoverHold
        interval: 90
        repeat: false
        onTriggered: root._ctxHoverSticky = false
    }

    property string contextMode: {
        if (Notifications.popupList.length > 0 && !Notifications.popupInhibited) return "notification"
        if (_currentTrack.length > 0 && _ctxHoverSticky) return "media-controls"
        if (_currentTrack.length > 0 && (_trackJustChanged || _nearEnd)) return "media-expanded"
        if (_currentTrack.length > 0 && _wavyShowing) return "media-wavy"
        if (_currentTrack.length > 0) return "media-collapsed"
        return "none"
    }
    property var contextNotif: Notifications.popupList.length > 0 ? Notifications.popupList[0] : null

    readonly property color playerAccent: PlayerService.accentForPlayer(MprisController.activePlayer)
    readonly property bool isYoutubeMusic: {
        const de = (MprisController.activePlayer?.desktopEntry ?? "").toLowerCase()
        return de.includes("youtube") || de.includes("ytmusic")
    }
    readonly property color ytmAccent: playerAccent

    // ── Sizing constants ──────────────────────────────────────────────────────
    readonly property real btnW:           28   // workspace slot width
    readonly property real padH:            6   // island horizontal padding
    readonly property real indMargin:       2   // active indicator inset
    readonly property real recW:           58   // recording indicator width

    // ── Slot / active-indicator shape ──────────────────────────────────────
    // Driven by Config.options.bar.workspaces.shape. Centralised here so the
    // occupied-chip radius and the SineCookie's geometry stay in lockstep.
    readonly property string slotShape: Config.options?.bar.workspaces.shape ?? "cookie"
    readonly property real slotRadius: {
        switch (slotShape) {
            case "square":  return 2
            case "rounded": return 6
            case "pill":
            case "hexagon":
            case "cookie":
            default:        return Appearance.rounding.full
        }
    }
    readonly property int  cookieSides: {
        switch (slotShape) {
            case "hexagon": return 6
            case "pill":    return 32                // many sides → smooth circle
            case "square":
            case "rounded": return 4                 // diamond / squircle
            case "cookie":
            default:        return 4
        }
    }
    readonly property real cookieAmpDivisor: {
        switch (slotShape) {
            case "pill":    return 9999              // ~0 amplitude = perfect circle
            case "square":  return 4                 // pointy diamond
            case "rounded": return 28                // soft squircle
            case "hexagon": return 60
            case "cookie":
            default:        return 80
        }
    }
    // mediaCircle is 22 wide. With it anchored.left inside a 24-wide
    // slot, the inside-right gap is 2 px (= workspace indMargin), so
    // visible-right = 2 + padH = 8 == visible-left of first workspace
    // (padH + indMargin = 8).
    readonly property real ctxCollapsedW: 24
    readonly property real ctxExpandedW:  27 + Math.min(ctxTextMeasure.implicitWidth, 180) + 8
    readonly property real ctxTotalW: {
        if (contextMode === "none") return 0
        if (contextMode === "media-collapsed") return ctxCollapsedW
        if (contextMode === "media-wavy")     return 120
        if (contextMode === "media-controls") return 120
        return ctxExpandedW
    }

    // Hidden text measurer for dynamic context slot width
    Text {
        id: ctxTextMeasure
        visible: false
        font.pixelSize: Appearance.font.pixelSize.small
        text: contextMode === "notification"
            ? (contextNotif?.summary ?? "")
            : MprisController.activePlayer?.trackTitle ?? ""
    }
    property int visibleSlotCount: {
        let n = 0
        for (let i = 0; i < slotCount; i++) {
            if ((workspaceOccupied[i] ?? false) || i === activeIdxInGroup) n++
        }
        return Math.max(1, n)
    }

    // No longer relevant — every existing workspace has its own slot.
    readonly property bool hasOtherGroups: false

    readonly property real slotsWidth:     (isHovered ? slotCount : visibleSlotCount) * btnW
    readonly property real recordingExtra: isRecording ? recW : 0

    // Layout: [padH][slots][2px+ctx?][padH]
    // padH * 2 supplies one padH on each side of the island. ctx hugs
    // the slots with a 2 px gap; no extra trailing padding beyond the
    // base padH on the right.
    implicitWidth:  slotsWidth + padH * 2 + recordingExtra + (ctxTotalW > 0 ? ctxTotalW + 2 : 0)
    implicitHeight: Appearance.sizes.barHeight

    Behavior on implicitWidth {
        // Must match contextSlot's `Behavior on width` (300 ms) — when
        // the durations differ, the inner slot's edge briefly outruns
        // the island background, producing the "rectangle wobble".
        NumberAnimation { duration: 300; easing.type: Easing.OutCubic }
    }

    // ── Input handlers ────────────────────────────────────────────────────────
    // Scroll-to-switch with delta accumulation. A touchpad emits a
    // continuous stream of tiny wheel deltas — firing `workspace r±1`
    // per event machine-guns through workspaces (and `r±1` wraps, so it
    // loops forever). Accumulate until a full notch (120) is crossed,
    // and gate with a cooldown so a fast fling can't burst-switch.
    WheelHandler {
        id: wsWheel
        property real accum: 0
        readonly property real notch: 120
        acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
        onWheel: event => {
            if (wsWheelCooldown.running) return
            accum += event.angleDelta.y !== 0
                ? event.angleDelta.y
                : event.pixelDelta.y * 4
            if (accum <= -notch) {
                Hyprland.dispatch("workspace r+1")
                accum = 0
                wsWheelCooldown.restart()
            } else if (accum >= notch) {
                Hyprland.dispatch("workspace r-1")
                accum = 0
                wsWheelCooldown.restart()
            }
        }
    }
    Timer {
        id: wsWheelCooldown
        interval: 180
        repeat: false
        onTriggered: wsWheel.accum = 0  // drop leftover fling delta
    }
    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.BackButton
        onPressed: event => {
            if (event.button === Qt.BackButton)
                Hyprland.dispatch("togglespecialworkspace")
        }
    }

    // ── Island background ─────────────────────────────────────────────────────
    Rectangle {
        id: islandBg
        anchors { fill: parent; topMargin: 4; bottomMargin: 4 }
        radius: Appearance.rounding.full
        color: Appearance.colors.colLayer1
        border.width: 1
        border.color: Appearance.colors.colLayer0Border

        HoverHandler {
            onHoveredChanged: root.isHovered = hovered
        }

        // YouTube Music tint overlay — darkened accent on the right portion
        Rectangle {
            anchors { right: parent.right; top: parent.top; bottom: parent.bottom }
            width: root.ctxTotalW > 0 ? root.ctxTotalW + root.padH : 0
            radius: parent.radius
            color: root.ytmAccent
            opacity: root.isYoutubeMusic && root.contextMode !== "none" ? 0.18 : 0
            Behavior on opacity { NumberAnimation { duration: 400 } }
            Behavior on width   { NumberAnimation { duration: 300; easing.type: Easing.OutCubic } }
        }
    }

    // Stable hover probe — sits as a SIBLING of contextSlot (no clip).
    // Its 120 px hit area keeps the slot in "media-controls" mode even
    // while contextSlot is animating between 28 px and 120 px.
    Item {
        id: ctxHoverProbe
        anchors {
            left: slotsRow.right
            leftMargin: 2
            verticalCenter: parent.verticalCenter
        }
        width: 120
        height: islandBg.height
        visible: root.contextMode !== "none"
        z: 5
        HoverHandler { id: ctxSlotHover }
    }

    // ── Context slot: right side of island ───────────────────────────────────
    Item {
        id: contextSlot
        // Tight gap to slotsRow — the workspace circles already have
        // their own internal padding so an extra 6 px island-pad here
        // doubled up visually. Drop to 2 px so the media icon sits
        // right after the last workspace pill.
        anchors { left: slotsRow.right; leftMargin: 2; verticalCenter: parent.verticalCenter }
        width: root.ctxTotalW
        height: islandBg.height
        clip: true
        Behavior on width { NumberAnimation { duration: 300; easing.type: Easing.OutCubic } }

        // Hover probe lives OUTSIDE the clipped contextSlot so its full
        // 120 px width keeps receiving hover events even when the slot
        // visually shrinks to 28 px. Putting it inside the clipped slot
        // made the effective hit-area equal the (animating) slot width,
        // so moving the cursor toward the buttons dropped the hover and
        // collapsed the slot.

        // Media icon circle — icon and accent follow PlayerService's
        // "context player" (whichever player is currently audible). When the
        // active player is muted, falls through to muted icon.
        Rectangle {
            id: mediaCircle
            readonly property var ctxPlayer: PlayerService.contextPlayer
            readonly property color ctxAccent: PlayerService.accentForPlayer(ctxPlayer) || root.playerAccent
            // Always anchored left. In media-wavy / media-controls the
            // content fills out to the right; in media-collapsed the
            // collapsed-slot width (ctxCollapsedW) is sized so 22-wide
            // circle + 2 px inset on each side = symmetric trailing gap.
            anchors { left: parent.left; verticalCenter: parent.verticalCenter }
            width: 22; height: 22; radius: 11
            color: ColorUtils.transparentize(ctxAccent, 0.5)
            Behavior on color { animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this) }
            opacity: root.contextMode.startsWith("media-") ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: 180 } }
            visible: opacity > 0

            // Material Symbol fallback (most players)
            MaterialSymbol {
                anchors.centerIn: parent
                visible: !PlayerService.contextIsYoutubeMusic || PlayerService.contextMuted
                text: PlayerService.contextIcon
                iconSize: Appearance.font.pixelSize.normal
                color: PlayerService.contextMuted
                    ? Appearance.colors.colSubtext
                    : mediaCircle.ctxAccent
                Behavior on color { animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this) }
            }
            // YouTube Music — custom SVG, recolored to accent
            CustomIcon {
                anchors.centerIn: parent
                width: 16; height: 16
                visible: PlayerService.contextIsYoutubeMusic && !PlayerService.contextMuted
                source: "youtube-music-symbolic.svg"
                colorize: true
                color: mediaCircle.ctxAccent
            }

            TapHandler {
                onTapped: GlobalStates.cornerPopupOpen = !GlobalStates.cornerPopupOpen
            }

            HoverHandler { id: mediaCircleHover }
            Rectangle {
                anchors.fill: parent; radius: parent.radius
                color: "white"
                opacity: mediaCircleHover.hovered ? 0.12 : 0
                Behavior on opacity { NumberAnimation { duration: 120 } }
            }
        }

        // Notification icon circle
        Rectangle {
            id: notifCircle
            anchors { left: parent.left; verticalCenter: parent.verticalCenter }
            width: 22; height: 22; radius: 11
            color: ColorUtils.transparentize(Appearance.m3colors.m3error, 0.7)
            opacity: root.contextMode === "notification" ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: 180 } }
            visible: opacity > 0

            MaterialSymbol {
                anchors.centerIn: parent
                text: "notifications"
                iconSize: Appearance.font.pixelSize.small
                color: Appearance.m3colors.m3error
            }
        }

        // Wavy progress line — flashes for 2 s after the title disappears,
        // visualising playback position with a lively wobble.
        Item {
            id: mediaWavyBar
            anchors {
                left: parent.left; leftMargin: 27
                right: parent.right; rightMargin: 6
                verticalCenter: parent.verticalCenter
            }
            height: 12
            opacity: root.contextMode === "media-wavy" ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: 180 } }
            visible: opacity > 0

            // Inactive (un-played) backing line, also wavy but dim.
            WavyLine {
                anchors.fill: parent
                color: Qt.alpha(Appearance.colors.colOnLayer1, 0.18)
                lineWidth: 2
                amplitudeMultiplier: 0.8
                frequency: 8
            }
            // Played portion — full accent, animates the wave.
            WavyLine {
                id: wavyPlayed
                anchors {
                    left: parent.left; verticalCenter: parent.verticalCenter
                }
                height: parent.height
                fullLength: parent.width
                color: root.playerAccent
                lineWidth: 2.5
                amplitudeMultiplier: 1.2
                frequency: 8
                width: {
                    const p = MprisController.activePlayer
                    if (!p || p.length <= 0) return 0
                    return parent.width * Math.min(p.position / p.length, 1)
                }
                Behavior on width { NumberAnimation { duration: 1000; easing.type: Easing.Linear } }
                FrameAnimation {
                    running: mediaWavyBar.visible
                    onTriggered: wavyPlayed.requestPaint()
                }
            }
        }

        // Hover controls — replaces the wavy line on hover.
        RowLayout {
            id: mediaControls
            anchors {
                left: parent.left; leftMargin: 27
                right: parent.right; rightMargin: 6
                verticalCenter: parent.verticalCenter
            }
            spacing: 0
            opacity: root.contextMode === "media-controls" ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: 140 } }
            visible: opacity > 0

            Repeater {
                model: [
                    { sym: "skip_previous", fn: () => MprisController.previous(),  show: () => MprisController.canGoPrevious },
                    { sym: MprisController.isPlaying ? "pause" : "play_arrow",
                                            fn: () => MprisController.togglePlaying(), show: () => true },
                    { sym: "skip_next",     fn: () => MprisController.next(),      show: () => MprisController.canGoNext },
                ]
                delegate: Rectangle {
                    required property var modelData
                    Layout.alignment: Qt.AlignVCenter
                    Layout.fillWidth: true
                    Layout.preferredHeight: 18
                    radius: 9
                    color: btnHov.hovered
                        ? Qt.alpha(root.playerAccent, 0.22)
                        : "transparent"
                    Behavior on color { ColorAnimation { duration: 120 } }
                    visible: modelData.show()
                    HoverHandler { id: btnHov }
                    TapHandler   { onTapped: modelData.fn() }
                    MaterialSymbol {
                        anchors.centerIn: parent
                        text: modelData.sym
                        iconSize: 14
                        fill: btnHov.hovered ? 1 : 0
                        color: root.playerAccent
                    }
                }
            }
        }

        // Media title text (first 4s and last 20s)
        StyledText {
            anchors {
                left: parent.left; leftMargin: 27
                right: parent.right; rightMargin: 6
                verticalCenter: parent.verticalCenter
            }
            opacity: root.contextMode === "media-expanded" ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: 180 } }
            visible: opacity > 0
            text: MprisController.activePlayer?.trackTitle ?? ""
            font.pixelSize: Appearance.font.pixelSize.small
            color: Appearance.colors.colOnLayer1
            elide: Text.ElideRight
        }

        // Notification text (expanded)
        ColumnLayout {
            anchors {
                left: parent.left; leftMargin: 27
                right: parent.right; rightMargin: 6
                verticalCenter: parent.verticalCenter
            }
            spacing: 0
            opacity: root.contextMode === "notification" ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: 180 } }
            visible: opacity > 0

            StyledText {
                Layout.fillWidth: true
                text: root.contextNotif?.summary ?? ""
                elide: Text.ElideRight
                font.pixelSize: Appearance.font.pixelSize.small
                font.weight: Font.Medium
                color: Appearance.colors.colOnLayer1
            }
            StyledText {
                Layout.fillWidth: true
                visible: (root.contextNotif?.appName ?? "") !== ""
                text: root.contextNotif?.appName ?? ""
                elide: Text.ElideRight
                font.pixelSize: Appearance.font.pixelSize.small - 2
                color: Appearance.colors.colOnLayer1
                opacity: 0.55
            }
        }
    }

    // ── Recording indicator ───────────────────────────────────────────────────
    Item {
        id: recIndicator
        anchors.left: islandBg.left
        anchors.verticalCenter: parent.verticalCenter
        width: root.recordingExtra
        height: islandBg.height
        clip: true
        visible: root.isRecording

        Behavior on width { NumberAnimation { duration: 300; easing.type: Easing.OutCubic } }

        Row {
            anchors { left: parent.left; leftMargin: root.padH; verticalCenter: parent.verticalCenter }
            spacing: root.padH

            Rectangle {
                width: 7; height: 7; radius: 3.5
                color: Appearance.m3colors.m3error
                anchors.verticalCenter: parent.verticalCenter
                SequentialAnimation on opacity {
                    running: root.isRecording
                    loops: Animation.Infinite
                    NumberAnimation { to: 0.2; duration: 700 }
                    NumberAnimation { to: 1.0; duration: 700 }
                }
            }
            StyledText {
                text: "REC"
                font.pixelSize: Appearance.font.pixelSize.small
                color: Appearance.m3colors.m3error
                anchors.verticalCenter: parent.verticalCenter
            }
            Rectangle {
                width: 2; height: 14
                radius: 1
                color: Appearance.colors.colOutlineVariant
                anchors.verticalCenter: parent.verticalCenter
            }
        }
    }

    // ── Active workspace indicator (SineCookie blob) ──────────────────────────
    // A wavy squircle ("cookie") that slides to the active workspace and
    // briefly spins + grows extra lobes on each workspace switch (driven
    // by switchFlashActive). At rest it's a calm 4-sided squircle.
    SineCookie {
        id: activeIndicator
        color: Appearance.colors.colPrimary

        property real computedX: {
            let x = root.recordingExtra
            x += root.padH   // matches slotsRow anchors.leftMargin
            for (let i = 0; i < root.activeIdxInGroup; i++) {
                const vis = (root.workspaceOccupied[i] ?? false) || root.isHovered
                x += vis ? root.btnW : 0
            }
            return x + root.indMargin
        }

        // Square blob sized to the slot; centered in the bar's island.
        implicitSize: root.btnW - root.indMargin * 2
        x: computedX + ((root.btnW - root.indMargin * 2 - implicitSize) / 2)
        y: islandBg.y + (islandBg.height - implicitSize) / 2

        // Rest: shape-dependent (see root.cookieSides / cookieAmpDivisor).
        // On switch: doubles to 8 lobes + spin (the "celebration" flash is the
        // same animation regardless of resting shape, so it always reads as a
        // change).
        sides: root.switchFlashActive ? 8 : root.cookieSides
        amplitude: implicitSize / (root.switchFlashActive ? 28 : root.cookieAmpDivisor)
        constantlyRotate: root.switchFlashActive

        Behavior on x         { NumberAnimation { duration: 300; easing.type: Easing.OutCubic } }
        Behavior on amplitude { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
        Behavior on sides     { NumberAnimation { duration: 260; easing.type: Easing.OutCubic } }
    }

    // ── Workspace slots ───────────────────────────────────────────────────────
    Row {
        id: slotsRow
        anchors.left: recIndicator.right
        anchors.leftMargin: root.padH   // keeps slots aligned with indicator computedX
        anchors.verticalCenter: parent.verticalCenter
        spacing: 0

        Repeater {
            model: root.slotCount

            Item {
                id: slot
                required property int index

                property int    wsId:      root.slotWsIds[index] ?? (root.groupStart + index)
                property bool   occupied:  root.workspaceOccupied[index] ?? false
                property bool   isActive:  index === root.activeIdxInGroup
                property bool   slotVis:   occupied || isActive || root.isHovered
                property bool   showNum:   root.showNumerals || (root.switchFlashActive && isActive) || (root.isHovered && occupied)
                property bool   renaming:  false
                property string wsName:    root.workspaceNames[index] ?? ""
                property int    winCount:  root.workspaceWindowCounts[index] ?? 0

                property var    biggestWindow: HyprlandData.biggestWindowForWorkspace(wsId)
                // Only resolve icon when class is known — avoids showing the image-missing fallback
                property bool   hasIcon: (biggestWindow?.class ?? "") !== ""
                property string iconSrc: hasIcon
                    ? Quickshell.iconPath(AppSearch.guessIcon(biggestWindow.class), "image-missing")
                    : ""

                implicitWidth:  slotVis ? root.btnW : 0
                implicitHeight: root.btnW
                clip: true

                Behavior on implicitWidth {
                    NumberAnimation { duration: 300; easing.type: Easing.OutCubic }
                }

                // Occupied background (secondary container, only non-active)
                Rectangle {
                    z: 1
                    anchors { fill: parent; margins: root.indMargin }
                    radius: root.slotRadius
                    color: ColorUtils.transparentize(Appearance.m3colors.m3secondaryContainer, 0.4)
                    opacity: (slot.occupied && !slot.isActive) ? 1 : 0
                    Behavior on opacity { NumberAnimation { duration: 200 } }
                    Behavior on radius  { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
                }

                // Theme color for overlays — matches active/occupied/inactive state
                readonly property color slotThemeColor:
                    slot.isActive  ? Appearance.m3colors.m3onPrimary :
                    slot.occupied  ? Appearance.m3colors.m3onSecondaryContainer :
                                     Appearance.colors.colOnLayer1Inactive

                // App icon
                Item {
                    z: 3
                    id: iconContainer
                    anchors.centerIn: parent
                    width:  root.btnW
                    height: root.btnW
                    opacity: (slot.occupied && slot.hasIcon && slotIcon.status === Image.Ready && !slot.showNum && !slot.renaming) ? 1 : 0
                    visible: opacity > 0
                    Behavior on opacity { NumberAnimation { duration: 180 } }

                    IconImage {
                        id: slotIcon
                        anchors.centerIn: parent
                        source: slot.iconSrc
                        implicitSize: root.btnW * 0.64
                    }

                    // Monochrome color overlay (same as original)
                    Loader {
                        active: Config.options.bar.workspaces.monochromeIcons
                        anchors.fill: slotIcon
                        sourceComponent: Item {
                            Desaturate {
                                id: desatIcon
                                visible: false
                                anchors.fill: parent
                                source: slotIcon
                                desaturation: 0.8
                            }
                            ColorOverlay {
                                anchors.fill: desatIcon
                                source: desatIcon
                                color: ColorUtils.transparentize(slot.slotThemeColor, 0.9)
                            }
                        }
                    }
                }

                // Window count badge (top-right of icon, shown on hover)
                Rectangle {
                    z: 4
                    anchors { top: parent.top; right: parent.right; topMargin: 1; rightMargin: 1 }
                    width:  badgeText.implicitWidth + 5
                    height: 11
                    radius: 6
                    color:   Appearance.colors.colPrimary
                    opacity: (root.isHovered && slot.winCount > 1) ? 1 : 0
                    visible: opacity > 0
                    Behavior on opacity { NumberAnimation { duration: 200 } }

                    StyledText {
                        id: badgeText
                        anchors.centerIn: parent
                        text: slot.winCount
                        font.pixelSize: 8
                        color: Appearance.m3colors.m3onPrimary
                    }
                }

                // Slot dot. Three states:
                //   • ws exists but is empty (winCount === 0) — always
                //     visible, brighter (this is the new state the user
                //     asked for — distinguishes "opened but empty" from
                //     a workspace that's never been visited).
                //   • ws doesn't exist at all — hover-only ghost dot.
                //   • ws has windows or showNum is on — hidden (icon /
                //     numeral takes over).
                Rectangle {
                    // Lower z than the icon — guarantees the dot can never
                    // visually overlay an app icon, even if a binding
                    // race makes both visible briefly.
                    z: 1
                    anchors.centerIn: parent
                    width: root.btnW * 0.28; height: width; radius: width / 2
                    color: (slot.occupied && !slot.hasIcon)
                        ? Appearance.m3colors.m3outline
                        : Appearance.colors.colOnLayer1Inactive
                    Behavior on color { ColorAnimation { duration: 180 } }
                    // Dot rules:
                    //   • ws exists *and* no icon will be drawn  → solid dot
                    //   • ws doesn't exist                       → hover-only ghost
                    //   • ws has a window with a class           → no dot (icon takes over)
                    //   • showNum / renaming overlay active      → no dot
                    // Using `!slot.hasIcon` (instead of `winCount === 0`)
                    // makes this immune to the cross-monitor count lag —
                    // the icon is the source of truth for "something is
                    // visually here", and we just fill the gap.
                    opacity: (slot.showNum || slot.renaming)
                        ? 0
                        : (slot.occupied && !slot.hasIcon)
                            ? 1
                            : !slot.occupied
                                ? (root.isHovered ? 0.5 : 0.22)
                                : 0
                    visible: opacity > 0
                    Behavior on opacity { NumberAnimation { duration: 180 } }
                }

                // Roman numeral / custom name — overlaid ON the icon, pulses in
                Item {
                    z: 5
                    id: numeralOverlay
                    anchors.centerIn: parent
                    width:  root.btnW
                    height: root.btnW

                    property bool showing: slot.showNum && !slot.renaming

                    opacity: showing ? 1 : 0
                    scale:   showing ? 1 : 0.6
                    visible: opacity > 0

                    Behavior on opacity {
                        NumberAnimation { duration: 160; easing.type: Easing.OutCubic }
                    }
                    Behavior on scale {
                        NumberAnimation { duration: 200; easing.type: Easing.OutBack }
                    }

                    StyledText {
                        anchors.centerIn: parent
                        text: {
                            if (slot.wsName && slot.wsName !== String(slot.wsId))
                                return slot.wsName
                            return root.romanNumerals[index] ?? String(index + 1)
                        }
                        font.pixelSize: Appearance.font.pixelSize.small
                        font.family: Appearance.font.family.numbers
                        font.weight: Font.ExtraBold
                        color: slot.slotThemeColor
                    }
                }

                // Live rename text input
                TextInput {
                    z: 5
                    id: renameInput
                    anchors.centerIn: parent
                    width: parent.width - 6
                    visible: slot.renaming
                    text: slot.wsName || String(slot.wsId)
                    color: slot.isActive ? Appearance.m3colors.m3onPrimary
                                         : Appearance.colors.colOnLayer1
                    font.pixelSize: Appearance.font.pixelSize.small
                    horizontalAlignment: Text.AlignHCenter
                    selectByMouse: true
                    onAccepted: {
                        const t = text.trim()
                        if (t !== "") Hyprland.dispatch(`renameworkspace ${slot.wsId} ${t}`)
                        slot.renaming = false
                    }
                    Keys.onEscapePressed: slot.renaming = false
                    onVisibleChanged: if (visible) { selectAll(); forceActiveFocus() }
                }

                // Click / double-click handler
                MouseArea {
                    z: slot.renaming ? 0 : 6
                    anchors.fill: parent
                    acceptedButtons: Qt.LeftButton | Qt.MiddleButton | Qt.RightButton

                    onPressed: event => {
                        if (slot.renaming) return
                        if (event.button === Qt.LeftButton)
                            Hyprland.dispatch(`workspace ${slot.wsId}`)
                        else if (event.button === Qt.MiddleButton)
                            Hyprland.dispatch(`movetoworkspace ${slot.wsId}`)
                        else if (event.button === Qt.RightButton)
                            GlobalStates.overviewOpen = !GlobalStates.overviewOpen
                    }
                    onDoubleClicked: {
                        if (root.isHovered) slot.renaming = true
                    }
                }
            }
        }
    }

    // ── Init ──────────────────────────────────────────────────────────────────
    Component.onCompleted: {
        updateWorkspaceData()
        micCheckProc.exec({ command: ["bash", "-c", "pactl list source-outputs | grep -c 'Corked: no'"] })
        screenRecordProc.exec({ command: ["bash", "-c", "pgrep -x wf-recorder"] })
    }
}
