import QtQuick
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets

QuickToggleModel {
    readonly property var labels: ["Default", "Balanced", "Full"]
    name: Translation.tr("Charge")
    icon: "bolt"
    statusText: labels[Rog.chargeMode] ?? "Default"
    tooltipText: Translation.tr("Cycle charge mode")
    toggled: Rog.chargeMode > 0
    available: true
    mainAction: () => Rog.setChargeMode((Rog.chargeMode + 1) % labels.length)
}
