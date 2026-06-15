// Native screenshot annotation popup. Replaces swappy.
// Lazy-loaded via LazyPanelLoader so it costs zero RAM until you open a snip.
pragma ComponentBehavior: Bound
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland

Scope {
    id: root

    Loader {
        active: GlobalStates.screenshotEditorOpen
        sourceComponent: PanelWindow {
            id: win
            color: "transparent"
            WlrLayershell.namespace: "quickshell:screenshotEditor"
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand
            exclusionMode: ExclusionMode.Ignore
            // Same shape as ScreenDrawSidebar — left-anchored, vertically centered.
            anchors { left: true }
            implicitWidth: 520
            implicitHeight: 720

            Component.onCompleted: GlobalFocusGrab.addDismissable(win)
            Component.onDestruction: GlobalFocusGrab.removeDismissable(win)
            Connections {
                target: GlobalFocusGrab
                function onDismissed() { GlobalStates.screenshotEditorOpen = false }
            }

            ScreenshotEditorContent {
                anchors.fill: parent
                imagePath: GlobalStates.screenshotEditorPath
                onCloseRequested: GlobalStates.screenshotEditorOpen = false
            }
        }
    }

    // IPC entry — ScreenshotAction.qml's Edit branch calls this with the
    // path of the freshly-cropped image. Replaces the `swappy -f -` invocation.
    IpcHandler {
        target: "screenshotEditor"
        function open(path: string): void {
            GlobalStates.screenshotEditorPath = path
            GlobalStates.screenshotEditorOpen = true
        }
        function close(): void {
            GlobalStates.screenshotEditorOpen = false
        }
    }
}
