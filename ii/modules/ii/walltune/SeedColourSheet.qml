import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts

/// Look > Colour > From a colour: the whole palette from one colour (tinct generate --color), no
/// wallpaper; the scheme and grading still apply. Typed, picked from the screen or one of a few.
PanelSheet {
    id: sheet
    title: qsTr("From a colour")
    subtitle: qsTr("The whole theme from one colour, not the wallpaper")

    property string draft: ExactTheme.seed !== "" ? ExactTheme.seed : "#6750a4"
    readonly property bool valid: /^#[0-9a-fA-F]{6}$/.test(draft)
    onOpenChanged: if (open) draft = ExactTheme.seed !== "" ? ExactTheme.seed : draft

    PaletteCard {
        ColumnLayout {
            Layout.fillWidth: true
            Layout.margins: 10
            spacing: 10

            // the colour and its hex
            RowLayout {
                Layout.fillWidth: true
                spacing: 10
                Rectangle {
                    implicitWidth: 44; implicitHeight: 44; radius: 22
                    color: sheet.valid ? sheet.draft : "transparent"
                    border.width: 1
                    border.color: Appearance.colors.colLayer0Border
                }
                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: 36
                    radius: Appearance.rounding.small
                    color: Appearance.colors.colLayer2
                    border.width: hexIn.activeFocus ? 1 : 0
                    border.color: Appearance.colors.colPrimary
                    StyledTextInput {
                        id: hexIn
                        anchors.fill: parent
                        anchors.leftMargin: 10
                        anchors.rightMargin: 10
                        verticalAlignment: TextInput.AlignVCenter
                        font.family: Appearance.font.family.monospace
                        text: sheet.draft
                        validator: RegularExpressionValidator { regularExpression: /#?[0-9a-fA-F]{0,6}/ }
                        onTextEdited: sheet.draft = (text.startsWith("#") ? text : "#" + text).toLowerCase()
                        onAccepted: if (sheet.valid) ExactTheme.setSeed(sheet.draft)
                    }
                }
                RippleButton {
                    implicitWidth: 36; implicitHeight: 36
                    buttonRadius: Appearance.rounding.small
                    colBackground: Appearance.colors.colLayer2
                    onClicked: ColorPick.pickInto(c => { sheet.draft = c; })
                    contentItem: MaterialSymbol { anchors.centerIn: parent; text: "colorize"; iconSize: 18; color: Appearance.colors.colOnLayer2 }
                    StyledToolTip { text: qsTr("Pick from the screen") }
                }
            }

            // a few to start from, then the last picks
            Flow {
                Layout.fillWidth: true
                spacing: 6
                Repeater {
                    model: ["#e53935", "#fb8c00", "#fdd835", "#43a047", "#00897b", "#00acc1", "#1e88e5", "#3949ab",
                            "#8e24aa", "#d81b60", "#6d4c41", "#546e7a"].concat(Array.from(ColorPick.recent).slice(0, 6))
                    delegate: Rectangle {
                        id: sw
                        required property string modelData
                        width: 26; height: 26; radius: 13
                        color: modelData
                        border.width: sheet.draft === modelData ? 2 : 1
                        border.color: sheet.draft === modelData ? Appearance.colors.colOnLayer1 : Appearance.colors.colLayer0Border
                        TapHandler { onTapped: sheet.draft = sw.modelData }
                    }
                }
            }
        }
    }

    RowLayout {
        Layout.fillWidth: true
        spacing: 8
        DialogButton {
            buttonText: qsTr("Wallpaper again")
            enabled: ExactTheme.seed !== ""
            onClicked: ExactTheme.setSeed("")
        }
        Item { Layout.fillWidth: true }
        DialogButton {
            buttonText: ExactTheme.seed === sheet.draft ? qsTr("In use") : qsTr("Use this colour")
            enabled: sheet.valid && ExactTheme.seed !== sheet.draft
            onClicked: ExactTheme.setSeed(sheet.draft)
        }
    }

    StyledText {
        Layout.fillWidth: true
        wrapMode: Text.WordWrap
        text: qsTr("An exact theme turns this off, and this turns an exact theme off. Extraction mode, theory and style still shape it.")
        font.pixelSize: Appearance.font.pixelSize.smallest
        color: Appearance.colors.colSubtext
    }
}
