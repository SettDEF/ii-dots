// Standalone "Profile" tile — renders the same RogProfileSwitcher
// (sliding-thumb performance switcher) used inside the ROG drawer.
// At cellSize 1 it's just an icon; at cellSize >= 2 the slider widget.
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.models.quickToggles
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts

AndroidQuickToggleButton {
    id: root
    toggleModel: RogProfileToggle {}
    parentContainerType: "rog"
    compactExpanded: true
    // Keep the tile background neutral even when model.toggled is true —
    // our widget renders its own accent on the icon block / thumb.
    colBackgroundToggled: colBackground
    colBackgroundToggledHover: colBackgroundHover
    colBackgroundToggledActive: colBackgroundActive
    expandedDelegate: Component {
        Item {
            implicitHeight: 56
            RogProfileSwitcher { anchors.fill: parent }
        }
    }
}
