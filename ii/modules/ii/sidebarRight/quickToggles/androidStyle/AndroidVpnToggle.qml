// VPN tile. At cellSize 1 it is just the icon; at cellSize >= 2 it renders the
// full VpnWidget inline, the same way AndroidRogProfileToggle hosts the ROG
// profile switcher.
import qs.modules.common
import qs.modules.common.models.quickToggles
import qs.modules.common.widgets
import QtQuick

AndroidQuickToggleButton {
    id: root
    toggleModel: VpnToggle {}
    compactExpanded: true
    // The widget paints its own accent on the thumb, so the tile background
    // stays neutral even when connected.
    colBackgroundToggled: colBackground
    colBackgroundToggledHover: colBackgroundHover
    colBackgroundToggledActive: colBackgroundActive
    expandedDelegate: Component {
        Item {
            implicitHeight: 56
            VpnWidget { anchors.fill: parent }
        }
    }
}
