import qs
import QtQuick

// Loads a StackedSettingsPanel and keeps it alive through its fade-out, so
// the exit animation renders instead of the panel blinking out on close.
//   StackedPanelLoader { isOpen: GlobalStates.fooOpen; sourceComponent: ... }
Loader {
    id: root

    required property bool isOpen  // bind to the GlobalStates boolean

    property bool lingering: false  // stay loaded a moment past close
    active: root.isOpen || root.lingering

    onIsOpenChanged: {
        if (root.isOpen) {
            exitTimer.stop();
            root.lingering = false;
        } else if (root.item) {
            root.lingering = true;
            if (typeof root.item.playExit === "function")
                root.item.playExit();
            exitTimer.restart();
        }
    }

    Timer {
        id: exitTimer
        interval: (root.item && root.item.exitDuration !== undefined)
                  ? root.item.exitDuration + 20 : 200
        onTriggered: root.lingering = false
    }
}
