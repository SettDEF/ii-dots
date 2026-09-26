import qs.modules.common
import qs.modules.common.widgets
import QtQuick

// The sidebar's top-level tab strip: icons only, so it stays one compact row
// and leaves the width for sub-categories underneath. Names live in tooltips.
Flow {
    id: root
    required property var tabs
    required property int currentIndex
    signal picked(int index)

    spacing: 2

    Repeater {
        model: root.tabs
        delegate: Rectangle {
            id: pill
            required property var modelData
            required property int index
            readonly property bool active: root.currentIndex === pill.index

            implicitHeight: 32
            implicitWidth: 38
            radius: height / 2
            color: pill.active ? Appearance.colors.colSecondaryContainer
                 : (pillHov.hovered ? Appearance.colors.colLayer2 : "transparent")
            Behavior on color { ColorAnimation { duration: 160 } }

            HoverHandler { id: pillHov }
            TapHandler { onTapped: root.picked(pill.index) }

            MaterialSymbol {
                anchors.centerIn: parent
                text: pill.modelData.icon
                iconSize: 18
                fill: pill.active ? 1 : 0
                color: pill.active ? Appearance.m3colors.m3onSecondaryContainer
                                   : Appearance.colors.colOnLayer0
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
