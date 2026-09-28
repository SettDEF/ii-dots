pragma ComponentBehavior: Bound
import qs
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import qs.services
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Qt5Compat.GraphicalEffects
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland

// Options toolbar
Toolbar {
    id: root

    // Use a synchronizer on these
    property var action
    property var selectionMode
    // Signals
    signal dismiss()

    ToolbarTabBar {
        id: tabBar
        tabButtonList: [
            {"icon": "activity_zone", "name": Translation.tr("Rect")},
            {"icon": "gesture", "name": Translation.tr("Circle")}
        ]
        // Synced by hand, not bound: binding currentIndex from selectionMode
        // while writing it back is a loop. Assign only on a real difference.
        Component.onCompleted: tabBar.syncFromMode()

        function syncFromMode(): void {
            const want = root.selectionMode === RegionSelection.SelectionMode.RectCorners ? 0 : 1;
            if (tabBar.currentIndex !== want) tabBar.setCurrentIndex(want);
        }

        Connections {
            target: root
            function onSelectionModeChanged() { tabBar.syncFromMode() }
        }

        onCurrentIndexChanged: {
            const want = currentIndex === 0 ? RegionSelection.SelectionMode.RectCorners
                                            : RegionSelection.SelectionMode.Circle;
            if (root.selectionMode !== want) root.selectionMode = want;
        }
    }
}
