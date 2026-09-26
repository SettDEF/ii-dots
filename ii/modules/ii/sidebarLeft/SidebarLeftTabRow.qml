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

    // 3px, not 2: at 2 the pills touch closely enough that the active one
    // looks like a highlight sitting on a strip rather than one tab of several.
    spacing: 3

    Repeater {
        model: root.tabs
        delegate: Rectangle {
            id: pill
            required property var modelData
            required property int index
            readonly property bool active: root.currentIndex === pill.index

            // Wider than tall, so the active indicator reads as a tab pill and
            // not as a blob: at 34x30 the radius made it all but circular. 36x28
            // still fits five tabs plus the divider in the 460px sidebar once
            // the "Tools" label has collapsed.
            implicitHeight: 28
            implicitWidth: 36
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
