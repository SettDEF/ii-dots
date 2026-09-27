import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets

Item {
    id: root
    property bool vertical: false
    property color color: Appearance.colors.colOnSurfaceVariant

    readonly property string currentId: LayoutService.currentLayout()
    readonly property var currentMeta: {
        const list = LayoutService.availableLayouts
        for (let i = 0; i < list.length; i++) if (list[i].id === currentId) return list[i]
        return list[0]
    }

    implicitWidth: 26
    implicitHeight: 26

    Rectangle {
        anchors.centerIn: parent
        width: 24; height: 24
        radius: width / 2
        color: hov.hovered ? Appearance.colors.colLayer2Base : ColorUtils.transparentize(Appearance.colors.colLayer2Base)
        Behavior on color { animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this) }

        HoverHandler { margin: Appearance.sizes.touchSlop; id: hov }
        TapHandler {
            margin: Appearance.sizes.touchSlop
            acceptedButtons: Qt.LeftButton | Qt.RightButton
            onTapped: (event) => {
                if (event.button === Qt.RightButton) LayoutService.cycle(-1)
                else LayoutService.cycle(1)
            }
        }
        WheelHandler {
            onWheel: (event) => {
                if (event.angleDelta.y > 0) LayoutService.cycle(-1)
                else if (event.angleDelta.y < 0) LayoutService.cycle(1)
            }
        }

        MaterialSymbol {
            anchors.centerIn: parent
            text: root.currentMeta.icon
            iconSize: 18
            color: root.color
        }
    }

    StyledToolTip {
        // The parent here is the outer Item, which has no `hovered` —
        // without an explicit visibility gate the tooltip would always
        // show, leaking onto the desktop. Drive off the HoverHandler.
        extraVisibleCondition: false
        alternativeVisibleCondition: hov.hovered
        text: root.currentMeta.label + "\n" +
              "Click / scroll: cycle  ·  Right-click: prev"
    }
}
