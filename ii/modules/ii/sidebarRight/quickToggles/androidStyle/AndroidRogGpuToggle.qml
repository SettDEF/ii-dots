import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.models.quickToggles
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts

AndroidQuickToggleButton {
    id: root
    toggleModel: RogGpuToggle {}
    parentContainerType: "rog"
    compactExpanded: true
    // Keep the tile background neutral even when model.toggled is true —
    // our widget renders its own accent on the icon block / thumb.
    colBackgroundToggled: colBackground
    colBackgroundToggledHover: colBackgroundHover
    colBackgroundToggledActive: colBackgroundActive
    expandedDelegate: Component {
        Item {
            implicitHeight: 56
            RogWideBtn {
                anchors.fill: parent
                iconName:   "memory"
                label:      Translation.tr("GPU")
                statusText: Rog.gpuMode === "AsusMuxDiscreet" ? "dGPU" : Rog.gpuMode
                toggled:    Rog.gpuMode !== "Integrated"
                onTap: {
                    const m = ["Integrated","Hybrid","AsusMuxDiscreet"]
                    const i = Math.max(0, m.indexOf(Rog.gpuMode))
                    Rog.setGpuMode(m[(i + 1) % m.length])
                }
            }
        }
    }
}
