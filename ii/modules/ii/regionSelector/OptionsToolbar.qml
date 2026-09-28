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
        /*
         * Synced in both directions by hand, not by a binding.
         *
         * `currentIndex: <from selectionMode>` plus an onCurrentIndexChanged
         * that WRITES selectionMode is a cycle: the write re-evaluates the
         * binding that caused it, and Qt reported it as a binding loop on
         * currentIndex every time this toolbar was built. Assigning only when
         * the value actually differs breaks it — each direction stops after
         * one hop instead of handing control back.
         */
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
