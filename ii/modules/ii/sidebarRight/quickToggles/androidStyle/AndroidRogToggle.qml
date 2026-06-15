// ROG container — a 1×1 tile in the grid. When opened the tile animates
// into a full-row card whose body is the ContainerDrawer's rog grid. The
// size animation is driven by the baseWidth/baseHeight Behaviors in
// AndroidQuickToggleButton (gated on _isContainerOpen).
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.models.quickToggles
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts

AndroidQuickToggleButton {
    id: root
    toggleModel: RogToggle {}
    containerType: "rog"
    toggled: root._isContainerOpen
    // Tall-tile semantics: when open, baseHeight follows the delegate's
    // implicitHeight (the rog children Grid) instead of the standard 2x cell.
    tallTile: root._isContainerOpen

    colBackgroundToggled: root.colBackground
    colBackgroundToggledHover: root._holdPressed ? "transparent" : Appearance.colors.colLayer2Hover
    colBackgroundToggledActive: root._holdPressed ? "transparent" : Appearance.colors.colLayer2Active
    colText: root._holdPressed
        ? Appearance.colors.colOnPrimary
        : ColorUtils.transparentize(Appearance.colors.colOnLayer2, enabled ? 0 : 0.7)
    colIcon: root._holdPressed
        ? Appearance.colors.colOnPrimary
        : colText

    expandedDelegate: Component {
        ContainerDrawer {
            tabIndex: root.tabIndex
            buttonIndex: root.buttonIndex
            containerType: "rog"
            editMode: root.editMode
        }
    }
}
