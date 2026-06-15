// Phone (KDE-Connect) — full-inline tile.  Content (PhoneCard) renders
// directly on the tile.  No drawer.
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.models.quickToggles
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts

AndroidQuickToggleButton {
    id: root
    toggleModel: PhoneToggle {}
    tallTile: true
    signal requestKdeConnectDialog()
    expandedDelegate: Component {
        PhoneCard {
            onOpenDialog: root.requestKdeConnectDialog()
        }
    }
}
