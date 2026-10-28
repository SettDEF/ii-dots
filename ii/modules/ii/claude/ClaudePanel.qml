pragma ComponentBehavior: Bound
import qs
import qs.modules.common
import QtQuick
import Quickshell
import Quickshell.Wayland

/**
 * Claude at the right edge: claude-ui's own panel (~/.local/share/claude-ui-app/Panel.qml, the same
 * sessions as the Claude window and zett), loaded by a Loader so a broken install never stops the shell.
 * Keys after a click; Esc closes. Toggle: `qs -c ii ipc call claude toggle`, Super+Shift+I.
 */
Scope {
    id: root
    PanelWindow {
        id: win
        visible: GlobalStates.claudeOpen
        anchors { right: true; top: true; bottom: true }
        implicitWidth: 560
        exclusiveZone: 0
        color: "transparent"
        WlrLayershell.namespace: "quickshell:claude"
        WlrLayershell.layer: WlrLayer.Top
        property bool keys: false
        WlrLayershell.keyboardFocus: keys ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None
        onVisibleChanged: keys = false
        mask: Region { item: card }

        Rectangle {
            id: card
            anchors { fill: parent; margins: 12 }
            radius: Appearance.rounding.large
            color: Appearance.m3colors.m3background
            border.width: 1; border.color: Appearance.colors.colLayer0Border
            clip: true
            opacity: GlobalStates.claudeOpen ? 1 : 0
            transform: Translate { x: GlobalStates.claudeOpen ? 0 : 40; Behavior on x { NumberAnimation { duration: 260; easing.type: Easing.OutCubic } } }
            Behavior on opacity { NumberAnimation { duration: 180 } }

            PointHandler { acceptedButtons: Qt.AllButtons; onActiveChanged: if (active && !win.keys) { win.keys = true; Qt.callLater(() => { if (front.item) front.item.focusInput() }) } }
            readonly property bool winActive: Window.active
            onWinActiveChanged: if (!winActive) win.keys = false
            Keys.onEscapePressed: GlobalStates.claudeOpen = false

            Loader {
                id: front
                anchors.fill: parent
                source: "file://" + Quickshell.env("HOME") + "/.local/share/claude-ui-app/Panel.qml"
                onLoaded: item.openWindow.connect(() => GlobalStates.claudeOpen = false)
            }
            Text {
                visible: front.status === Loader.Error
                anchors.centerIn: parent
                text: "claude-ui is not installed: run claude-ui/install.sh"
                color: Appearance.colors.colSubtext
            }
        }
    }
}
