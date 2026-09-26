import qs.modules.common
import QtQuick
import QtQuick.Layouts

Rectangle {
    id: sep
    property real lineHeight: 20

    // One fixed height, self-centring, so every separator matches whether it
    // sits in dockRow or inside a DockAppButton.
    //
    // The offset is the point: dockRow spans the whole window, but the
    // visible dock is inset elevationMargin on top and hyprlandGapsOut at the
    // bottom, so the row's centre sits (10-5)/2 above the dock's.
    implicitWidth: 1
    implicitHeight: sep.lineHeight
    Layout.preferredHeight: sep.lineHeight
    Layout.alignment: Qt.AlignVCenter
    Layout.topMargin: Appearance.sizes.elevationMargin - Appearance.sizes.hyprlandGapsOut
    color: Appearance.colors.colOutlineVariant
}
