import QtQuick
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets

QuickToggleModel {
    name: Translation.tr("Phone")
    icon: "smartphone"
    tooltipText: Translation.tr("KDE Connect")
    toggled: false
    available: true
    hasStatusText: false
    mainAction: () => {}
}
