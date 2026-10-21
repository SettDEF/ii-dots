pragma Singleton

import QtQuick
import Quickshell

// Frames each shell window sends while a measurement runs (diag framesStart / frames).
Singleton {
    id: root
    property bool recording: false
    property real startMs: 0
    property var counts: ({})

    function start() {
        counts = {};
        startMs = Date.now();
        recording = true;
    }
    function add(name) {
        counts[name] = (counts[name] ?? 0) + 1;
    }
    // Frames per second for each window since start(), busiest first; stops the measurement.
    function report() {
        const s = Math.max((Date.now() - startMs) / 1000, 0.001);
        recording = false;
        const rows = Object.keys(counts).map(k => [k, counts[k] / s]).sort((a, b) => b[1] - a[1]);
        if (!rows.length) return `no frames in ${s.toFixed(1)} s`;
        return rows.map(r => `${r[1].toFixed(1).padStart(6)} fps  ${r[0]}`).join("\n") + `\n(over ${s.toFixed(1)} s)`;
    }
}
