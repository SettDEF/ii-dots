import QtQuick
import qs
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets

QuickToggleModel {
    id: root
    name: Translation.tr("Offload")
    icon: "drive_file_move"
    statusText: {
        const linked = Offload.folders.filter(f => f.state === "linked").length
        const total = Offload.folders.length
        if (!Offload.mounted) return Translation.tr("Drive offline")
        if (total === 0) return Translation.tr("—")
        return Translation.tr("%1/%2 linked").arg(linked).arg(total)
    }
    tooltipText: Translation.tr("Offload home folders to external storage")
    toggled: Offload.mounted && Offload.folders.some(f => f.state === "linked")
    available: true

    mainAction: () => Offload.refresh()
    altAction:  () => Offload.refresh()
}
