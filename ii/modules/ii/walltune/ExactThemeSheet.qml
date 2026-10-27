import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts

/// Palette > Exact theme: the wallpaper's colours, or a named theme's own (tinct theme list).
PanelSheet {
    id: sheet
    title: qsTr("Exact theme")
    subtitle: qsTr("A theme's own colours in every app and the terminal")

    PaletteCard {
        Repeater {
            // the wallpaper first: picking it turns exact themes off
            model: [{ id: "", name: qsTr("Wallpaper colours"), dark: true, swatches: [] }].concat(ExactTheme.themes)
            delegate: ColumnLayout {
                id: entry
                required property var modelData
                required property int index
                readonly property bool chosen: ExactTheme.current === modelData.id
                Layout.fillWidth: true
                spacing: 0

                PaletteDivider { visible: entry.index > 0 }
                RippleButton {
                    Layout.fillWidth: true
                    implicitHeight: 48
                    buttonRadius: Appearance.rounding.small
                    colBackground: "transparent"
                    colBackgroundHover: Appearance.colors.colLayer1Hover
                    onClicked: {
                        ExactTheme.select(entry.modelData.id);
                        sheet.closed();
                    }

                    contentItem: RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 10
                        anchors.rightMargin: 10
                        spacing: 12

                        // the theme in five dots; the wallpaper gets its icon
                        Item {
                            Layout.preferredWidth: 22 + 4 * 11
                            Layout.preferredHeight: 22
                            MaterialSymbol {
                                visible: entry.modelData.swatches.length === 0
                                anchors.verticalCenter: parent.verticalCenter
                                text: "wallpaper"
                                iconSize: Appearance.font.pixelSize.larger
                                color: entry.chosen ? Appearance.colors.colPrimary : Appearance.colors.colSubtext
                            }
                            Repeater {
                                model: entry.modelData.swatches
                                delegate: Rectangle {
                                    required property string modelData
                                    required property int index
                                    x: index * 11
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: 22; height: 22; radius: 11
                                    color: modelData
                                    border.width: 2
                                    border.color: Appearance.m3colors.m3surfaceContainerHigh
                                }
                            }
                        }
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 0
                            StyledText {
                                Layout.fillWidth: true
                                text: entry.modelData.name
                                elide: Text.ElideRight
                                font.pixelSize: Appearance.font.pixelSize.smaller
                                font.weight: entry.chosen ? Font.DemiBold : Font.Normal
                                color: Appearance.colors.colOnLayer1
                            }
                            StyledText {
                                Layout.fillWidth: true
                                text: entry.modelData.id === "" ? qsTr("Extracted from the image")
                                    : (entry.modelData.dark ? qsTr("Dark") : qsTr("Light")) + " · " + qsTr("%1 colours").arg(entry.modelData.colors)
                                font.pixelSize: Appearance.font.pixelSize.smallest
                                color: Appearance.colors.colSubtext
                            }
                        }
                        MaterialSymbol {
                            visible: entry.chosen
                            text: "check"
                            iconSize: Appearance.font.pixelSize.larger
                            color: Appearance.colors.colPrimary
                        }
                    }
                }
            }
        }
    }

    StyledText {
        Layout.fillWidth: true
        wrapMode: Text.WordWrap
        text: qsTr("Grading (theory, style, remap) is left out with a theme: it would move its colours. Edit colours changes single ones.")
        font.pixelSize: Appearance.font.pixelSize.smallest
        color: Appearance.colors.colSubtext
    }
}
