import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets

Scope {
    id: root
    
    LazyLoader {
        id: barLoader
        active: GlobalStates.barOpen
        component: Variants {
            model: Quickshell.screens
            delegate: PanelWindow { // Bar window
                id: barRoot
                required property var modelData
                screen: modelData
                exclusionMode: ExclusionMode.Ignore
                exclusiveZone: implicitHeight
                WlrLayershell.namespace: "quickshell:bar"

                anchors {
                    left: true
                    right: true
                    bottom: Config.options.waffles.bar.bottom
                    top: !Config.options.waffles.bar.bottom
                }

                color: "transparent"
                implicitHeight: content.implicitHeight
                implicitWidth: content.implicitWidth

                WaffleBarContent {
                    id: content
                    anchors.fill: parent
                }
            }
        }
    }

    IpcHandler {
        target: "bar"

        function toggle(): void {
            GlobalStates.barOpen = !GlobalStates.barOpen
        }

        function close(): void {
            GlobalStates.barOpen = false
        }

        function open(): void {
            GlobalStates.barOpen = true
        }
    }

    // Super+N like Windows: the Nth taskbar app (focus, cycle its windows, or launch)
    IpcHandler {
        target: "taskbar"

        function activate(n: int): string {
            const apps = TaskbarApps.apps.filter(app => app.appId !== "SEPARATOR");
            const app = apps[n - 1];
            if (!app) return "none";
            const wins = app.toplevels;
            if (wins.length === 0) {
                AppLaunch.launch(DesktopEntries.heuristicLookup(app.appId));
                return "ok";
            }
            const cur = wins.findIndex(t => t.activated);
            wins[(cur + 1) % wins.length].activate();
            return "ok";
        }
    }

    GlobalShortcut {
        name: "barToggle"
        description: "Toggles bar on press"

        onPressed: {
            GlobalStates.barOpen = !GlobalStates.barOpen;
        }
    }

    GlobalShortcut {
        name: "barOpen"
        description: "Opens bar on press"

        onPressed: {
            GlobalStates.barOpen = true;
        }
    }

    GlobalShortcut {
        name: "barClose"
        description: "Closes bar on press"

        onPressed: {
            GlobalStates.barOpen = false;
        }
    }
}
