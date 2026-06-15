import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.models.quickToggles
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts

AndroidQuickToggleButton {
    id: root
    toggleModel: RogBatteryToggle {}
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
                iconName:   "battery_saver"
                label:      Translation.tr("Battery")
                statusText: Rog.batteryLimit + "%"
                toggled:    Rog.batteryLimit < 100
                onTap: {
                    const stops = [80, 90, 100]
                    let i = stops.indexOf(Rog.batteryLimit)
                    if (i < 0) i = stops.length - 1
                    Rog.setBatteryLimit(stops[(i + 1) % stops.length])
                }
            }
        }
    }
}
