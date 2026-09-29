import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import QtQuick

// The sidebar's top-level tab strip: icons only, so it stays one compact row
// and leaves the width for sub-categories underneath. Names live in tooltips.
//
// Sized and coloured to match the QuickToggleButton group at the other end.
Item {
    id: root
    required property var tabs
    required property int currentIndex
    signal picked(int index)

    // A circle, matching the toggles. 4px between them: circles need more air
    // than a stadium, or they look wedged.
    readonly property int pillSize: 32
    readonly property int pillSpacing: 4
    readonly property int count: root.tabs?.length ?? 0

    // Stated rather than derived from the children, so the enclosing clip can
    // be sized from it without waiting on the Row. Sizing that clip from the
    // Row instead is what sheared the top and bottom off these circles.
    implicitHeight: root.pillSize
    implicitWidth: root.count > 0
        ? root.count * root.pillSize + (root.count - 1) * root.pillSpacing
        : 0

    // One indicator that travels, rather than a colour swap in each pill: the
    // move is what tells you the strip is a single control.
    Rectangle {
        id: indicator
        width: root.pillSize
        height: root.pillSize
        radius: height / 2
        x: root.currentIndex * (root.pillSize + root.pillSpacing)
        visible: root.currentIndex >= 0 && root.currentIndex < root.count
        color: Appearance.colors.colPrimary

        // Skipped for the first placement, or the indicator slides in from the
        // left every time the strip is revealed.
        property bool placed: false
        Component.onCompleted: Qt.callLater(() => indicator.placed = true)
        Behavior on x {
            enabled: indicator.placed
            NumberAnimation { duration: 260; easing.type: Easing.OutCubic }
        }
    }

    Row {
        anchors.fill: parent
        spacing: root.pillSpacing

        Repeater {
            model: root.tabs
            delegate: Item {
                id: pill
                required property var modelData
                required property int index
                readonly property bool active: root.currentIndex === pill.index

                implicitHeight: root.pillSize
                implicitWidth: root.pillSize

                // Under the icon but over the indicator, so it is left out on
                // the active pill rather than painting over the indicator.
                Rectangle {
                    anchors.fill: parent
                    radius: width / 2
                    visible: !pill.active
                    color: pillHov.hovered ? Appearance.colors.colLayer1Hover : "transparent"
                    Behavior on color { ColorAnimation { duration: 160 } }
                }

                HoverHandler { id: pillHov }
                TapHandler { onTapped: root.picked(pill.index) }

                MaterialSymbol {
                    // MaterialSymbol is a Text: centerIn centres the line box, not the glyph.
                    anchors.fill: parent
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                    text: pill.modelData.icon
                    // 20, between the 20px grid_view and the 22px toggles.
                    iconSize: 20
                    fill: pill.active ? 1 : 0
                    color: pill.active ? Appearance.m3colors.m3onPrimary
                                       : Appearance.colors.colOnLayer1
                    Behavior on color { ColorAnimation { duration: 160 } }
                }

                StyledToolTip {
                    extraVisibleCondition: false
                    alternativeVisibleCondition: pillHov.hovered || Appearance.touchUi
                    text: pill.modelData.label
                }
            }
        }
    }
}
