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
    /// Close now, capture again after this many seconds.
    signal delayed(int seconds)

    // Keyboard: ←/→ walk Rect, Circle, 3s, 5s, 10s; Enter or Space fires a delay.
    readonly property var delays: [3, 5, 10]
    property int keyIndex: -1
    function moveKey(step) {
        const n = 2 + root.delays.length;
        root.keyIndex = root.keyIndex < 0 ? (step > 0 ? 0 : n - 1) : (root.keyIndex + step + n) % n;
        if (root.keyIndex < 2)
            root.selectionMode = root.keyIndex === 0 ? RegionSelection.SelectionMode.RectCorners
                                                     : RegionSelection.SelectionMode.Circle;
    }
    function activateKey() {
        if (root.keyIndex >= 2) root.delayed(root.delays[root.keyIndex - 2]);
    }

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

    // Delay: close, count down, capture fresh — for menus and hover states.
    RowLayout {
        Layout.fillHeight: true
        spacing: 2
        MaterialSymbol {
            Layout.leftMargin: 6
            text: "timer"
            iconSize: 20
            color: Appearance.colors.colOnSurfaceVariant
        }
        Repeater {
            model: root.delays
            delegate: ToolbarButton {
                id: delayBtn
                required property int modelData
                required property int index
                toggled: root.keyIndex === delayBtn.index + 2
                implicitWidth: delayText.implicitWidth + 20
                onClicked: root.delayed(delayBtn.modelData)
                contentItem: StyledText {
                    id: delayText
                    anchors.centerIn: parent
                    text: delayBtn.modelData + "s"
                    font.pixelSize: Appearance.font.pixelSize.small
                    color: Appearance.colors.colOnSurfaceVariant
                }
                StyledToolTip { text: Translation.tr("Capture again in %1 seconds").arg(delayBtn.modelData) }
            }
        }
    }
}
