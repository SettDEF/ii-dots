import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.models.quickToggles
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts

AndroidQuickToggleButton {
    id: root
    toggleModel: RogChargeToggle {}
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
                iconName:   "bolt"
                label:      Translation.tr("Charge")
                statusText: ["Default","Balanced","Full"][Rog.chargeMode] ?? "Default"
                toggled:    Rog.chargeMode > 0
                onTap: Rog.setChargeMode((Rog.chargeMode + 1) % 3)
            }
        }
    }
}
