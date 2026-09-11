// System hub — one screen that reaches every settings panel in the shell.
//
// The panels themselves are scattered across keybinds, sidebar buttons and
// IPC calls, which means the only reliable way to find one was to remember it
// existed. This is the index: every panel, named, with an icon, in one grid.
//
// Opened by tapping the uptime pill in the right sidebar (see
// SidebarRightContent), by Super+Shift+S, or `qs -c ii ipc call systemHub open`.
//
// TOUCH FIRST. Everything here is sized for a finger rather than a cursor:
//   · tiles are 104px with 10px gutters — comfortably past the ~9mm target
//     that touch guidelines ask for, at this panel's 1.67 scale
//   · labels are always drawn, never hover-only, because a finger produces no
//     hover state and a grid of bare icons is a memory test
//   · the grid flicks (StyledFlickable), so it scrolls by dragging anywhere in
//     it rather than only on a 4px scrollbar
//   · the close affordance is a 44px target, and tapping the backdrop also
//     closes — two ways out, both large
pragma ComponentBehavior: Bound
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import Quickshell.Wayland

Scope {
    id: root

    function close() { GlobalStates.systemHubOpen = false }

    // Every panel worth reaching, in one list. Adding a panel is one entry —
    // there is deliberately no second place to register it.
    readonly property var entries: [
        { icon: "monitor",              label: Translation.tr("Displays"),      act: () => GlobalStates.displayOpen = true },
        { icon: "volume_up",            label: Translation.tr("Audio"),         act: () => GlobalStates.audioSettingsOpen = true },
        { icon: "monitoring",           label: Translation.tr("System monitor"),act: () => GlobalStates.statsHudSettingsOpen = true },
        { icon: "speed",                label: Translation.tr("Stats overlay"), act: () => GlobalStates.statsHudOpen = !GlobalStates.statsHudOpen },
        { icon: "bolt",                 label: Translation.tr("Power profile"), act: () => GlobalStates.rogPowerOpen = true },
        { icon: "mouse",                label: Translation.tr("Mouse"),         act: () => GlobalStates.kinetixOpen = true },
        { icon: "keyboard",             label: Translation.tr("Keyboard"),      act: () => GlobalStates.kbSettingsOpen = true },
        { icon: "language",             label: Translation.tr("Layout"),        act: () => GlobalStates.kbPickerOpen = true },
        { icon: "keyboard_alt",         label: Translation.tr("On-screen keys"),act: () => GlobalStates.oskOpen = !GlobalStates.oskOpen },
        { icon: "touch_app",            label: Translation.tr("Touchpad"),      act: () => GlobalStates.touchpadOpen = !GlobalStates.touchpadOpen },

        { icon: "wallpaper",            label: Translation.tr("Wallpaper"),     act: () => GlobalStates.wallpaperSelectorOpen = true },
        { icon: "travel_explore",       label: Translation.tr("Wallpaper web"), act: () => GlobalStates.skwdWallOpen = true },
        { icon: "tune",                 label: Translation.tr("Wallpaper tune"),act: () => GlobalStates.wallTuneOpen = true },
        { icon: "auto_awesome",         label: Translation.tr("Wall effects"),  act: () => GlobalStates.wallEffectVarsOpen = true },
        { icon: "crop",                 label: Translation.tr("Wall position"), act: () => GlobalStates.wallpaperAdjusterOpen = true },

        { icon: "search",               label: Translation.tr("Search"),        act: () => GlobalStates.overviewOpen = true },
        { icon: "dashboard",            label: Translation.tr("Dashboard"),     act: () => GlobalStates.hudOpen = true },
        { icon: "inventory_2",          label: Translation.tr("Shelf"),         act: () => GlobalStates.shelfOpen = true },
        { icon: "widgets",              label: Translation.tr("Quick settings"),act: () => GlobalStates.sidebarRightOpen = true },
        { icon: "forum",                label: Translation.tr("Assistant"),     act: () => GlobalStates.sidebarLeftOpen = true },

        { icon: "draw",                 label: Translation.tr("Draw on screen"),act: () => GlobalStates.screenDrawFullOpen = true },
        { icon: "point_scan",           label: Translation.tr("Crosshair"),     act: () => GlobalStates.crosshairOpen = !GlobalStates.crosshairOpen },
        { icon: "help",                 label: Translation.tr("Keybinds"),      act: () => GlobalStates.cheatsheetOpen = true },
        { icon: "settings",             label: Translation.tr("All settings"),  act: () => SettingsApp.open() },
        { icon: "power_settings_new",   label: Translation.tr("Power"),         act: () => GlobalStates.sessionOpen = true },
    ]

    GlobalShortcut {
        name: "systemHubToggle"
        description: "Toggle the system hub (index of every settings panel)"
        onPressed: GlobalStates.systemHubOpen = !GlobalStates.systemHubOpen
    }

    IpcHandler {
        target: "systemHub"
        function toggle(): void { GlobalStates.systemHubOpen = !GlobalStates.systemHubOpen }
        function open(): void   { GlobalStates.systemHubOpen = true }
        function close(): void  { GlobalStates.systemHubOpen = false }
    }

    Loader {
        active: GlobalStates.systemHubOpen

        sourceComponent: PanelWindow {
            id: win
            // Focused screen only: this is a modal index, and drawing it on
            // every monitor would put a full-screen scrim over a second
            // display you might be watching.
            screen: Hyprland.focusedMonitor
                ? Quickshell.screens.find(s => s.name === Hyprland.focusedMonitor.name) ?? null
                : null
            color: "transparent"
            WlrLayershell.namespace: "quickshell:systemHub"
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
            exclusionMode: ExclusionMode.Ignore
            anchors { top: true; bottom: true; left: true; right: true }

            Component.onCompleted: GlobalFocusGrab.addDismissable(win)
            Component.onDestruction: GlobalFocusGrab.removeDismissable(win)
            Connections {
                target: GlobalFocusGrab
                function onDismissed() { root.close() }
            }

            // Full-bleed scrim, same framing as the session screen: no card,
            // no chrome, the grid IS the screen. Tapping anywhere off a tile
            // cancels, which on a tablet is a target the size of the display.
            Rectangle {
                id: scrim
                anchors.fill: parent
                color: Appearance.colors.colScrim
                opacity: shown ? 1 : 0
                property bool shown: false
                Component.onCompleted: shown = true
                Behavior on opacity { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
                TapHandler { onTapped: root.close() }

                focus: true
                Keys.onEscapePressed: event => { root.close(); event.accepted = true }
            }

            ColumnLayout {
                anchors.centerIn: parent
                width: Math.min(parent.width - 40, 800)
                spacing: 0
                opacity: scrim.shown ? 1 : 0
                scale: scrim.shown ? 1 : 0.96
                Behavior on opacity { NumberAnimation { duration: 180 } }
                Behavior on scale   { NumberAnimation { duration: 240; easing.type: Easing.OutCubic } }

                StyledText {
                    Layout.alignment: Qt.AlignHCenter
                    text: Translation.tr("Everything")
                    font.pixelSize: Appearance.font.pixelSize.huge
                    color: Appearance.colors.colOnLayer0
                    horizontalAlignment: Text.AlignHCenter
                }
                StyledText {
                    Layout.alignment: Qt.AlignHCenter
                    Layout.bottomMargin: 22
                    text: Translation.tr("Up %1 · tap anything to open it").arg(DateTime.uptime)
                        + "\n" + Translation.tr("Esc or tap the background to close")
                    font.pixelSize: Appearance.font.pixelSize.small
                    color: Appearance.colors.colSubtext
                    horizontalAlignment: Text.AlignHCenter
                }

                StyledFlickable {
                    id: flick
                    Layout.fillWidth: true
                    Layout.preferredHeight: Math.min(grid.implicitHeight,
                                                     win.height - 260)
                    contentHeight: grid.implicitHeight
                    clip: true
                    // Touch drags scroll the grid; without a press delay the
                    // tile under your finger swallows the drag and nothing moves.
                    flickableDirection: Flickable.VerticalFlick
                    pressDelay: 60

                    Flow {
                        id: grid
                        width: flick.width
                        spacing: 12

                        Repeater {
                            model: root.entries
                            delegate: RippleButton {
                                id: tile
                                required property var modelData
                                readonly property bool lit: tile.hovered || tile.down || tile.focus

                                implicitWidth: 124
                                implicitHeight: 124
                                // Squircle that becomes a circle when it lights
                                // up — the session screen's signature move, and
                                // the clearest possible "this one" on a touch
                                // screen where there is no cursor to look at.
                                buttonRadius: tile.lit ? implicitWidth / 2
                                                       : Appearance.rounding.verylarge
                                Behavior on buttonRadius {
                                    NumberAnimation { duration: 200; easing.type: Easing.OutCubic }
                                }
                                colBackground: Appearance.colors.colSecondaryContainer
                                colBackgroundHover: Appearance.colors.colPrimary
                                colRipple: Appearance.colors.colPrimaryActive

                                // Close BEFORE acting: several of these are
                                // stacked panels that measure the free width
                                // when they open, and the hub's own surface
                                // would still be counted.
                                onClicked: {
                                    root.close();
                                    Qt.callLater(modelData.act);
                                }

                                // An Item wrapper, then centre inside it. A
                                // ColumnLayout used directly as contentItem is
                                // RESIZED to the control's content area, so its
                                // own centerIn fought the control's sizing and
                                // the icon sat high in the tile.
                                contentItem: Item {
                                  ColumnLayout {
                                    anchors.centerIn: parent
                                    width: parent.width
                                    spacing: 5
                                    MaterialSymbol {
                                        Layout.alignment: Qt.AlignHCenter
                                        text: tile.modelData.icon
                                        iconSize: 38
                                        // Pin the box to the glyph. A text
                                        // item's line box carries the font's
                                        // ascent and descent, so left to size
                                        // itself the icon added invisible
                                        // padding and pushed the pair below
                                        // the tile's centre.
                                        Layout.preferredHeight: 38
                                        verticalAlignment: Text.AlignVCenter
                                        color: tile.lit ? Appearance.m3colors.m3onPrimary
                                                        : Appearance.colors.colOnLayer0
                                    }
                                    // The session screen shows one label at a
                                    // time, for whatever is focused. That works
                                    // for eight actions; with this many it is a
                                    // memory test, and hover does not exist on
                                    // a touch screen — so every tile is named.
                                    StyledText {
                                        Layout.alignment: Qt.AlignHCenter
                                        Layout.maximumWidth: tile.implicitWidth - 12
                                        text: tile.modelData.label
                                        // `smaller`, not `smallest`: at 10px
                                        // these are names you squint at, and
                                        // the label is the only thing telling
                                        // 25 near-identical squares apart.
                                        font.pixelSize: Appearance.font.pixelSize.smaller
                                        color: tile.lit ? Appearance.m3colors.m3onPrimary
                                                        : Appearance.colors.colOnLayer0
                                        horizontalAlignment: Text.AlignHCenter
                                        wrapMode: Text.WordWrap
                                        maximumLineCount: 2
                                        elide: Text.ElideRight
                                    }
                                  }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
