// ShapedButton — Material 3 expressive button using the same MaterialShape
// library that powers the lock-screen password chars. 36 shapes available.
import QtQuick
import qs.modules.common
import qs.modules.common.widgets

Item {
    id: root
    // Pass any value from MaterialShape.Shape.* (e.g. MaterialShape.Shape.Pentagon)
    property var  shape
    property string icon: ""
    property bool   active: false
    property bool   danger: false
    property int    iconSize: Appearance.font.pixelSize.normal
    signal pressed()

    implicitWidth: 36; implicitHeight: 36

    HoverHandler { id: hov }
    TapHandler   { id: tap; onTapped: root.pressed() }

    scale: tap.pressed ? 0.9 : 1
    Behavior on scale { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }

    MaterialShape {
        anchors.centerIn: parent
        shape: root.shape
        implicitSize: Math.min(root.width, root.height)
        // Idle = visible surface tone so the shape silhouette is always
        // readable, not just on hover.
        color: root.active ? Appearance.colors.colPrimary
             : (hov.hovered ? Appearance.m3colors.m3surfaceContainerHighest
                            : Appearance.m3colors.m3surfaceContainer)
        Behavior on color { ColorAnimation { duration: 140 } }
    }

    MaterialSymbol {
        anchors.centerIn: parent
        text: root.icon
        iconSize: root.iconSize
        color: root.active
            ? Appearance.m3colors.m3onPrimary
            : (root.danger ? Appearance.m3colors.m3error : Appearance.m3colors.m3onSurface)
    }
}
