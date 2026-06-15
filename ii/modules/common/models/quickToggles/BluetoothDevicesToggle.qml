import QtQuick
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets

QuickToggleModel {
    name: Translation.tr("BT Devices")
    icon: "devices_other"
    tooltipText: Translation.tr("Paired Bluetooth devices")
    toggled: false
    available: true
    hasStatusText: false
    mainAction: () => {}
}
