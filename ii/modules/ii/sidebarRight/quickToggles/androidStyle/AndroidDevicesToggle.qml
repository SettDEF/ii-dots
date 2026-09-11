// Devices container tile.
//
// Three sizes, three different jobs:
//   1x1       plain icon button, no inline content (expandedSize is false)
//   2x1       one summary line - what is attached and the battery to worry
//             about. A shrunk card list would be a worse list, not a summary.
//   full row  the card list, with per-device controls.
//
// Right-click (the model's menu action) opens the full dialog, matching how
// Internet and Bluetooth behave.
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.models.quickToggles
import qs.modules.common.widgets
import qs.modules.ii.cornerPopup
import QtQuick
import QtQuick.Layouts

AndroidQuickToggleButton {
    id: root
    toggleModel: DevicesToggle {}

    // 2 cells or fewer is a summary; anything wider gets the real list.
    readonly property bool isCompact: root.cellSize <= 2

    // A summary is one row tall, so it must not grow to the 2x height an
    // expanded tile normally takes.
    tallTile: !root.isCompact
    compactExpanded: root.isCompact
    sizeAnimDuration: 0   // grow / shrink instantly when devices populate

    expandedDelegate: Component {
        DevicesView {
            popupRounding: Appearance.rounding.normal
            isSidebar: true
            compact: root.isCompact
        }
    }
}
