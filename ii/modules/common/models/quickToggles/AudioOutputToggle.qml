import QtQuick
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import Quickshell.Services.Pipewire

// Cycles the default audio sink through every available output device.
// Click once → next sink (and moves all running streams along). Right-click
// opens the full device selector menu (same one the existing AudioToggle
// uses for hasMenu=true).
QuickToggleModel {
    id: root

    // Currently-default sink and a friendly name for the status pill.
    readonly property var defaultSink: Pipewire.defaultAudioSink
    readonly property string currentName:
        defaultSink ? Audio.friendlyDeviceName(defaultSink) : Translation.tr("No output")
    readonly property list<var> devices: Audio.outputDevices

    name: Translation.tr("Audio output")
    statusText: root.currentName
    tooltipText: Translation.tr("Click to switch output device | Right-click for picker")
    toggled: !!defaultSink && devices.length > 1
    available: devices.length > 0

    // Pick an icon that hints which kind of device is currently selected.
    icon: {
        const n = (currentName || "").toLowerCase()
        if (n.includes("headphone") || n.includes("headset") || n.includes("hdb"))
            return "headphones"
        if (n.includes("roland") || n.includes("dj") || n.includes("usb"))
            return "speaker_group"     // external interface / DJ
        if (n.includes("hdmi") || n.includes("display"))
            return "tv"
        if (n.includes("bluetooth") || n.includes("bt"))
            return "bluetooth_audio"
        return "speaker"
    }

    mainAction: () => {
        const list = devices
        if (list.length <= 1) return
        const curId = defaultSink ? defaultSink.id : null
        let idx = list.findIndex(d => d.id === curId)
        if (idx < 0) idx = -1
        // PipeWire reroutes any stream without an explicit target to the new
        // default sink, so VolumeDialogContent.qml:58's pattern of only
        // calling setDefaultSink is sufficient. Don't touch per-stream
        // targetNode — that's not a PwAudio property and pinning streams
        // would prevent future default-sink changes from moving them.
        Audio.setDefaultSink(list[(idx + 1) % list.length])
    }

    // Right-click / long-press → existing device picker dialog
    hasMenu: true
}
