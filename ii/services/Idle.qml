pragma Singleton
import qs.modules.common
import QtQuick
import Quickshell
import Quickshell.Wayland

/**
 * A nice wrapper for date and time strings.
 */
Singleton {
    id: root

    property bool inhibit: false

    Connections {
        target: Persistent
        function onReadyChanged() {
            if (!Persistent.isNewHyprlandInstance) {
                root.inhibit = Persistent.states.idle.inhibit;
            } else {
                Persistent.states.idle.inhibit = root.inhibit;
            }
        }
    }

    function toggleInhibit(active = null) {
        if (active !== null) {
            root.inhibit = active;
        } else {
            root.inhibit = !root.inhibit;
        }
        Persistent.states.idle.inhibit = root.inhibit;
    }

    // The inhibitor needs a surface. It is created only WHILE inhibiting:
    // a PanelWindow made up front (as before) broke every other program that
    // imports these services without a layer-shell backend — the tinct-cast
    // editor among them: "No PanelWindow backend loaded" took the whole
    // services module down and the editor never opened.
    LazyLoader {
        id: inhibitWindow
        active: root.inhibit
        PanelWindow {
            implicitWidth: 0
            implicitHeight: 0
            color: "transparent"
            anchors {
                right: true
                bottom: true
            }
            // not interactable
            mask: Region {
                item: null
            }
        }
    }

    IdleInhibitor {
        id: idleInhibitor
        enabled: root.inhibit && inhibitWindow.item !== null
        window: inhibitWindow.item
    }
}
