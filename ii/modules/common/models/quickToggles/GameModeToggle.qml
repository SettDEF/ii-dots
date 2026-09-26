import QtQuick
import qs.services
import qs.modules.common

QuickToggleModel {
    name: Translation.tr("Game mode")
    icon: "gamepad"
    toggled: GameMode.active
    statusText: GameMode.active
        ? (GameMode.manual ? Translation.tr("On") : Translation.tr("On · game running"))
        : (GameMode.auto ? Translation.tr("Auto") : Translation.tr("Off"))
    mainAction: () => GameMode.toggle()
    // Settings action: whether a running game turns it on by itself.
    altAction: () => GameMode.setAuto(!GameMode.auto)
    tooltipText: Translation.tr("Game mode")
}
