import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts
import Quickshell.Widgets

Item {
    id: root
    required property real value
    required property string icon
    required property string name
    property bool rotateIcon: false
    // Total rotation angle in degrees applied at value=1. Default 180°
    // matches the existing scroll-spin behaviour for non-binary OSDs.
    // Binary indicators like caps lock should use 360° so the icon
    // spins fully back to its original orientation instead of finishing
    // upside-down (a down-pointing caps-lock arrow looks like a bug).
    property real iconRotationAngle: 180
    property bool scaleIcon: false
    property bool showProgress: true
    property string customValueText: ""
    property bool highlightIcon: false
    // Caps lock OSD wants no shadow — the soft drop shadow reads as a
    // "blur halo" around the pill during the show/hide pop, and at the
    // short duration of a caps OSD it's a distraction rather than a
    // depth cue. Other indicators (volume / brightness) keep it.
    property bool showShadow: true
    property color iconColor: highlightIcon ? Appearance.colors.colPrimary : Appearance.colors.colOnLayer0

    property real valueIndicatorVerticalPadding: 9
    property real valueIndicatorLeftPadding: 10
    property real valueIndicatorRightPadding: 20 // An icon is circle ish, a column isn't, hence the extra padding

    implicitWidth: Appearance.sizes.osdWidth + 2 * Appearance.sizes.elevationMargin
    implicitHeight: valueIndicator.implicitHeight + 2 * Appearance.sizes.elevationMargin

    StyledRectangularShadow {
        target: valueIndicator
        visible: root.showShadow
    }
    Rectangle {
        id: valueIndicator
        anchors {
            fill: parent
            margins: Appearance.sizes.elevationMargin
        }
        radius: Appearance.rounding.full
        color: Appearance.colors.colLayer0

        implicitWidth: valueRow.implicitWidth
        implicitHeight: valueRow.implicitHeight

        RowLayout { // Icon on the left, stuff on the right
            id: valueRow
            Layout.margins: 10
            anchors.fill: parent
            spacing: 10

            Item {
                implicitWidth: 30
                implicitHeight: 30
                Layout.alignment: Qt.AlignVCenter
                Layout.leftMargin: valueIndicatorLeftPadding
                Layout.topMargin: valueIndicatorVerticalPadding
                Layout.bottomMargin: valueIndicatorVerticalPadding

                MaterialSymbol { // Icon
                    anchors {
                        centerIn: parent
                        alignWhenCentered: !root.rotateIcon
                    }
                    color: root.iconColor
                    renderType: Text.QtRendering

                    text: root.icon
                    iconSize: 20 + 10 * (root.scaleIcon ? value : 1)
                    rotation: root.iconRotationAngle * (root.rotateIcon ? value : 0)

                    Behavior on iconSize {
                        animation: Appearance.animation.elementMoveEnter.numberAnimation.createObject(this)
                    }
                    Behavior on rotation {
                        animation: Appearance.animation.elementMoveEnter.numberAnimation.createObject(this)
                    }
                
                }
            }
            ColumnLayout { // Stuff
                Layout.alignment: Qt.AlignVCenter
                Layout.rightMargin: valueIndicatorRightPadding
                spacing: root.showProgress ? 5 : 0

                RowLayout { // Name fill left, value on the right end
                    Layout.leftMargin: root.showProgress ? (valueProgressBar.height / 2) : 6 // Align text with progressbar radius curve's left end
                    Layout.rightMargin: root.showProgress ? (valueProgressBar.height / 2) : 6 // Align text with progressbar radius curve's left end
                    // Explicit gap — was 0 by default, which let the name
                    // run straight into the ON/OFF chip on the caps-lock
                    // OSD where there's no progress bar to pad them apart.
                    spacing: 14

                    StyledText {
                        color: Appearance.colors.colOnLayer0
                        font.pixelSize: Appearance.font.pixelSize.small
                        // No fillWidth + no elide → the pill grows wide
                        // enough to fit the label. Previous "fillWidth +
                        // elide" combo capped the row at the pill's
                        // current implicitWidth (driven by the icon),
                        // which is why "Caps Lock" rendered as "Caps L…".
                        text: root.name
                    }
                    Item { Layout.fillWidth: true }

                    StyledText {
                        color: Appearance.colors.colOnLayer0
                        font.pixelSize: Appearance.font.pixelSize.small
                        Layout.fillWidth: false
                        text: root.customValueText !== "" ? root.customValueText : Math.round(root.value * 100)
                    }
                }
                
                StyledProgressBar {
                    id: valueProgressBar
                    Layout.fillWidth: true
                    value: root.value
                    visible: root.showProgress
                }
            }
        }
    }
}
