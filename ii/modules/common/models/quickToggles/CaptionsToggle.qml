import QtQuick
import Quickshell
import qs
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets

QuickToggleModel {
    name: Translation.tr("Live captions")
    // Says what it is DOING, not just on/off: with translation on, "Listening"
    // alone would not tell you which of the two modes you are in.
    statusText: !toggled ? Translation.tr("Off")
              : Captions.lastError.length > 0 ? Translation.tr("Failed")
              : Captions.translateTo.length > 0
                  ? Translation.tr("→ %1").arg(Captions.translateTo)
                  : Translation.tr("Listening")
    toggled: Captions.active
    icon: Captions.active ? "closed_caption" : "closed_caption_disabled"
    mainAction: () => {
        Captions.toggle()
    }
    hasMenu: true

    tooltipText: Translation.tr("Live captions | Reads out loud speech on screen")
}
