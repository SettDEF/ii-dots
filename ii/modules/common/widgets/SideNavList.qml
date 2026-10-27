import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts

/// Settings sidebar: the rail's look (a pill that slides to the selection,
/// accent icons) in an even, compact list with group headings. Labels stay
/// neutral so the list reads as an index, not as a wall of accent colour.
///
/// model: [{ name, icon, iconRotation?, group? }] — a `group` starts a heading
/// above that entry.
Item {
    id: root
    property var model: []
    property int currentIndex: 0
    signal selected(int index)
    property bool animate: true

    property real rowHeight: 42
    /// One entry per page, heading included, for scroll snapping/reveal.
    readonly property var buttons: Array.from(column.children).filter(c => c.isNavEntry === true)

    implicitWidth: 180
    implicitHeight: column.implicitHeight

    // The old rail's pill: one highlight that slides to the selected row.
    Rectangle {
        readonly property Item target: root.buttons[root.currentIndex] ?? null
        visible: target !== null
        x: 0
        y: target ? target.y + target.headingHeight : 0
        width: parent.width
        height: root.rowHeight
        radius: Appearance.rounding.full
        color: Appearance.colors.colSecondaryContainer
        Behavior on y {
            enabled: root.animate
            NumberAnimation {
                duration: Appearance.animationCurves.expressiveFastSpatialDuration
                easing.type: Appearance.animation.elementMove.type
                easing.bezierCurve: Appearance.animationCurves.expressiveFastSpatial
            }
        }
    }

    Column {
        id: column
        width: parent.width
        spacing: 1

        Repeater {
            model: root.model
            delegate: Item {
                id: entry
                required property int index
                required property var modelData
                readonly property bool isNavEntry: true
                readonly property bool current: root.currentIndex === index
                readonly property bool hasGroup: (modelData.group ?? "").length > 0
                readonly property real headingHeight: hasGroup ? (index === 0 ? 22 : 30) : 0

                width: column.width
                height: headingHeight + root.rowHeight

                StyledText {
                    visible: entry.hasGroup
                    x: 16
                    anchors.bottom: row.top
                    anchors.bottomMargin: 6
                    text: (entry.modelData.group ?? "").toUpperCase()
                    font.pixelSize: Appearance.font.pixelSize.smallest
                    font.weight: Font.DemiBold
                    font.letterSpacing: 0.8
                    color: Appearance.colors.colSubtext
                    opacity: 0.8
                }

                Rectangle {
                    id: row
                    y: entry.headingHeight
                    width: parent.width
                    height: root.rowHeight
                    radius: Appearance.rounding.full
                    color: entry.current ? "transparent"
                         : mouse.containsMouse ? Appearance.colors.colLayer1Hover
                         : "transparent"
                    Behavior on color { ColorAnimation { duration: 110 } }

                    MaterialSymbol {
                        id: glyph
                        anchors.verticalCenter: parent.verticalCenter
                        x: 16
                        text: entry.modelData.icon
                        rotation: entry.modelData.iconRotation ?? 0
                        iconSize: 21
                        fill: entry.current ? 1 : 0
                        color: entry.current ? Appearance.colors.colOnSecondaryContainer
                                             : Appearance.colors.colPrimary
                    }
                    StyledText {
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.left: glyph.right
                        anchors.leftMargin: 12
                        anchors.right: parent.right
                        anchors.rightMargin: 8
                        elide: Text.ElideRight
                        text: entry.modelData.name
                        font.pixelSize: Appearance.font.pixelSize.small
                        font.weight: entry.current ? Font.DemiBold : Font.Normal
                        color: entry.current ? Appearance.colors.colOnSecondaryContainer
                                             : Appearance.colors.colOnLayer0
                    }

                    MouseArea {
                        id: mouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.selected(entry.index)
                    }
                }
            }
        }
    }
}
