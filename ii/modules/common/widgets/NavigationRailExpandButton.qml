import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets

RippleButton {
    id: root
    /// What it expands. Defaults to the parent, for use inside a rail.
    property Item rail: root.parent

    Layout.alignment: Qt.AlignLeft
    implicitWidth: 40
    implicitHeight: 40
    Layout.leftMargin: 8
    downAction: () => {
        root.rail.expanded = !root.rail.expanded;
    }
    buttonRadius: Appearance.rounding.full

    rotation: (root.rail?.expanded ?? false) ? 0 : -180
    Behavior on rotation {
        animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
    }

    contentItem: MaterialSymbol {
        id: icon
        anchors.centerIn: parent
        horizontalAlignment: Text.AlignHCenter
        iconSize: 24
        color: Appearance.colors.colOnLayer1
        text: (root.rail?.expanded ?? false) ? "menu_open" : "menu"
    }
}
