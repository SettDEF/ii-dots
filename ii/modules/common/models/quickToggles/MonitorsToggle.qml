import QtQuick
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets

QuickToggleModel {
    name: Translation.tr("Monitors")
    statusText: {
        switch (MonitorManager.activePreset) {
            case "internal":  return Translation.tr("Internal only")
            case "external":  return Translation.tr("External only")
            case "mirror":    return Translation.tr("Mirroring")
            case "extend":    return Translation.tr("Extended (%1)")
                .arg(MonitorManager.friendly.filter(m => !m.disabled).length)
            default:          return Translation.tr("No monitors")
        }
    }
    tooltipText: Translation.tr("Manage monitors | Right-click to open")
    icon: {
        switch (MonitorManager.activePreset) {
            case "mirror":   return "screen_share"
            case "extend":   return "splitscreen_right"
            case "external": return "monitor"
            default:         return "laptop"
        }
    }

    // "Toggled" = at least one external panel currently active.
    toggled: MonitorManager.anyExternalActive

    // Tap toggles every external panel between enabled / disabled. If any
    // are active, disable them all; otherwise enable all known externals.
    mainAction: () => {
        const externals = MonitorManager.externalMonitors
        if (externals.length === 0) return
        const anyOn = externals.some(m => !m.disabled)
        externals.forEach(m => {
            if (anyOn) MonitorManager.disable(m.name)
            else MonitorManager.enable(m.name)
        })
    }

    hasMenu: true
}
