import QtQuick
import qs.services
import qs.modules.common
import qs.modules.common.functions

QuickToggleModel {
    name: Translation.tr("KDE Connect")
    statusText: {
        const d = KdeConnectService.firstDevice
        if (!d) return Translation.tr("No devices")
        const bat = d.battery >= 0 ? ` ${d.battery}%${d.charging ? " ⚡" : ""}` : ""
        return d.name + bat
    }
    tooltipText: Translation.tr("Click to open phone controls — right-click to ring")

    icon: KdeConnectService.anyConnected ? "smartphone" : "phonelink_off"
    available: true
    toggled: KdeConnectService.anyConnected

    // Click → opens the dialog (handled by the wrapper button via altAction)
    mainAction: () => {
        // No-op; the right-side panel triggers the dialog through altAction.
    }
    hasMenu: true
}
