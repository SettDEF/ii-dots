import QtQuick
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets

QuickToggleModel {
    // Cycles through three common battery-limit presets on click.
    readonly property var stops: [80, 90, 100]
    name: Translation.tr("Battery")
    icon: "battery_saver"
    statusText: Rog.batteryLimit + "%"
    tooltipText: Translation.tr("Cycle battery charge limit")
    toggled: Rog.batteryLimit < 100
    available: true
    mainAction: () => {
        let i = stops.indexOf(Rog.batteryLimit)
        if (i < 0) i = stops.length - 1
        Rog.setBatteryLimit(stops[(i + 1) % stops.length])
    }
}
