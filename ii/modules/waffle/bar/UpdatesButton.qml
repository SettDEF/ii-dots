import QtQuick
import Quickshell
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.waffle.looks
import qs.modules.waffle.bar.tray

BarIconButton {
    id: root

    visible: Updates.updateAdvised || Updates.updateStronglyAdvised
    padding: 4
    // No icon of its own — the Pac-Man below is the icon. arrow-sync said
    // "syncing"; this button is specifically pacman, so it may as well look
    // like it.
    iconName: ""
    iconSize: 20
    tooltipText: Translation.tr("Get the latest features and security improvements with\nthe newest feature update.\n\n%1 packages").arg(Updates.count)

    onClicked: {
        Quickshell.execDetached(["bash", "-c", Config.options.apps.update]);
    }

    // Chomps while a check is actually running, and keeps chomping once the
    // backlog is past the "strongly advised" threshold — motion is the nag.
    // Otherwise it sits still so a quiet bar stays quiet.
    readonly property bool hungry: Updates.checking || Updates.updateStronglyAdvised

    overlayingItems: [
        PacmanIcon {
            anchors.centerIn: parent
            implicitSize: 18
            chomping: root.hungry
            // Warning tint when the backlog is bad, classic yellow otherwise —
            // the colour carries the severity so the dot does not have to.
            color: Updates.updateStronglyAdvised ? Looks.colors.warning : "#FFD54F"
        },
        // The pellets it is eating: one per pending update, capped at three so
        // a 400-package backlog does not become a dotted line.
        Row {
            anchors {
                right: parent.right
                verticalCenter: parent.verticalCenter
                rightMargin: -1
            }
            spacing: 2
            visible: Updates.count > 0
            Repeater {
                model: Math.min(3, Updates.count)
                delegate: Rectangle {
                    width: 3; height: 3; radius: 1.5
                    anchors.verticalCenter: parent.verticalCenter
                    color: Updates.updateStronglyAdvised ? Looks.colors.warning : Looks.colors.accent
                    opacity: 0.9
                }
            }
        }
    ]
}
