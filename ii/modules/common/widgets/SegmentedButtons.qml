import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts

/// Material 3 segmented buttons.
/// https://m3.material.io/components/segmented-buttons/overview
///
///   SegmentedButtons {
///       model: [{ id: "fade", label: "Fade", icon: "blur_on" }, …]
///       currentId: state
///       onSelected: id => state = id
///   }
Rectangle {
    id: root

    /// [{ id, label, icon? }]
    property var model: []
    property var currentId
    /// M3 shows a check on the selection; off where icons already say enough.
    property bool showCheck: true
    property real segmentHeight: 36

    signal selected(var id)

    implicitHeight: root.segmentHeight
    radius: height / 2
    color: "transparent"
    border.width: 1
    border.color: Appearance.colors.colLayer0Border

    RowLayout {
        anchors.fill: parent
        anchors.margins: 1
        spacing: 0

        Repeater {
            model: root.model

            delegate: Item {
                id: segment
                required property var modelData
                required property int index

                readonly property bool active: root.currentId === modelData.id
                readonly property bool first: index === 0
                readonly property bool last: index === (root.model.length - 1)

                Layout.fillWidth: true
                Layout.fillHeight: true

                Rectangle {
                    anchors.fill: parent
                    // Only outer corners round: one pill, not a row of them.
                    topLeftRadius: segment.first ? root.radius : 0
                    bottomLeftRadius: segment.first ? root.radius : 0
                    topRightRadius: segment.last ? root.radius : 0
                    bottomRightRadius: segment.last ? root.radius : 0

                    color: segment.active ? Appearance.colors.colSecondaryContainer
                        : segHov.hovered ? Appearance.colors.colLayer1Hover
                        : "transparent"

                    Behavior on color {
                        ColorAnimation {
                            duration: Appearance.animation.elementMoveFast.duration
                            easing.type: Appearance.animation.elementMoveFast.type
                            easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve
                        }
                    }
                }

                // Hidden next to a filled segment, where it would cut the fill.
                Rectangle {
                    visible: !segment.first && !segment.active
                        && !(root.currentId === (root.model[segment.index - 1]?.id))
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    implicitWidth: 1
                    implicitHeight: parent.height - 12
                    color: Appearance.colors.colLayer0Border
                }

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
                        opacity: segment.active ? 1 : 0.7
                    }
                    StyledText {
                        anchors.verticalCenter: parent.verticalCenter
                        visible: text.length > 0
                        text: segment.modelData.label ?? ""
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        font.weight: segment.active ? Font.Medium : Font.Normal
                        color: segment.active ? Appearance.m3colors.m3onSecondaryContainer
                                              : Appearance.colors.colOnLayer1
                        opacity: segment.active ? 1 : 0.75
                    }
                }

                HoverHandler { id: segHov }
                TapHandler { onTapped: root.selected(segment.modelData.id) }
            }
        }
    }
}
