import QtQuick
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets

QuickToggleModel {
    name: Translation.tr("Sliders")
    icon: "tune"
    statusText: Translation.tr("Volume / brightness")
    tooltipText: Translation.tr("System sliders")
    toggled: false
    available: true
    hasStatusText: false
    mainAction: () => {}
}
