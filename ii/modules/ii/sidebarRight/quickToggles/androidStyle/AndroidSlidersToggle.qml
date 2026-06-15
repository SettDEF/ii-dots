// Sliders container — 1×1 tile. Click opens the panel-wide drawer below
// the grid (rendered by AndroidQuickPanel via OpenContainerState).
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.models.quickToggles
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts

AndroidQuickToggleButton {
    id: root
    toggleModel: SlidersToggle {}
    containerType: "sliders"
    toggled: root._isContainerOpen
}
