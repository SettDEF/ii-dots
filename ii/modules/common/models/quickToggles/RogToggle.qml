import QtQuick
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets

QuickToggleModel {
    name: Translation.tr("ROG")
    icon: "memory"
    tooltipText: Translation.tr("ROG performance & fans")
    toggled: false
    available: true
    hasStatusText: false
    mainAction: () => {}
}
