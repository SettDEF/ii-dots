import QtQuick
import qs.modules.common

Rectangle {
    id: contentItem
    /// False for a widget the user has set to "no background": the content
    /// stays, the surface behind it goes.
    property bool shown: true
    anchors.fill: parent
    color: contentItem.shown ? Appearance.m3colors.m3surfaceContainer : "transparent"
}
