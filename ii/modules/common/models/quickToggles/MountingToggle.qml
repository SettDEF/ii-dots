import QtQuick
import qs
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets

QuickToggleModel {
    id: root
    name: Translation.tr("Drives")
    icon: "usb"
    statusText: Mounting.mountedCount > 0
        ? Translation.tr("%1 mounted").arg(Mounting.mountedCount)
        : (Mounting.devices.length > 0
            ? Translation.tr("%1 available").arg(Mounting.devices.length)
            : Translation.tr("None"))
    tooltipText: Translation.tr("Mount / unmount drives")
    toggled: Mounting.mountedCount > 0
    available: true

    // Tap → refresh listing. Long-press / right-click does the same since
    // this is mostly a display tile; mount/unmount happens in the expanded
    // delegate.
    mainAction: () => Mounting.refresh()
    altAction:  () => Mounting.refresh()
}
