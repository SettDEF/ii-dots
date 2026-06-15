import QtQuick
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets

QuickToggleModel {
    name: Translation.tr("MIDI")
    icon: "piano"
    tooltipText: Translation.tr("MIDI devices")
    toggled: false
    available: true
    hasStatusText: false
    mainAction: () => {}
}
