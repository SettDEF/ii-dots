import qs.modules.common
import qs.modules.common.widgets
import QtQuick

/**
 * One track, one indicator that slides between the options. Three pills that
 * merely change colour read as three unrelated buttons; the movement is what
 * says they are alternatives.
 *
 *     SegmentedControl {
 *         model: [{ id: "quiet", label: "Quiet", icon: "eco" }, ...]
 *         currentId: Rog.profile
 *         onPicked: id => Rog.setProfile(id)
 *     }
 */
Item {
    id: root

    property var model: []
    property string currentId: ""
    signal picked(string id)

    readonly property int index: Math.max(0, root.model.findIndex(m => m.id === root.currentId))
    readonly property real slotWidth: width / Math.max(1, root.model.length)
    readonly property bool hasSelection: root.model.some(m => m.id === root.currentId)

    implicitHeight: 36

    Rectangle {
        anchors.fill: parent
        radius: Appearance.rounding.full
        color: Appearance.colors.colLayer1
    }

    Rectangle {
        visible: root.hasSelection
        width: root.slotWidth
        height: parent.height
        x: root.index * root.slotWidth
        radius: Appearance.rounding.full
        color: Appearance.colors.colPrimary
        Behavior on x {
            NumberAnimation {
                duration: Appearance.animation.elementMoveFast.duration
                easing.type: Easing.BezierSpline
                easing.bezierCurve: Appearance.animationCurves.emphasized
            }
        }
    }

    Row {
        anchors.fill: parent
        Repeater {
            model: root.model
            delegate: Item {
                id: seg
                required property var modelData
                required property int index
                readonly property bool sel: root.hasSelection && seg.index === root.index
                width: root.slotWidth
                height: root.height

                Row {
                    anchors.centerIn: parent
                    spacing: 5
                    MaterialSymbol {
                        visible: (seg.modelData.icon ?? "").length > 0
                        anchors.verticalCenter: parent.verticalCenter
                        text: seg.modelData.icon ?? ""
                        iconSize: 16
                        color: seg.sel ? Appearance.colors.colOnPrimary : Appearance.colors.colOnLayer1
                        Behavior on color { ColorAnimation { duration: 140 } }
                    }
                    StyledText {
                        anchors.verticalCenter: parent.verticalCenter
                        text: seg.modelData.label ?? ""
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        font.weight: seg.sel ? Font.Medium : Font.Normal
                        color: seg.sel ? Appearance.colors.colOnPrimary : Appearance.colors.colOnLayer1
                        Behavior on color { ColorAnimation { duration: 140 } }
                    }
                }
                HoverHandler { cursorShape: Qt.PointingHandCursor }
                TapHandler { onTapped: root.picked(seg.modelData.id) }
            }
        }
    }
}
