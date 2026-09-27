import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

TabButton {
    id: root

    property bool toggled: TabBar.tabBar.currentIndex === TabBar.index
    property string buttonIcon
    property real buttonIconRotation: 0
    property string buttonText
    property bool expanded: false
    property bool showToggledHighlight: true
    readonly property real visualWidth: root.expanded ? root.baseSize + 20 + itemText.implicitWidth : root.baseSize

    property real baseSize: 56
    property real iconSize: 24
    // 14 is off the ramp; kept as the default so other rails do not shift.
    property real labelSize: 14
    property real baseHighlightHeight: 32
    property real highlightCollapsedTopMargin: 6

    /// Heading above this button, marking a group. Carried by the button because
    /// NavigationRailTabArray indexes its highlight off `baseSize !== undefined`,
    /// so a bare Item between buttons shifts it. Collapsed, it becomes a rule.
    property string groupLabel: ""
    readonly property bool hasGroupLabel: root.groupLabel.length > 0
    readonly property real groupLabelHeight: !root.hasGroupLabel ? 0
        : (root.expanded ? groupText.implicitHeight + 14 : 13)

    // Where the highlight pill starts inside the button.
    readonly property real highlightY: root.groupLabelHeight
        + (root.expanded ? 0 : root.highlightCollapsedTopMargin)
    padding: 0

    // The navigation item’s target area always spans the full width of the
    // nav rail, even if the item container hugs its contents.
    Layout.fillWidth: true
    // implicitWidth: contentItem.implicitWidth
    // Collapsed, the label sits under the icon and needs its own room, or it
    // runs into the next item.
    implicitHeight: root.groupLabelHeight + (root.expanded ? baseSize
        : highlightCollapsedTopMargin + baseHighlightHeight + 2 + itemText.implicitHeight + 6)

    background: null
    PointingHandInteraction {}

    StyledText {
        id: groupText
        visible: root.hasGroupLabel && root.expanded
        anchors {
            left: parent.left
            leftMargin: 16
            top: parent.top
            topMargin: 9
        }
        text: root.groupLabel.toUpperCase()
        font.pixelSize: Appearance.font.pixelSize.smallest
        font.weight: Font.DemiBold
        font.letterSpacing: 0.8
        color: Appearance.colors.colSubtext
    }

    Rectangle {
        visible: root.hasGroupLabel && !root.expanded
        anchors {
            horizontalCenter: parent.horizontalCenter
            top: parent.top
            topMargin: 6
        }
        implicitWidth: root.baseSize - 24
        implicitHeight: 1
        color: Appearance.colors.colOnLayer1
        opacity: 0.18
    }

    // Real stuff
    contentItem: Item {
        id: buttonContent
        anchors {
            top: parent.top
            topMargin: root.groupLabelHeight
            bottom: parent.bottom
            left: parent.left
            right: undefined
        }
        
        implicitWidth: root.visualWidth
        implicitHeight: root.expanded ? itemIconBackground.implicitHeight : itemIconBackground.implicitHeight + itemText.implicitHeight 

        Rectangle {
            id: itemBackground
            anchors.top: itemIconBackground.top
            anchors.left: itemIconBackground.left
            anchors.bottom: itemIconBackground.bottom
            implicitWidth: root.visualWidth
            radius: Appearance.rounding.full
            color: toggled ? 
                root.showToggledHighlight ?
                    (root.down ? Appearance.colors.colSecondaryContainerActive : root.hovered ? Appearance.colors.colSecondaryContainerHover : Appearance.colors.colSecondaryContainer)
                    : ColorUtils.transparentize(Appearance.colors.colSecondaryContainer) :
                (root.down ? Appearance.colors.colLayer1Active : root.hovered ? Appearance.colors.colLayer1Hover : ColorUtils.transparentize(Appearance.colors.colLayer1Hover, 1))

            states: State {
                name: "expanded"
                when: root.expanded
                AnchorChanges {
                    target: itemBackground
                    anchors.top: buttonContent.top
                    anchors.left: buttonContent.left
                    anchors.bottom: buttonContent.bottom
                }
                PropertyChanges {
                    target: itemBackground
                    implicitWidth: root.visualWidth
                }
            }
            transitions: Transition {
                AnchorAnimation {
                    duration: Appearance.animation.elementMoveFast.duration
                    easing.type: Appearance.animation.elementMoveFast.type
                    easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve
                }
                PropertyAnimation {
                    target: itemBackground
                    property: "implicitWidth"
                    duration: Appearance.animation.elementMove.duration
                    easing.type: Appearance.animation.elementMove.type
                    easing.bezierCurve: Appearance.animation.elementMove.bezierCurve
                }
            }

            Behavior on color {
                animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
            }
        }

        Item {
            id: itemIconBackground
            implicitWidth: root.baseSize
            implicitHeight: root.baseHighlightHeight
            anchors {
                left: parent.left
                top: parent.top
                topMargin: root.expanded ? (root.baseSize - root.baseHighlightHeight) / 2 : root.highlightCollapsedTopMargin
            }
            MaterialSymbol {
                id: navRailButtonIcon
                rotation: root.buttonIconRotation
                anchors.centerIn: parent
                iconSize: root.iconSize
                fill: toggled ? 1 : 0
                font.weight: (toggled || root.hovered) ? Font.DemiBold : Font.Normal
                text: buttonIcon
                color: toggled ? Appearance.m3colors.m3onSecondaryContainer : Appearance.colors.colOnLayer1

                Behavior on color {
                    animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
                }
            }
        }

        StyledText {
            id: itemText
            // Collapsed, the rail is one button wide and the label has to fit
            // it; unconstrained it overflowed and was clipped at both ends.
            width: root.expanded ? implicitWidth : root.baseSize - 4
            horizontalAlignment: root.expanded ? Text.AlignLeft : Text.AlignHCenter
            elide: Text.ElideRight
            anchors {
                top: itemIconBackground.bottom
                topMargin: 2
                horizontalCenter: itemIconBackground.horizontalCenter
            }
            states: State {
                name: "expanded"
                when: root.expanded
                AnchorChanges {
                    target: itemText
                    anchors {
                        top: undefined
                        horizontalCenter: undefined
                        left: itemIconBackground.right
                        verticalCenter: itemIconBackground.verticalCenter
                    }
                }
            }
            transitions: Transition {
                AnchorAnimation {
                    duration: Appearance.animation.elementMoveFast.duration
                    easing.type: Appearance.animation.elementMoveFast.type
                    easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve
                }
            }
            text: buttonText
            font.pixelSize: root.labelSize
            color: Appearance.colors.colOnLayer1
        }
    }

}
