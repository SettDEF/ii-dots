import QtQuick
import Quickshell
import qs.modules.common

/*
 * Widget to be placed on a WidgetCanvas
 */
MouseArea {
    id: root

    property alias animateXPos: xBehavior.enabled
    property alias animateYPos: yBehavior.enabled
    // Optional-chained: this binds before Config's FileView has populated
    // options, and an undefined there would make every widget undraggable.
    property bool draggable: !(Config.options?.background?.widgetsLocked ?? false)
    drag.target: draggable ? root : undefined
    cursorShape: (draggable && containsPress) ? Qt.ClosedHandCursor : draggable ? Qt.OpenHandCursor : Qt.ArrowCursor

    function center() {
        root.x = (root.parent.width - root.width) / 2
        root.y = (root.parent.height - root.height) / 2
    }

    Behavior on x {
        id: xBehavior
        animation: Appearance.animation.elementMove.numberAnimation.createObject(this)
    }
    Behavior on y {
        id: yBehavior
        animation: Appearance.animation.elementMove.numberAnimation.createObject(this)
    }
}
