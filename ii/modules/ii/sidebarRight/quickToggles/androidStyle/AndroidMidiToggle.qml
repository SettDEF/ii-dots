// MIDI container — full-inline tile.  Content (MidiView) renders
// directly on the tile.  No drawer.
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
    toggleModel: MidiToggle {}
    tallTile: true
    expandedDelegate: Component {
        MidiView {
            popupRounding: Appearance.rounding.normal
            isSidebar: true
        }
    }
}
