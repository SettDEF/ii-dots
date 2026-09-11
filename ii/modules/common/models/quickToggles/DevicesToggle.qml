import QtQuick
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets

/**
 * The devices tile.
 *
 * Was "BT Devices", which was only ever true by accident: the list is whatever
 * is attached, and a speaker on a USB-C cable is as much a device as one on the
 * radio. Transport belongs in the row, not in the tile's name.
 */
QuickToggleModel {
    name: Translation.tr("Devices")
    icon: Devices.count > 0 ? "devices" : "devices_off"
    statusText: Devices.summary
    tooltipText: Translation.tr("Connected devices | Right-click for the full list")
    toggled: Devices.count > 0
    available: true
    hasStatusText: true
    // The tile renders the list itself; the menu action opens the full dialog.
    mainAction: () => {}
    hasMenu: true
}
