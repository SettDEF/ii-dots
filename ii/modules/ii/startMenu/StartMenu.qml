// StartMenu — Windows-style launcher: search, pinned/frequent apps, all
// apps and power actions. One instance per screen, shown above the dock.
//
// Opened by GlobalStates.startMenuOpen — driven by Super+Space
// (panelFamilies/Shortcuts.qml), the "startMenu" IpcHandler, or the dock's
// apps-grid button. Structure mirrors modules/ii/mouseMenu/MouseMenu.qml and
// modules/ii/keybindsHint/KeybindsHint.qml: a full-width bottom-anchored
// PanelWindow whose mask is just the visible card, centred over the strip.
pragma ComponentBehavior: Bound
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland

Scope {
    id: root

    // Fresh search every time the menu opens, so it never reappears mid-query.
    Connections {
        target: GlobalStates
        function onStartMenuOpenChanged() {
            if (GlobalStates.startMenuOpen)
                LauncherSearch.query = ""
        }
    }

    Variants {
        model: Quickshell.screens

        PanelWindow {
            id: panelWindow
            required property var modelData
            screen: modelData
            visible: GlobalStates.startMenuOpen
            exclusionMode: ExclusionMode.Ignore
            exclusiveZone: 0
            color: "transparent"
            WlrLayershell.namespace: "quickshell:startMenu"
            WlrLayershell.keyboardFocus: visible ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None

            anchors.bottom: true
            anchors.left: true
            anchors.right: true
            // Follows the dock: no clearance when it is off or at the top.
            readonly property bool dockBelow: (Config.options?.dock.enable ?? false)
                && (Config.options?.dock.position ?? "bottom") !== "top"
            margins.bottom: !dockBelow ? Appearance.sizes.hyprlandGapsOut
                : (Config.options?.dock.height ?? 60)
                  + Appearance.sizes.elevationMargin + Appearance.sizes.hyprlandGapsOut
                  + ((Config.options?.dock.floating ?? true) ? (Config.options?.dock.floatingMargin ?? 8) : 0)
            implicitHeight: card.implicitHeight

            mask: Region { item: card }

            onVisibleChanged: {
                if (visible)
                    GlobalFocusGrab.addDismissable(panelWindow)
                else
                    GlobalFocusGrab.removeDismissable(panelWindow)
            }
            Component.onDestruction: GlobalFocusGrab.removeDismissable(panelWindow)
            Connections {
                target: GlobalFocusGrab
                function onDismissed() { GlobalStates.startMenuOpen = false }
            }

            StyledRectangularShadow { target: card }

            Rectangle {
                id: card
                anchors.centerIn: parent
                implicitWidth: 480
                implicitHeight: 600
                radius: Appearance.rounding.large
                // colLayer0Base, not colLayer2 — the layer colours are
                // computed with `solveOverlayColor(..., 1 - contentTransparency)`
                // and are meant to sit ON a background, not to be one. Using
                // colLayer2 here let the desktop show straight through the
                // menu, which made the text unreadable. Every other panel in
                // this shell paints colLayer0Base for the same reason.
                color: Appearance.colors.colLayer0Base
                border.width: 1
                border.color: Appearance.colors.colLayer0Border

                focus: panelWindow.visible
                Keys.onEscapePressed: GlobalStates.startMenuOpen = false

                StartMenuContent {
                    anchors.fill: parent
                    anchors.margins: 16
                }
            }
        }
    }
}
