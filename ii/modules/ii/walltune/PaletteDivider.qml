import qs
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts

/// Hairline between rows in a PaletteCard, starting after the icon column.
Rectangle {
    Layout.fillWidth: true
    Layout.leftMargin: 44
    Layout.rightMargin: 8
    implicitHeight: 1
    color: Appearance.colors.colOnLayer1
    opacity: 0.08
}
