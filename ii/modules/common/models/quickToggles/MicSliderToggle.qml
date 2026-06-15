import QtQuick
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets

QuickToggleModel {
    name: Translation.tr("Mic")
    icon: "mic"
    tooltipText: Translation.tr("Input volume")
    toggled: false
    available: true
    hasStatusText: false
    mainAction: () => {}
}
