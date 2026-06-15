pragma Singleton
pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Io

/**
 * Sleep timer — suspends the system after a chosen delay.
 *
 * State lives here (a singleton) rather than in the quick-toggle so the
 * countdown keeps running when the quick-settings panel is closed.
 */
Singleton {
    id: root

    // Selectable durations, in minutes.
    readonly property var durations: [15, 30, 45, 60, 90, 120]
    property int durationIndex: 1                                  // default 30 min
    readonly property int durationMinutes: durations[durationIndex]

    property bool running: false
    property int remainingSeconds: 0

    function start() {
        root.remainingSeconds = root.durationMinutes * 60
        root.running = true
    }
    function cancel() {
        root.running = false
        root.remainingSeconds = 0
    }
    function toggle() {
        if (root.running) root.cancel()
        else root.start()
    }
    // Step to the next preset duration; restart the countdown if active.
    function cycleDuration() {
        root.durationIndex = (root.durationIndex + 1) % root.durations.length
        if (root.running) root.start()
    }

    // "1h 5m", "12m 30s" or "45s".
    function formatRemaining() {
        let s = root.remainingSeconds
        const h = Math.floor(s / 3600); s -= h * 3600
        const m = Math.floor(s / 60);   s -= m * 60
        if (h > 0) return `${h}h ${m}m`
        if (m > 0) return `${m}m ${s.toString().padStart(2, "0")}s`
        return `${s}s`
    }

    Timer {
        running: root.running
        interval: 1000
        repeat: true
        onTriggered: {
            root.remainingSeconds -= 1
            if (root.remainingSeconds <= 0) {
                root.running = false
                suspendProc.running = true
            }
        }
    }

    Process {
        id: suspendProc
        command: ["systemctl", "suspend"]
    }
}
