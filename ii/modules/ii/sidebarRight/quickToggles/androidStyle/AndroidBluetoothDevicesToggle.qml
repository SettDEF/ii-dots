// Bluetooth-Devices container — full-inline tile.  Adds to the grid
// at full row width, content (BluetoothDevicesView) renders directly
// on the tile. No drawer.
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
    toggleModel: BluetoothDevicesToggle {}
    tallTile: true
    sizeAnimDuration: 0   // grow / shrink instantly when devices populate
    expandedDelegate: Component {
        BluetoothDevicesView {
            popupRounding: Appearance.rounding.normal
            isSidebar: true
        }
    }
}
