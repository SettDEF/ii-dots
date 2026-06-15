import QtQuick
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets

QuickToggleModel {
    name: Translation.tr("Profile")
    icon: {
        const p = Rog.profile
        if (p === "Quiet") return "bedtime"
        if (p === "Balanced") return "balance"
        return "speed"
    }
    statusText: Rog.profile
    tooltipText: Translation.tr("Cycle ROG performance profile")
    toggled: Rog.profile === "Performance"
    available: true
    mainAction: () => {
        const ps = Rog.profiles
        if (!ps || ps.length === 0) return
        const i = Math.max(0, ps.indexOf(Rog.profile))
        Rog.setProfile(ps[(i + 1) % ps.length])
    }
}
