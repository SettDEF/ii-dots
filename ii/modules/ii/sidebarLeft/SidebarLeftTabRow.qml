import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import QtQuick

// The sidebar's top-level tab strip: icons only, so it stays one compact row
// and leaves the width for sub-categories underneath. Names live in tooltips.
//
// Sized and coloured to match the QuickToggleButton group at the other end.
Flow {
    id: root
    required property var tabs
    required property int currentIndex
    signal picked(int index)

    // 4px: circles need more air than a stadium, or they look wedged.
    spacing: 4

    Repeater {
        model: root.tabs
        delegate: Rectangle {
            id: pill
            required property var modelData
            required property int index
            readonly property bool active: root.currentIndex === pill.index

            // Square: a circle, matching the toggles. Five fit the 460px
            // sidebar once the "Tools" label collapses.
            implicitHeight: 32
            implicitWidth: 32
            // width / 2: rounding.full did not clamp here, it rendered square.
            radius: width / 2
            color: pill.active ? Appearance.colors.colPrimary
                 : (pillHov.hovered ? Appearance.colors.colLayer1Hover : ColorUtils.transparentize(Appearance.colors.colLayer1Hover))
            Behavior on color { ColorAnimation { duration: 160 } }

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
