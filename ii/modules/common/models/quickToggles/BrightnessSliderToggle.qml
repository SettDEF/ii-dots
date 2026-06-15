import QtQuick
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets

QuickToggleModel {
    name: Translation.tr("Brightness")
    icon: "brightness_6"
    tooltipText: Translation.tr("Display brightness")
    toggled: false
    available: true
    hasStatusText: false
    mainAction: () => {}
}
