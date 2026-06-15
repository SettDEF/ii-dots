import QtQuick
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets

QuickToggleModel {
    name: Translation.tr("Volume")
    icon: "volume_up"
    tooltipText: Translation.tr("Output volume")
    toggled: false
    available: true
    hasStatusText: false
    mainAction: () => {}
}
