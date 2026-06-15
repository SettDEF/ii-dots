import QtQuick
import qs
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets

QuickToggleModel {
    id: root
    name: Translation.tr("Tablet")
    icon: toggled ? "tablet_mac" : "laptop"
    toggled: Config.options?.tabletMode ?? false
    statusText: toggled ? Translation.tr("On") : Translation.tr("Off")
    tooltipText: Translation.tr("Tablet mode — bigger bar, auto-OSK in launcher")

    mainAction: () => {
        Config.options.tabletMode = !Config.options.tabletMode
    }
}
