import QtQuick
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets

QuickToggleModel {
    readonly property var modes: ["Integrated", "Hybrid", "AsusMuxDiscreet"]
    name: Translation.tr("GPU")
    icon: "memory"
    statusText: Rog.gpuMode === "AsusMuxDiscreet" ? "dGPU" : Rog.gpuMode
    tooltipText: Translation.tr("Cycle GPU mode")
    toggled: Rog.gpuMode !== "Integrated"
    available: true
    mainAction: () => {
        const i = Math.max(0, modes.indexOf(Rog.gpuMode))
        Rog.setGpuMode(modes[(i + 1) % modes.length])
    }
}
