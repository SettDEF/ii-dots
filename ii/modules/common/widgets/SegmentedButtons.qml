import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts

/// A recessed track with one pill that slides to the chosen segment.
///
///   SegmentedButtons {
///       model: [{ id: "fade", label: "Fade", icon: "blur_on" }, …]
///       currentId: state
///       onSelected: id => state = id
///   }
///
/// A sliding indicator rather than a full-bleed fill: the fill has to square
/// off its inner edges to meet its neighbours, which reads as unfinished next
/// to a rounded container — and it cannot animate between segments.
Rectangle {
    id: root

    /// [{ id, label, icon? }]
    property var model: []
    property var currentId
    property bool showCheck: false
    property real segmentHeight: 36

    signal selected(var id)

    readonly property int currentIndex: {
        for (let i = 0; i < root.model.length; ++i)
            if (root.model[i].id === root.currentId) return i;
        return -1;
    }
    readonly property real segmentWidth:
        root.model.length > 0 ? (width - 4) / root.model.length : 0

    implicitHeight: root.segmentHeight
    radius: Appearance.rounding.full
    // A hole, not a raised surface: the pill sits in it.
    color: Qt.darker(Appearance.colors.colLayer0, 1.25)

    Rectangle {
        id: indicator
        visible: root.currentIndex >= 0
        x: 2 + root.currentIndex * root.segmentWidth
        y: 2
        width: root.segmentWidth
        height: parent.height - 4
        radius: parent.radius - 2
        color: Appearance.colors.colSecondaryContainer

        Behavior on x {
            NumberAnimation {
                duration: Appearance.animation.elementMoveFast.duration
                easing.type: Easing.BezierSpline
                easing.bezierCurve: Appearance.animationCurves.expressiveFastSpatial
            }
        }
        Behavior on width { NumberAnimation { duration: 140 } }
        Behavior on color {
            ColorAnimation { duration: Appearance.animation.elementMoveFast.duration }
        }
    }

    Row {
        anchors.fill: parent
        anchors.margins: 2

        Repeater {
            model: root.model

            delegate: Item {
                id: segment
                required property var modelData
                required property int index
                readonly property bool active: root.currentIndex === index

                width: root.segmentWidth
                height: parent.height

                Row {
                    anchors.centerIn: parent
                    spacing: 5

                    MaterialSymbol {
                        anchors.verticalCenter: parent.verticalCenter
                        visible: text.length > 0
                        text: (root.showCheck && segment.active) ? "check"
                            : (segment.modelData.icon ?? "")
                        iconSize: Appearance.font.pixelSize.small
                        color: segment.active ? Appearance.m3colors.m3onSecondaryContainer
                                              : Appearance.colors.colOnLayer1
                        opacity: segment.active ? 1 : 0.8
                        Behavior on color { ColorAnimation { duration: 140 } }
                    }
                    StyledText {
                        anchors.verticalCenter: parent.verticalCenter
                        visible: text.length > 0
                        text: segment.modelData.label ?? ""
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        font.weight: segment.active ? Font.Medium : Font.Normal
                        color: segment.active ? Appearance.m3colors.m3onSecondaryContainer
                                              : Appearance.colors.colOnLayer1
                        opacity: segment.active ? 1 : 0.85
                        Behavior on color { ColorAnimation { duration: 140 } }
                    }
                }

                HoverHandler { id: segHov }
                TapHandler { onTapped: root.selected(segment.modelData.id) }

                // Hover shows only on segments that are not already chosen.
                Rectangle {
                    anchors.fill: parent
                    anchors.margins: 1
                    radius: root.radius - 2
                    color: Appearance.colors.colLayer1Hover
                    opacity: (segHov.hovered && !segment.active) ? 0.5 : 0
                    Behavior on opacity { NumberAnimation { duration: 120 } }
                }
            }
        }
    }
}
