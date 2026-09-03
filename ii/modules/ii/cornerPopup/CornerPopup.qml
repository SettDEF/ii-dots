pragma ComponentBehavior: Bound
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.modules.ii.mediaControls
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import Quickshell.Services.Mpris

Scope {
    id: root

    readonly property real popupWidth: 340
    readonly property real popupRounding: Appearance.rounding.screenRounding - Appearance.sizes.hyprlandGapsOut + 1

    PanelWindow {
        id: panelWindow
        visible: GlobalStates.cornerPopupOpen
        exclusionMode: ExclusionMode.Ignore
        exclusiveZone: 0
        implicitWidth: root.popupWidth
        // Pin the Wayland surface to the *fully expanded* size so opening
        // the options panel doesn't resize the layer-shell surface every
        // frame (those compositor commits were the dropdown's lag). The
        // visible rounded rect still grows via its own height animation;
        // the `mask` region tracks `mainCol` so input/visibility match
        // what's actually drawn.
        property string tab: "media"
        // Latch: the Files view stays loaded after its first visit.
        property bool filesEverOpened: false
        onTabChanged: if (tab === "files") filesEverOpened = true
        readonly property int _tabsHeight: 40
        readonly property int _mediaHeight: PlayerService.players.length > 0
            ? (Appearance.sizes.mediaControlsHeight
                + (PlayerService.players.length > 1 ? playerCard.stripHeight : 0)
                + playerCard.optionsHeight)
            : 72   // "no active player" fallback rect
        // Floor only has to clear the "Nothing playing" placeholder; the list
        // itself reports what it needs. A larger floor left dead space now
        // that internal streams are filtered out and the list is short.
        readonly property int _audioHeight: Math.max(76, audioLoader.item?.contentHeight ?? 76)
        readonly property int _filesHeight: filesLoader.item?.contentHeight ?? 232
        // Surface height follows the active tab. Tab switches are user actions
        // (not per-frame), so an occasional resize here is fine.
        readonly property int _bodyHeight: tab === "media" ? _mediaHeight
            : tab === "sources" ? _audioHeight : _filesHeight
        implicitHeight: _tabsHeight + _bodyHeight + 8
        color: "transparent"
        WlrLayershell.namespace: "quickshell:cornerPopup"

        anchors.top: true
        anchors.right: true
        margins.top: Appearance.sizes.barHeight + Appearance.sizes.hyprlandGapsOut
            + (GlobalStates.shelfOpen ? Math.round(panelWindow.screen.height * 0.20) : 0)
        margins.right: Appearance.sizes.hyprlandGapsOut
        Behavior on margins.top { NumberAnimation { duration: 340; easing.type: Easing.OutCubic } }

        mask: Region { item: mainCol }


        onVisibleChanged: {
            if (visible) GlobalFocusGrab.addDismissable(panelWindow)
            else GlobalFocusGrab.removeDismissable(panelWindow)
        }
        Component.onDestruction: GlobalFocusGrab.removeDismissable(panelWindow)
        Connections {
            target: GlobalFocusGrab
            function onDismissed() { GlobalStates.cornerPopupOpen = false }
        }

        // One surface for the whole popup. The tab bar lives inside it rather
        // than floating above as its own pill, so this reads as a single
        // window with tabs instead of two stacked cards.
        Rectangle {
            id: mainCol
            width: parent.width
            y: 2
            height: parent.height - 4
            radius: root.popupRounding
            color: Appearance.colors.colLayer0
            clip: true

            ColumnLayout {
                anchors.fill: parent
                spacing: 0

                PillTabBar {
                    Layout.fillWidth: true
                    Layout.topMargin: 4
                    implicitHeight: 32
                    tabs: [
                        { id: "media",   icon: "music_note",  label: Translation.tr("Media") },
                        { id: "sources", icon: "graphic_eq",  label: Translation.tr("Sources") },
                        { id: "files",   icon: "folder_open", label: Translation.tr("Files") },
                    ]
                    current: panelWindow.tab
                    onTabSelected: id => panelWindow.tab = id
                }

                // ── Audio sources tab ──────────────────────────────────────
                Item {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    visible: panelWindow.tab === "sources"
                    clip: true
                    Loader {
                        id: audioLoader
                        anchors.fill: parent
                        active: panelWindow.tab === "sources" || GlobalStates.cornerPopupOpen
                        asynchronous: true
                        sourceComponent: AudioSourcesView {}
                    }
                }

                // ── Files tab ──────────────────────────────────────────────
                Item {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    visible: panelWindow.tab === "files"
                    clip: true
                    Loader {
                        id: filesLoader
                        anchors.fill: parent
                        // Latched via panelWindow so the view stays alive once
                        // opened (navigation state survives tab switches).
                        // Must NOT read its own `status` here — that is a
                        // self-referential binding and breaks instantiation.
                        active: panelWindow.filesEverOpened
                        asynchronous: true
                        sourceComponent: FilesView {}
                    }
                }

            // Player card + name/dots strip all in one rounded rect
            Rectangle {
                id: playerCard
                visible: panelWindow.tab === "media" && PlayerService.players.length > 0
                implicitWidth: root.popupWidth
                // Height is computed from the options panel's *current* height
                // (which is itself animated). One animation, one source of
                // truth — avoids the implicitHeight ↔ child-height race that
                // produced visible jitter.
                implicitHeight: Appearance.sizes.mediaControlsHeight
                    + (PlayerService.players.length > 1 ? stripHeight : 0)
                    + optionsPanel.height
                // The shell already paints the background; this is just a
                // positioning container for the player pieces.
                color: "transparent"
                clip: true

                readonly property int stripHeight: 28
                readonly property int optionsHeight: 44
                property bool optionsOpen: false

                // Helper: run a shell command for the active app
                function _runForActive(line) {
                    Quickshell.execDetached(["bash", "-c", line])
                }

                // Toggle mute on the active player's app via the helper script,
                // which matches sink-inputs by identity / desktopEntry / dbusName.
                function toggleMute() {
                    const p = PlayerService.activePlayer
                    if (!p) return
                    const ident   = p.identity     ?? ""
                    const desktop = p.desktopEntry ?? ""
                    const dbus    = p.dbusName     ?? ""
                    const script  = FileUtils.trimFileProtocol(`${Directories.scriptPath}/audio/mute-mpris-app.sh`)
                    Quickshell.execDetached([
                        "bash", "-c",
                        `out=$('${script}' '${ident.replace(/'/g, "'\\''")}' '${desktop.replace(/'/g, "'\\''")}' '${dbus.replace(/'/g, "'\\''")}' 2>/dev/null); ` +
                        `case "$out" in ` +
                        `  MUTED)   notify-send -a Quickshell -i audio-volume-muted   -t 1500 'Muted'   '${ident.replace(/'/g, "'\\''")}' ;; ` +
                        `  UNMUTED) notify-send -a Quickshell -i audio-volume-high    -t 1500 'Unmuted' '${ident.replace(/'/g, "'\\''")}' ;; ` +
                        `  *)       notify-send -a Quickshell -i audio-volume-muted   -t 1500 'No audio' 'No sink for this player' ;; ` +
                        `esac`
                    ])
                }

                function adjustVolume(delta) {
                    const p = PlayerService.activePlayer
                    if (!p) return
                    if (p.canSetVolume) p.volume = Math.max(0, Math.min(1, (p.volume ?? 0) + delta / 100))
                }

                function copyTitle() {
                    const p = PlayerService.activePlayer
                    Quickshell.clipboardText = p?.trackTitle ?? ""
                    Quickshell.execDetached([
                        "notify-send", "-a", "Quickshell", "-i", "edit-copy", "-t", "2000",
                        "Track copied", p?.trackTitle ?? ""
                    ])
                }

                function raiseApp() {
                    const p = PlayerService.activePlayer
                    if (!p) return
                    if (p.canRaise) p.raise()
                }

                PlayerControl {
                    anchors.top: parent.top
                    anchors.left: parent.left
                    anchors.right: parent.right
                    implicitHeight: Appearance.sizes.mediaControlsHeight
                    player: PlayerService.activePlayer
                    visualizerPoints: CavaService.visualizerPoints
                    radius: root.popupRounding
                }

                // Name + dots strip — sits just below the player control,
                // above the options panel.
                Item {
                    id: nameStrip
                    visible: PlayerService.players.length > 1
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: undefined
                    y: Appearance.sizes.mediaControlsHeight
                    height: parent.stripHeight

                    StyledText {
                        anchors.left: parent.left
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.leftMargin: 12
                        text: PlayerService.activePlayer?.identity ?? ""
                        color: PlayerService.accentForPlayer(PlayerService.activePlayer)
                        font.pixelSize: Appearance.font.pixelSize.smallest
                        font.weight: Font.Medium
                        Behavior on color { ColorAnimation { duration: 200 } }
                    }

                    Row {
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.rightMargin: 12
                        spacing: 5

                        Repeater {
                            model: PlayerService.players
                            delegate: Rectangle {
                                required property int index
                                required property MprisPlayer modelData
                                width: PlayerService.activeIndex === index ? 16 : 6
                                height: 6
                                radius: 3
                                color: PlayerService.activeIndex === index
                                    ? PlayerService.accentForPlayer(modelData)
                                    : Qt.alpha(Appearance.colors.colOnLayer0, 0.3)
                                Behavior on width  { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
                                Behavior on color  { ColorAnimation { duration: 200 } }
                                TapHandler { onTapped: PlayerService.activeIndex = index }
                            }
                        }
                    }
                }

                // Hover the whole card → expand options
                HoverHandler {
                    id: cardHov
                    onHoveredChanged: {
                        if (hovered) {
                            optionsCloseTimer.stop()
                            playerCard.optionsOpen = true
                        } else {
                            optionsCloseTimer.restart()
                        }
                    }
                }
                Timer {
                    id: optionsCloseTimer
                    interval: 180
                    repeat: false
                    onTriggered: if (!cardHov.hovered) playerCard.optionsOpen = false
                }

                // ── Options panel — grows out of the bottom of the card on hover.
                // Lazy: nothing instantiated until the user has hovered at least
                // once. Stays loaded after first show (cheap to keep around).
                Item {
                    id: optionsPanel
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    height: playerCard.optionsOpen ? playerCard.optionsHeight : 0
                    Behavior on height {
                        NumberAnimation {
                            duration: 220
                            easing.type: Easing.OutCubic
                        }
                    }
                    visible: height > 0.5
                    clip: true

                    Loader {
                        anchors.fill: parent
                        active: playerCard.optionsOpen || optionsPanel.visible
                        asynchronous: true
                        sourceComponent: Item {
                            anchors.fill: parent
                            // Hairline divider on top
                            Rectangle {
                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.top: parent.top
                                anchors.leftMargin: 8
                                anchors.rightMargin: 8
                                height: 1
                                color: Qt.alpha(Appearance.colors.colOnLayer0, 0.10)
                            }

                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: 8
                                anchors.rightMargin: 8
                                anchors.topMargin: 4
                                anchors.bottomMargin: 4
                                spacing: 4

                                // ── 6-slot row: mute (1) │ slider (2) │ title (1) │ raise (1) │ stop (1)
                                component IconBtn: Rectangle {
                                    property string sym: ""
                                    property var onTap: () => {}
                                    Layout.alignment: Qt.AlignVCenter
                                    Layout.fillWidth: true
                                    Layout.horizontalStretchFactor: 1
                                    implicitHeight: 30
                                    radius: height / 2
                                    color: ibHov.hovered
                                        ? Qt.alpha(Appearance.colors.colOnLayer0, 0.08)
                                        : "transparent"
                                    Behavior on color { ColorAnimation { duration: 120 } }
                                    HoverHandler { id: ibHov }
                                    TapHandler { onTapped: parent.onTap() }
                                    MaterialSymbol {
                                        anchors.centerIn: parent
                                        text: parent.sym
                                        iconSize: 16
                                        color: Appearance.colors.colOnLayer0
                                    }
                                }

                                IconBtn { sym: "volume_off"; onTap: () => playerCard.toggleMute() }

                                // Compact volume slider — takes up two slots' worth of row
                                // width via the stretch factor. Drives the active player's
                                // volume directly; for the phone this routes through the
                                // KDE Connect MPRIS bridge → mprisremote.volume.
                                StyledSlider {
                                    id: volSlider
                                    Layout.alignment: Qt.AlignVCenter
                                    Layout.fillWidth: true
                                    Layout.horizontalStretchFactor: 2
                                    Layout.preferredHeight: 30
                                    from: 0; to: 1
                                    // Some MPRIS players don't expose canSetVolume reliably
                                    // (and the phone bridge always accepts writes), so stay
                                    // enabled — failed writes are no-ops.
                                    enabled: PlayerService.activePlayer !== null

                                    // One-way bindings would be torn by the user's drag.
                                    // Use imperative sync via Connections instead.
                                    readonly property var _player: PlayerService.activePlayer
                                    on_PlayerChanged: value = _player?.volume ?? 0
                                    Component.onCompleted: value = _player?.volume ?? 0
                                    Connections {
                                        target: volSlider._player
                                        ignoreUnknownSignals: true
                                        function onVolumeChanged() {
                                            if (!volSlider.pressed)
                                                volSlider.value = volSlider._player?.volume ?? 0
                                        }
                                    }

                                    onMoved: {
                                        const p = _player
                                        if (!p) return
                                        const v = Math.max(0, Math.min(1, value))
                                        // Force the write even if the player advertises
                                        // canSetVolume=false; if the underlying player
                                        // ignores it that's fine.
                                        p.volume = v
                                    }
                                }

                                IconBtn { sym: "title";       onTap: () => playerCard.copyTitle() }
                                IconBtn { sym: "open_in_new"; onTap: () => playerCard.raiseApp() }
                                // Stop removed — pause/play on the main strip already
                                // serves the same purpose (pause is reversible, stop wasn't).
                            }
                        }
                    }
                }

                WheelHandler {
                    target: null
                    acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
                    onWheel: event => {
                        const n = PlayerService.players.length
                        if (n < 2) return
                        if (event.angleDelta.y < 0)
                            PlayerService.activeIndex = (PlayerService.activeIndex + 1) % n
                        else
                            PlayerService.activeIndex = (PlayerService.activeIndex - 1 + n) % n
                    }
                }
            }

            // No player fallback
            Item {
                visible: panelWindow.tab === "media" && PlayerService.players.length === 0
                Layout.fillWidth: true
                implicitHeight: 72
                RowLayout {
                    anchors.centerIn: parent
                    spacing: 8
                    MaterialSymbol {
                        text: "music_off"
                        iconSize: Appearance.font.pixelSize.large
                        color: Appearance.colors.colSubtext
                    }
                    StyledText {
                        text: Translation.tr("No active player")
                        color: Appearance.colors.colSubtext
                        font.pixelSize: Appearance.font.pixelSize.small
                    }
                }
            }
            }
        }
    }

    // GlobalShortcuts moved to panelFamilies/Shortcuts.qml so they stay
    // registered while this panel is unloaded by LazyPanelLoader.
}
