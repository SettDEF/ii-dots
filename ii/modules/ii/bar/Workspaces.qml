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
    // Declared and never read: every anchor below is horizontal. The vertical
    // bar uses VerticalWorkspaces instead — passing vertical: true here only
    // ever produced a full-width widget spilling out of a 40px bar. Kept so
    // any caller still setting it is not a hard error.
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
            if (Config.options.bar.workspaces.switchFlash && !GameMode.active) {
                root.switchFlashActive = true
                switchFlashTimer.restart()
            }
        }
    }
    onCurrentGroupChanged: updateWorkspaceData()

    // ── Hover ─────────────────────────────────────────────────────────────────
    property bool isHovered: false
    // Pointer x inside the island, used to work out WHICH slot is under the
    // cursor. Deliberately not a HoverHandler on each slot: slotsRow is drawn
    // on top of islandBg as a SIBLING, so a handler on a slot consumes the
    // hover and islandBg never sees it — which silently killed the row's
    // expand-to-10 entirely. One handler, and the slots do the arithmetic.
    readonly property real hoverX: islandHover.point.position.x

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
                // Exactly two lines from one shell: mic activity, then whether
                // wf-recorder is up. Combining them halves the process spawns;
                // the debounce on each is unchanged.
                //
                // The recorder line is an explicit if/echo rather than
                // `pgrep -c ... || echo 0`: pgrep -c PRINTS 0 and also EXITS
                // non-zero when there is no match, so the `||` fired too and the
                // command emitted three lines, shifting the parse.
                const lines = text.trim().split("\n")
                const micActive = parseInt(lines[0] ?? "0") > 0
                const recActive = parseInt(lines[1] ?? "0") > 0

                root._micPositiveCount = micActive
                    ? Math.min(root._micPositiveCount + 1, 2) : 0
                root.micRecording = root._micPositiveCount >= 2

                root._screenPositiveCount = recActive
                    ? Math.min(root._screenPositiveCount + 1, 2) : 0
                root.screenRecording = root._screenPositiveCount >= 2
            }
        }
    }

    // Poll for "is something recording". Two costs worth keeping down: this runs
    // for the life of the session, and `pactl list source-outputs` is not a cheap
    // read. Measured at 3s it was ~8 points of a core all by itself, purely from
    // spawning two shells twenty times a minute.
    //
    // 5s instead of 3s, and one shell instead of two: that is a third of the
    // process spawns. The debounce needs two consecutive positives, so REC still
    // appears within ~10s of a recording starting.
    Timer {
        interval: 5000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: {
            // One shell, not two. Both answers come back on one line, which also
            // halves the process spawns.
            //
            // cava reads the output monitor, not the mic — the bar's own
            // visualiser would otherwise light REC as if you were recording.
            micCheckProc.exec({ command: ["bash", "-c",
                "pactl list source-outputs | awk 'BEGIN{RS=\"Source Output\"} /Corked: no/ && !/MiniMeters/ && !/cava/' | wc -l; "
              + "if pgrep -x wf-recorder >/dev/null; then echo 1; else echo 0; fi"] })
        }
    }

    // ── Roman numeral flash ───────────────────────────────────────────────────
    readonly property var romanNumerals: ["I","II","III","IV","V","VI","VII","VIII","IX","X"]
    // The periodic numeral flash is gone. It fired every 9s for 1s across every
    // slot, so the bar changed on its own with nothing having happened — motion
    // in peripheral vision that carried no information. Numbers now appear only
    // when asked for: hover a slot, or on an actual workspace switch.
    property bool switchFlashActive: false
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

    // A pomodoro counts as "in progress" while it is running OR paused
    // part-way through a lap. Sitting idle at the full lap duration is not a
    // session, so the island stays out of the way until you actually start one.
    readonly property bool pomodoroActive: TimerService.pomodoroRunning
        || TimerService.pomodoroSecondsLeft !== TimerService.pomodoroLapDuration

    property string contextMode: {
        if (Notifications.popupList.length > 0 && !Notifications.popupInhibited) return "notification"
        // Hovering still gets you the media controls, so music is never more
        // than a pointer away even mid-session.
        if (_currentTrack.length > 0 && _ctxHoverSticky) return "media-controls"
        // Above passive media: if you started a timer you want to see it, and
        // a track title you already know is the cheaper thing to give up.
        if (root.pomodoroActive) return "pomodoro"
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
    readonly property real recW:           72   // chip + separator + padding

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
    // 14 bars × (2 dot + 4 gap), + the icon's 27 lead and 6 tail.
    readonly property real ctxSpectrumW: Config.options.bar.showVisualizer ? 84 + 27 + 6 : ctxCollapsedW
    readonly property real ctxExpandedW:  27 + Math.min(ctxTextMeasure.implicitWidth, 180) + 8
    readonly property real ctxTotalW: {
        if (contextMode === "none") return 0
        if (contextMode === "media-collapsed") return ctxSpectrumW
        if (contextMode === "media-wavy")     return 120
        if (contextMode === "media-controls") return 120
        if (contextMode === "pomodoro")       return ctxPomodoroW
        return ctxExpandedW
    }

    // ring(20) + gap(6) + readout + right padding(6)
    readonly property real ctxPomodoroW: 20 + 6 + Math.ceil(pomoTextMeasure.implicitWidth) + 6

    Text {
        id: pomoTextMeasure
        visible: false
        font.pixelSize: Appearance.font.pixelSize.small
        font.family: Appearance.font.family.numbers
        text: "00:00"
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
                HyprDispatch.run("workspace r+1")
                accum = 0
                wsWheelCooldown.restart()
            } else if (accum >= notch) {
                HyprDispatch.run("workspace r-1")
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
        // Right-click is listed here as the FALLBACK way to the settings menu.
        // "Media controls" is itself one of the menu's toggles, so switching it
        // off collapses contextSlot to zero width and takes the primary
        // right-click target with it -- leaving no way back to the menu that
        // turned it off. This MouseArea sits below the pills, so it only ever
        // sees presses on bare island: the padding around the row and the empty
        // strip the context slot vacates.
        acceptedButtons: Qt.BackButton | Qt.RightButton
        onPressed: event => {
            if (event.button === Qt.BackButton)
                HyprDispatch.run("togglespecialworkspace")
            else if (event.button === Qt.RightButton) {
                const pt = mapToItem(wsMenu.parent, event.x, event.y)
                wsMenu.popup(pt.x, pt.y, root.buildMenuItems())
            }
        }
    }

    // ── Island background ─────────────────────────────────────────────────────
    Rectangle {
        id: islandBg
        anchors { fill: parent; topMargin: 4; bottomMargin: 4 }
        radius: Appearance.rounding.full
        color: Appearance.colors.colBarIsland
        border.width: 1
        border.color: Appearance.colors.colBarIslandBorder

        HoverHandler {
            id: islandHover
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
        // Only as wide as the slot actually LOOKS, until the cursor is really
        // on it. A flat 120 meant ~100px of invisible, full-height hit area
        // sitting over empty island next to a 22px button — so the play button
        // lit up and the slot expanded while the cursor was still out between
        // the workspace pills, with nothing on screen to explain why.
        //
        // Once genuinely hovered it grows to 120 and _ctxHoverSticky holds it
        // there through the 90ms hysteresis, which is the case this probe was
        // built for: keeping the EXPANDED controls reachable while the slot
        // animates. That still works — you just have to touch the button first.
        width: root._ctxHoverSticky ? 120 : Math.max(root.ctxTotalW, 28)
        Behavior on width { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }
        height: islandBg.height
        visible: Config.options.bar.workspaces.showMediaContext && root.contextMode !== "none"
        z: 5
        HoverHandler { id: ctxSlotHover }
    }

    // ── Context slot: right side of island ───────────────────────────────────
    Item {
        id: contextSlot
        visible: Config.options.bar.workspaces.showMediaContext
        // Tight gap to slotsRow — the workspace circles already have
        // their own internal padding so an extra 6 px island-pad here
        // doubled up visually. Drop to 2 px so the media icon sits
        // right after the last workspace pill.
        anchors { left: slotsRow.right; leftMargin: 2; verticalCenter: parent.verticalCenter }
        width: root.ctxTotalW
        height: islandBg.height
        clip: true
        Behavior on width { NumberAnimation { duration: 300; easing.type: Easing.OutCubic } }

        // Plain right-click opens the workspaces settings menu.
        //
        // The menu cannot live on a plain right-click on the PILLS: there it is
        // the overview, which is muscle memory and taking it away was already
        // the wrong call once. This slot carries no such binding, so it can host
        // the menu with no modifier -- and it is the element the menu is mostly
        // about (visualiser, media controls) anyway. Ctrl+right-click on a pill
        // still works.
        TapHandler {
            acceptedButtons: Qt.RightButton
            gesturePolicy: TapHandler.ReleaseWithinBounds
            onTapped: eventPoint => {
                const pt = contextSlot.mapToItem(wsMenu.parent,
                                                 eventPoint.position.x, eventPoint.position.y)
                wsMenu.popup(pt.x, pt.y, root.buildMenuItems())
            }
        }

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
                margin: Appearance.sizes.touchSlop
                onTapped: GlobalStates.cornerPopupOpen = !GlobalStates.cornerPopupOpen
            }

            HoverHandler { margin: Appearance.sizes.touchSlop; id: mediaCircleHover }
            Rectangle {
                anchors.fill: parent; radius: parent.radius
                color: "white"
                opacity: mediaCircleHover.hovered ? 0.12 : 0
                Behavior on opacity { NumberAnimation { duration: 120 } }
            }
        }

        // ── Pomodoro ────────────────────────────────────────────────────
        // Ring + MM:SS. Left-click toggles pause/resume, right-click resets,
        // so the timer is fully drivable from the bar without opening the
        // sidebar. Same TimerService the sidebar widget uses — one source of
        // truth, so the two never disagree.
        Item {
            id: pomodoroCtx
            anchors {
                left: parent.left; leftMargin: 2
                right: parent.right; rightMargin: 6
                verticalCenter: parent.verticalCenter
            }
            height: 22
            opacity: root.contextMode === "pomodoro" ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: 180 } }
            visible: opacity > 0

            readonly property color phaseColor: TimerService.pomodoroBreak
                ? Appearance.m3colors.m3tertiary
                : Appearance.m3colors.m3primary

            HoverHandler { id: pomoHover; cursorShape: Qt.PointingHandCursor }
            TapHandler {
                acceptedButtons: Qt.LeftButton
                onTapped: TimerService.togglePomodoro()
            }
            TapHandler {
                acceptedButtons: Qt.RightButton
                onTapped: TimerService.resetPomodoro()
            }

            CircularProgress {
                id: pomoRing
                anchors { left: parent.left; verticalCenter: parent.verticalCenter }
                implicitSize: 20
                lineWidth: 3
                // Guard the divide: lapDuration is 0 for a beat on config reload.
                value: TimerService.pomodoroLapDuration > 0
                    ? 1 - (TimerService.pomodoroSecondsLeft / TimerService.pomodoroLapDuration)
                    : 0
                colPrimary: pomodoroCtx.phaseColor
                colSecondary: ColorUtils.transparentize(pomodoroCtx.phaseColor, 0.75)

                MaterialSymbol {
                    anchors.centerIn: parent
                    // Paused mid-lap reads as a play affordance, which is what
                    // clicking will do.
                    text: TimerService.pomodoroRunning
                        ? (TimerService.pomodoroBreak ? "coffee" : "timer")
                        : "play_arrow"
                    iconSize: 11
                    color: pomodoroCtx.phaseColor
                }
            }

            StyledText {
                anchors {
                    left: pomoRing.right; leftMargin: 6
                    right: parent.right
                    verticalCenter: parent.verticalCenter
                }
                font.pixelSize: Appearance.font.pixelSize.small
                font.family: Appearance.font.family.numbers
                color: pomodoroCtx.phaseColor
                elide: Text.ElideRight
                text: {
                    const left = Math.max(0, TimerService.pomodoroSecondsLeft)
                    const m = Math.floor(left / 60).toString().padStart(2, "0")
                    const sec = Math.floor(left % 60).toString().padStart(2, "0")
                    return `${m}:${sec}`
                }
            }

            StyledToolTip {
                visible: pomoHover.hovered
                text: {
                    const phase = TimerService.pomodoroLongBreak ? Translation.tr("Long break")
                        : TimerService.pomodoroBreak ? Translation.tr("Break") : Translation.tr("Focus")
                    const action = TimerService.pomodoroRunning ? Translation.tr("click to pause")
                                                                : Translation.tr("click to resume")
                    return `${phase} · ${Translation.tr("cycle")} ${TimerService.pomodoroCycle + 1}\n${action}, ${Translation.tr("right-click to reset")}`
                }
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
            // Spectrum takes this slot when enabled.
            opacity: root.contextMode === "media-wavy" && !Config.options.bar.showVisualizer ? 1 : 0
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
                // Flow the wave at ~30fps instead of every screen refresh.
                // Was a FrameAnimation firing 60–144×/s, repainting this
                // CPU-rasterized Canvas nonstop on the always-visible bar —
                // a real idle-battery drain. 30fps looks identically smooth.
                // Also only flow while actually playing; a paused track sits still.
                Timer {
                    interval: 33
                    repeat: true
                    running: mediaWavyBar.visible && MprisController.isPlaying
                    onTriggered: wavyPlayed.requestPaint()
                }
            }
        }

        // Cava spectrum — the wavy line's slot, opt-in. Loader, not
        // `visible`, so `off` builds nothing.
        Loader {
            anchors {
                left: parent.left; leftMargin: 27
                right: parent.right; rightMargin: 6
                verticalCenter: parent.verticalCenter
            }
            height: 12

            // Built ONLY while it is actually on screen.
            //
            // This used to be `active: showVisualizer`, so the spectrum existed
            // permanently and stayed bound to CavaService, which pushes a new
            // frame ~60x/s for as long as anything is playing. The bindings
            // re-ran every one of those frames even in the modes where the
            // widget is fully transparent and nothing is drawn. Measured: the
            // bar accounted for ~44 points of idle CPU, and the spectrum was
            // most of it.
            //
            // `|| opacity > 0.01` keeps it alive through the fade-out, so
            // disappearing still animates rather than popping.
            readonly property bool onScreen: root.contextMode === "media-wavy"
                                          || root.contextMode === "media-collapsed"
            active: (Config.options.bar.showVisualizer && onScreen) || opacity > 0.01
            // Collapsed too, not just the 2 s wavy window — otherwise it
            // would flash past once a track and never be seen.
            opacity: (Config.options.bar.showVisualizer && onScreen) ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: 180 } }
            visible: opacity > 0

            sourceComponent: Visualizer {
                barCount: 14
                dotSize: 2
                dotSpacing: 4
                maxBarHeight: 12
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

            // Same height and radius as a workspace slot. Tinted, not solid —
            // matugen's errorContainer at full strength shouts over the pills.
            Rectangle {
                implicitWidth: 52
                implicitHeight: root.btnW - root.indMargin * 2
                radius: root.slotRadius
                color: ColorUtils.transparentize(Appearance.colors.colErrorContainer, 0.4)

                Row {
                    anchors.centerIn: parent
                    spacing: 5

                    Rectangle {
                        width: 7; height: 7; radius: 3.5
                        color: Appearance.colors.colError
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
                        font.weight: Font.Medium
                        color: Appearance.colors.colError
                        anchors.verticalCenter: parent.verticalCenter
                    }
                }
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
                // Hover reveals every slot's number, not just occupied ones —
                // otherwise the widget can tell you WHAT is running but never
                // WHERE, and an empty slot stays anonymous.
                //
                // iconFailed is the important one: a slot with a known class but
                // an icon that never loads used to draw NOTHING. The icon hides
                // on `status !== Image.Ready`, and the dot hides because hasIcon
                // is true — so the slot rendered as a blank pill. Hyprland
                // truncates long classes ("com.bitwig.BitwigStudi", missing the
                // final "o"), which never resolves, so this fires in practice.
                // Only the slot under the cursor, not every slot in the row.
                // root.isHovered still expands the row so empty slots become
                // hoverable at all -- it just no longer numbers all of them.
                property bool   showNum:   Config.options.bar.workspaces.alwaysShowNumbers
                    || (root.switchFlashActive && isActive)
                    || pointerOver
                    || iconFailed
                property bool   renaming:  false
                property string wsName:    root.workspaceNames[index] ?? ""
                property int    winCount:  root.workspaceWindowCounts[index] ?? 0

                // islandBg fills root, so its pointer x shares root's x axis;
                // the slot's own left edge in that space is slotsRow.x + x.
                readonly property bool pointerOver: root.isHovered
                    && root.hoverX >= slotsRow.x + x
                    && root.hoverX <  slotsRow.x + x + width

                property var    biggestWindow: HyprlandData.biggestWindowForWorkspace(wsId)
                // Only resolve icon when class is known — avoids showing the image-missing fallback
                property bool   hasIcon: (biggestWindow?.class ?? "") !== ""
                property string iconSrc: hasIcon
                    ? Quickshell.iconPath(AppSearch.guessIcon(biggestWindow.class), "image-missing")
                    : ""
                // Did the icon lookup actually give up?
                //
                // NOT Image.status: iconSrc passes "image-missing" as the
                // fallback, so the URL is always loadable and status is never
                // Error -- it just renders a placeholder glyph. And guessIcon()
                // ends in a fuzzy pass that "always answers with something", so
                // a miss usually becomes a wrong-but-real icon rather than
                // nothing. The two genuine give-up values are the sentinels
                // guessIcon returns when even fuzzy fails, and iconPath()'s
                // check=true overload, which returns "" for a missing icon
                // instead of a placeholder URL.
                readonly property string iconGuess: hasIcon ? AppSearch.guessIcon(biggestWindow.class) : ""
                readonly property bool iconFailed: occupied && hasIcon
                    && (iconGuess === "image-missing"
                        || iconGuess === "application-x-executable"
                        || Quickshell.iconPath(iconGuess, true) === "")

                implicitWidth:  slotVis ? root.btnW : 0
                implicitHeight: root.btnW
                clip: true

                // Fade in step with the width.
                //
                // The slot animates 0 -> btnW over 300ms with clip:true, so a
                // half-open slot used to be REVEALED by a hard clip edge — a
                // sharp-edged vertical sliver of a dot or pill, which is what
                // shows up between elements while the row expands. Tying
                // opacity to how open the slot is turns that into a fade, so
                // there is never a crisp partial edge on screen.
                opacity: Math.min(1, implicitWidth / root.btnW)

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
                    opacity: (Config.options.bar.workspaces.showAppIcons
                        && slot.occupied && slot.hasIcon && slotIcon.status === Image.Ready
                        && !slot.showNum && !slot.renaming) ? 1 : 0
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
                            // Derive from wsId, not index: out-of-group slots are
                            // appended after the group, so index+1 named them wrong
                            // (ws 61 showed as "VII").
                            const w = Config.options.bar.workspaces
                            const off = slot.wsId - root.groupStart
                            const inGroup = off >= 0 && off < root.workspacesPerGroup
                            // numberMap is the user's own glyph list; it can be
                            // shorter than the group, so fall through when it is.
                            if (w.useNerdFont && inGroup && (w.numberMap?.length ?? 0) > off)
                                return w.numberMap[off]
                            if (w.romanNumerals && inGroup)
                                return root.romanNumerals[off] ?? String(slot.wsId)
                            return String(slot.wsId)
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
                        if (t !== "") HyprDispatch.run(`renameworkspace ${slot.wsId} ${t}`)
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

                    // Left-click switches, but a hair late so a double-click
                    // (which renames) can cancel it — otherwise the first press
                    // of the double-click already yanked you to that workspace.
                    Timer {
                        id: switchTimer
                        interval: 180
                        onTriggered: HyprDispatch.run(`workspace ${slot.wsId}`)
                    }
                    onPressed: event => {
                        if (slot.renaming) return
                        if (event.button === Qt.LeftButton)
                            switchTimer.restart()
                        else if (event.button === Qt.MiddleButton)
                            HyprDispatch.run(`movetoworkspace ${slot.wsId}`)
                        else if (event.button === Qt.RightButton) {
                            // Plain right-click keeps opening the overview — taking
                            // that away for a settings menu was the wrong trade, it
                            // is the muscle-memory action on these pills.
                            //
                            // Ctrl, not Super: SUPER + mouse:273 is bound to
                            // window-resize in hyprland/keybinds.lua, so Hyprland
                            // would swallow it before the shell ever saw the press.
                            if (event.modifiers & Qt.ControlModifier) {
                                const pt = slot.mapToItem(wsMenu.parent, event.x, event.y)
                                wsMenu.popup(pt.x, pt.y, root.buildMenuItems())
                            } else {
                                GlobalStates.overviewOpen = !GlobalStates.overviewOpen
                            }
                        }
                    }
                    onDoubleClicked: {
                        switchTimer.stop()   // cancel the pending switch — rename only
                        if (root.isHovered) slot.renaming = true
                    }
                }
            }
        }
    }

    // ── Context menu ─────────────────────────────────────────────────────────
    // Every switch here is a Config option, so it persists and stays editable
    // by hand; the menu is just a faster way to reach them. Checkbox state is
    // carried in the icon because PopupContextMenu items are {icon,label,fn}.
    function buildMenuItems() {
        const c = Config.options.bar
        const w = c.workspaces
        const chk = v => v ? "check_box" : "check_box_outline_blank"
        return [
            { icon: chk(c.showVisualizer),    label: qsTr("Audio visualiser"),
              onTriggered: () => c.showVisualizer = !c.showVisualizer },
            { icon: chk(w.showAppIcons),      label: qsTr("App icons"),
              onTriggered: () => w.showAppIcons = !w.showAppIcons },
            { icon: chk(w.monochromeIcons),   label: qsTr("Monochrome icons"),
              onTriggered: () => w.monochromeIcons = !w.monochromeIcons },
            { icon: chk(w.alwaysShowNumbers), label: qsTr("Always show numbers"),
              onTriggered: () => w.alwaysShowNumbers = !w.alwaysShowNumbers },
            { icon: chk(w.romanNumerals),     label: qsTr("Roman numerals"),
              onTriggered: () => w.romanNumerals = !w.romanNumerals },
            { icon: chk(w.switchFlash),       label: qsTr("Switch animation"),
              onTriggered: () => w.switchFlash = !w.switchFlash },
            { icon: chk(w.showMediaContext),  label: qsTr("Media controls"),
              onTriggered: () => w.showMediaContext = !w.showMediaContext }
        ]
    }

    PopupContextMenu {
        id: wsMenu
        // Re-parent to the window root or the bar clips it: the island is only
        // ~32px tall and the menu is far taller. Same walk PanelPositioner does.
        Component.onCompleted: {
            let p = parent
            while (p && p.parent) p = p.parent
            if (p) wsMenu.parent = p
        }
    }

    // ── Init ──────────────────────────────────────────────────────────────────
    Component.onCompleted: {
        updateWorkspaceData()
        // The poll timer has triggeredOnStart, so the first reading happens on
        // its own. Kicking it again here ran a THIRD shell at startup, with a
        // different (and wrong) mic query that did not exclude cava.
    }
}
