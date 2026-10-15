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
import Quickshell.Widgets
import Quickshell.Hyprland

Scope {
    id: root

    function dismiss() {
        GlobalStates.regionSelectorOpen = false
    }

    property var action: RegionSelection.SnipAction.Copy
    property var selectionMode: RegionSelection.SelectionMode.RectCorners
    
    Variants {
        model: Quickshell.screens
        delegate: Loader {
            id: regionSelectorLoader
            required property var modelData
            active: GlobalStates.regionSelectorOpen

            sourceComponent: RegionSelection {
                screen: regionSelectorLoader.modelData
                onDismiss: root.dismiss()
                onDelayed: seconds => root.startDelayed(seconds)
                action: root.action
                selectionMode: root.selectionMode
            }
        }
    }

    // ── Delay timer ──────────────────────────────────────────────────────
    // Close the overlay, count down, then open it again with a FRESH capture
    // (menus, hover states). Same action and selection mode as before.
    property int countdown: 0
    function startDelayed(seconds) {
        GlobalStates.regionSelectorOpen = false;
        root.countdown = Math.max(1, seconds);
        countdownTimer.restart();
    }
    Timer {
        id: countdownTimer
        interval: 1000
        repeat: true
        onTriggered: {
            root.countdown -= 1;
            if (root.countdown > 0) return;
            stop();
            // Let the pill unmap first, or it lands in the capture.
            reopenTimer.restart();
        }
    }
    Timer {
        id: reopenTimer
        interval: 150
        onTriggered: GlobalStates.regionSelectorOpen = true
    }
    Variants {
        model: Quickshell.screens
        delegate: Loader {
            id: countdownLoader
            required property var modelData
            active: root.countdown > 0 && Hyprland.focusedMonitor?.name === countdownLoader.modelData.name
            sourceComponent: PanelWindow {
                screen: countdownLoader.modelData
                WlrLayershell.namespace: "quickshell:shotCountdown"
                WlrLayershell.layer: WlrLayer.Overlay
                exclusionMode: ExclusionMode.Ignore
                color: "transparent"
                anchors.top: true
                margins.top: 60
                implicitWidth: 72
                implicitHeight: 72
                mask: Region {}
                Rectangle {
                    anchors.fill: parent
                    radius: width / 2
                    color: Qt.alpha(Appearance.colors.colLayer0, 0.85)
                    border.width: 1
                    border.color: Appearance.colors.colLayer0Border
                    StyledText {
                        anchors.centerIn: parent
                        text: root.countdown
                        font.pixelSize: Appearance.font.pixelSize.huge
                        font.weight: Font.DemiBold
                        color: Appearance.colors.colOnLayer0
                    }
                }
            }
        }
    }

    function screenshot() {
        root.action = RegionSelection.SnipAction.Copy
        root.selectionMode = RegionSelection.SelectionMode.RectCorners
        GlobalStates.regionSelectorOpen = true
    }

    function search() {
        root.action = RegionSelection.SnipAction.Search
        if (Config.options.search.imageSearch.useCircleSelection) {
            root.selectionMode = RegionSelection.SelectionMode.Circle
        } else {
            root.selectionMode = RegionSelection.SelectionMode.RectCorners
        }
        GlobalStates.regionSelectorOpen = true
    }

    function ocr() {
        root.action = RegionSelection.SnipAction.CharRecognition
        root.selectionMode = RegionSelection.SelectionMode.RectCorners
        GlobalStates.regionSelectorOpen = true
    }

    function record() {
        root.action = RegionSelection.SnipAction.Record
        root.selectionMode = RegionSelection.SelectionMode.RectCorners
        GlobalStates.regionSelectorOpen = true
    }

    function recordWithSound() {
        root.action = RegionSelection.SnipAction.RecordWithSound
        root.selectionMode = RegionSelection.SelectionMode.RectCorners
        GlobalStates.regionSelectorOpen = true
    }

    /// Drag a rectangle; the focused window becomes exactly that rectangle.
    /// The manual half of a tiling WM: the cases where no automatic layout is
    /// the one you want.
    function snapWindow() {
        root.action = RegionSelection.SnipAction.SnapWindow
        root.selectionMode = RegionSelection.SelectionMode.RectCorners
        GlobalStates.regionSelectorOpen = true
    }

    function lens() {
        root.action = RegionSelection.SnipAction.AttachToAi
        root.selectionMode = RegionSelection.SelectionMode.RectCorners
        GlobalStates.regionSelectorOpen = true
    }

    IpcHandler {
        target: "region"

        function screenshot() {
            root.screenshot()
        }
        /// `region screenshotIn 5`: a region shot whose capture waits N seconds.
        function screenshotIn(seconds: int) {
            root.action = RegionSelection.SnipAction.Copy
            root.selectionMode = RegionSelection.SelectionMode.RectCorners
            root.startDelayed(seconds)
        }
        function snap() {
            root.snapWindow()
        }
        function search() {
            root.search()
        }
        function ocr() {
            root.ocr()
        }
        function record() {
            root.record()
        }
        function recordWithSound() {
            root.recordWithSound()
        }
        function lens() {
            root.lens()
        }
    }

    GlobalShortcut {
        name: "regionScreenshot"
        description: "Takes a screenshot of the selected region"
        onPressed: root.screenshot()
    }
    GlobalShortcut {
        name: "regionSearch"
        description: "Searches the selected region"
        onPressed: root.search()
    }
    GlobalShortcut {
        name: "regionOcr"
        description: "Recognizes text in the selected region"
        onPressed: root.ocr()
    }
    GlobalShortcut {
        name: "regionRecord"
        description: "Records the selected region"
        onPressed: root.record()
    }
    GlobalShortcut {
        name: "regionRecordWithSound"
        description: "Records the selected region with sound"
        onPressed: root.recordWithSound()
    }
    GlobalShortcut {
        name: "regionLens"
        description: "Visual search: crops a region and attaches it to the AI chat"
        onPressed: root.lens()
    }
}
