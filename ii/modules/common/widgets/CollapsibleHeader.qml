import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts

/**
 * The clickable header of a collapsible section.
 *
 * A panel with two kinds of dropdown teaches you they are different things.
 * The audio panel had a filled 46px sink picker and, right above it, "Channels
 * Stereo ⌄" as bare text — same gesture, nothing in common to look at, and no
 * hit target to speak of. The filled row won; this is it, in one place.
 *
 *     CollapsibleHeader {
 *         title: Translation.tr("Channels")
 *         value: AudioLayout.layoutName(win.channels)
 *         expanded: win.channelsOpen
 *         onToggled: win.channelsOpen = !win.channelsOpen
 *     }
 */
Rectangle {
    id: root

    property string title: ""
    /// Secondary text: the current selection, a count, a state. Optional.
    property string value: ""
    /// Material Symbols name, drawn ahead of the title. Optional.
    property string icon: ""
    property bool expanded: false

    signal toggled()

    Layout.fillWidth: true
    implicitHeight: 46
    radius: Appearance.rounding.small
    color: headerHover.hovered ? Appearance.colors.colLayer1Hover
                               : Appearance.colors.colLayer1
    Behavior on color {
        animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
    }

    HoverHandler { id: headerHover; cursorShape: Qt.PointingHandCursor }
    TapHandler { onTapped: root.toggled() }

    RowLayout {
        anchors.fill: parent
        anchors.leftMargin: 10
        anchors.rightMargin: 10
        spacing: 10

        MaterialSymbol {
            visible: root.icon.length > 0
            text: root.icon
            iconSize: 20
            color: Appearance.colors.colOnLayer0
        }

        StyledText {
            text: root.title
            font.pixelSize: Appearance.font.pixelSize.smaller
            color: Appearance.colors.colOnLayer0
        }

        StyledText {
            Layout.fillWidth: true
            elide: Text.ElideRight
            text: root.value
            font.pixelSize: Appearance.font.pixelSize.smallest
            color: Appearance.colors.colSubtext
        }

        MaterialSymbol {
            text: "keyboard_arrow_down"
            iconSize: 20
            color: Appearance.colors.colSubtext
            rotation: root.expanded ? 180 : 0
            Behavior on rotation {
                animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
            }
        }
    }
}
