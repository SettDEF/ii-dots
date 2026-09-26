import qs.modules.common
import qs.modules.common.widgets
import QtQuick

// The sidebar's top-level tab strip: icons only, so it stays one compact row
// and leaves the width for sub-categories underneath. Names live in tooltips.
//
// Sized and coloured to match the QuickToggleButton group at the other end of
// the same row — they are the only two control clusters in the header, and two
// different toggle languages side by side read as two unrelated widgets.
Flow {
    id: root
    required property var tabs
    required property int currentIndex
    signal picked(int index)

    // 4px: circles need a little more air than a stadium did, or the active
    // one looks wedged between its neighbours.
    spacing: 4

    Repeater {
        model: root.tabs
        delegate: Rectangle {
            id: pill
            required property var modelData
            required property int index
            readonly property bool active: root.currentIndex === pill.index

            // Square, so the active indicator is a true circle — the same shape
            // as the QuickToggleButtons at the other end of the row, just
            // smaller. A stadium here read as a different kind of control.
            // Five of these plus the divider still fit the 460px sidebar once
            // the "Tools" label has collapsed.
            implicitHeight: 32
            implicitWidth: 32
            radius: Appearance.rounding.full
            color: pill.active ? Appearance.colors.colPrimary
                 : (pillHov.hovered ? Appearance.colors.colLayer1Hover : "transparent")
            Behavior on color { ColorAnimation { duration: 160 } }

            HoverHandler { id: pillHov }
            TapHandler { onTapped: root.picked(pill.index) }

            MaterialSymbol {
                // MaterialSymbol is a Text, so centerIn alone centres the line
                // box — ascent and descent included — and sits the glyph low.
                anchors.fill: parent
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
                text: pill.modelData.icon
                // 20, matching the grid_view icon to its left and closing the
                // gap to the 22px toggles at the other end of the same row.
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
