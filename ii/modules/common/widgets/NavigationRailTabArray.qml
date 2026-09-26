import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts

Item {
    id: root
    property int currentIndex: 0
    property bool expanded: false
    default property alias data: tabBarColumn.data  
    implicitHeight: tabBarColumn.implicitHeight
    implicitWidth: tabBarColumn.implicitWidth
    Layout.topMargin: 25

    // Buttons only: a Repeater is a child of the column too, and indexing
    // `children` directly put the highlight on the wrong item with fallback sizes.
    readonly property var buttons: Array.from(tabBarColumn.children).filter(c => c.baseSize !== undefined)
    readonly property var current: root.buttons[root.currentIndex] ?? null

    Rectangle {
        visible: root.current !== null
        anchors {
            top: tabBarColumn.top
            left: tabBarColumn.left
            topMargin: (root.current?.y ?? 0) + (root.current?.highlightY ?? 0)
        }
        radius: Appearance.rounding.full
        color: Appearance.colors.colSecondaryContainer
        implicitHeight: root.expanded ? (root.current?.baseSize ?? 56) : (root.current?.baseHighlightHeight ?? 32)
        implicitWidth: root.current?.visualWidth ?? 56

        Behavior on anchors.topMargin {
            NumberAnimation {
                duration: Appearance.animationCurves.expressiveFastSpatialDuration
                easing.type: Appearance.animation.elementMove.type
                easing.bezierCurve: Appearance.animationCurves.expressiveFastSpatial
            }
        }
    }

    ColumnLayout {
        id: tabBarColumn
        anchors.fill: parent
        spacing: 0
    }
}
