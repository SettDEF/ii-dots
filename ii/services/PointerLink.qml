pragma Singleton
pragma ComponentBehavior: Bound

// Live pointer link health, published by the KinetiX engine.
//
// The engine is the only thing that sees every single report, so it is the only
// honest source for how the link is actually behaving. It already measures the
// inter-report interval to drive the interpolator; this just surfaces it.
//
// A singleton rather than a FileView per panel: the Pointer panel and the
// Bluetooth device card both want these numbers, and two watchers on the same
// /dev/shm file is two sets of wakeups for one stream of data.

import qs.modules.common
import Quickshell
import Quickshell.Io
import QtQuick

Singleton {
    id: root

    readonly property string telemetryPath: "/dev/shm/kinetix-telemetry.json"

    property var data: ({})
    /// True once the engine has published anything. Distinguishes "engine not
    /// running" from "mouse is simply still".
    property bool available: false

    readonly property real speed:      root.data.live_speed ?? 0
    readonly property real gain:       root.data.live_gain ?? 0
    readonly property real angle:      root.data.live_angle ?? 0
    readonly property real reportMs:   root.data.report_ms ?? 0
    readonly property real batchedPct: root.data.batched_pct ?? 0

    /// Reports per second. The headline number for "is this link any good".
    readonly property int hz: root.reportMs > 0.01 ? Math.round(1000 / root.reportMs) : 0

    /// Rough quality bands. 1000Hz is a gaming mouse; 125Hz is USB default;
    /// Bluetooth HID typically lands near 111Hz and jitters badly.
    readonly property string quality: {
        if (!root.available || root.hz <= 0) return "unknown";
        if (root.hz >= 500) return "excellent";
        if (root.hz >= 250) return "good";
        if (root.hz >= 150) return "fair";
        return "poor";
    }

    /// Reports arriving in bursts rather than evenly. Feels like stutter even
    /// when the average rate looks acceptable, so it is worth showing
    /// separately from `hz`.
    readonly property bool bursty: root.available && root.batchedPct > 15

    FileView {
        id: telemetryFile
        // Qt.resolvedUrl, not a bare path — a bare "/dev/shm/..." silently
        // never loads. That bug cost an afternoon in LogiTune.
        path: Qt.resolvedUrl(root.telemetryPath)
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            try {
                root.data = JSON.parse(telemetryFile.text() || "{}");
                root.available = true;
            } catch (e) {
                // A half-written file is not a dead engine.
            }
        }
        onLoadFailed: root.available = false
    }
}
