import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import QtQuick

DockTile {
    tint: ColorUtils.mix(Appearance.colors.colPrimary, Appearance.colors.colPrimaryContainer, 0.2)
    tooltip: Translation.tr("Folders")

    MaterialSymbol {
        anchors.centerIn: parent
        text: "folder_open"
        iconSize: Appearance.font.pixelSize.huge
        fill: 1
        color: Appearance.colors.colOnPrimaryContainer
    }
}
