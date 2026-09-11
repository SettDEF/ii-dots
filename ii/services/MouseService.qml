pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import qs

Singleton {
    id: root

    property bool enabled: true

    FileView {
        id: statusFile
        path: "/dev/shm/logitune-cli-status.json"
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            try {
                const data = JSON.parse(statusFile.text())
                GlobalStates.gestureMenuOpen = data.gesture_active || false
                GlobalStates.gestureDirection = data.gesture_direction || "None"
            } catch (e) {
                // Ignore parse errors on transient writes
            }
        }
    }
}
