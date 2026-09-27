import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import qs.services
import qs.modules.common
import qs.modules.common.widgets

GroupButton {
    id: root
    horizontalPadding: 12
    verticalPadding: 8
    bounce: false
    property string buttonIcon
    property bool leftmost: false
    property bool rightmost: false
    // Position only, not selection: rounding the toggled chip on both sides
    // broke the connected-group shape, since its inner edge stopped matching
    // the neighbour it sits against.
    leftRadius: leftmost ? (height / 2) : Appearance.rounding.unsharpenmore
    rightRadius: rightmost ? (height / 2) : Appearance.rounding.unsharpenmore
    // M3 segmented button: the selected chip carries the colour and the rest
    // stay quiet. It was the other way round, so a row of eleven options read
    // as a wall of accent with one hole punched in it.
    colBackground: Appearance.colors.colLayer2
    colBackgroundHover: Appearance.colors.colLayer2Hover
    colBackgroundActive: Appearance.colors.colLayer2Active
    colBackgroundToggled: Appearance.colors.colSecondaryContainer
    colBackgroundToggledHover: Appearance.colors.colSecondaryContainerHover
    colBackgroundToggledActive: Appearance.colors.colSecondaryContainerActive

    contentItem: RowLayout {
        spacing: 4 * (root.buttonText?.length > 0)

        Loader {
            Layout.alignment: Qt.AlignVCenter
            active: root.buttonIcon && root.buttonIcon.length > 0
            visible: active
            sourceComponent: Item {
                implicitWidth: materialSymbol.implicitWidth
                MaterialSymbol {
                    id: materialSymbol
                    anchors.centerIn: parent
                    text: root.buttonIcon
                    iconSize: Appearance.font.pixelSize.larger
                    color: root.toggled ? Appearance.colors.colOnSecondaryContainer
                                        : Appearance.colors.colOnLayer2
                }
            }
        }

        Item {
            implicitWidth: root.buttonText?.length > 0 ? textItem.implicitWidth : 0
            implicitHeight: textMetrics.height // Force height to that of regular text

            TextMetrics {
                id: textMetrics
                font.family: Appearance.font.family.main
                text: "Abc"
            }

            StyledText {
                id: textItem
                anchors.centerIn: parent
                color: root.toggled ? Appearance.colors.colOnSecondaryContainer
                                    : Appearance.colors.colOnLayer2
                text: root.buttonText
            }
        }
    }
}
