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

    // Absolute wall-clock deadline, not a tick count. The countdown used to do
    // `remainingSeconds -= 1` once per Timer tick, but Qt does not replay missed
    // ticks: a blocked event loop or a starved process yields ONE late tick, not
    // the several that were due. Under heavy load the timer therefore ran slower
    // than real time, and across a suspend it did not advance at all.
    property double deadlineMs: 0

    function start() {
        root.deadlineMs = Date.now() + root.durationMinutes * 60000
        root.remainingSeconds = root.durationMinutes * 60
        root.running = true
    }
    function cancel() {
        root.running = false
        root.remainingSeconds = 0
        root.deadlineMs = 0
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
        id: tick
        running: root.running
        interval: 1000
        repeat: true
        // Last time this fired, to spot the clock jumping (i.e. we were asleep).
        property double lastTickMs: 0
        onRunningChanged: if (running) lastTickMs = Date.now()
        onTriggered: {
            const now = Date.now()
            const gap = now - tick.lastTickMs
            tick.lastTickMs = now

            // A gap far larger than the interval means the machine was suspended
            // (by hypridle, the lid, or anything else) rather than merely busy.
            // Firing here would suspend again the instant you woke it up, so
            // stand down instead and let the user re-arm deliberately.
            if (gap > 60000) {
                root.cancel()
                return
            }

            root.remainingSeconds = Math.max(0, Math.ceil((root.deadlineMs - now) / 1000))
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
