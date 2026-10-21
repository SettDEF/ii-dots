import QtQuick
import qs.services

// Put in a shell window: counts its frames for FrameStats, only while it records.
Item {
    id: probe
    required property string name
    Connections {
        target: probe.parent?.Window.window ?? null
        enabled: FrameStats.recording
        ignoreUnknownSignals: true
        function onFrameSwapped() { FrameStats.add(probe.name); }
    }
}
