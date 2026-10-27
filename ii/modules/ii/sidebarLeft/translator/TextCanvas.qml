import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

Rectangle {
    id: root
    property bool isInput: true // true for input, false for output
    property string placeholderText
    property string text: ""
    property var inputTextArea: isInput ? inputLoader.item : undefined
    readonly property string displayedText: isInput ? inputLoader.item.text : 
        root.text.length > 0 ? outputLoader.item.text : ""
    property real minHeight: 150
    property color textColor: Appearance.colors.colOnLayer1
    property real textSize: Appearance.font.pixelSize.small
    default property alias actionButtons: actions.data
    Layout.fillWidth: true
    implicitHeight: Math.max(root.minHeight, inputColumn.implicitHeight)
    color: Appearance.colors.colLayer2
    radius: Appearance.rounding.normal

    signal inputTextChanged(); // Signal emitted when text changes

    ColumnLayout {
        id: inputColumn
        anchors.fill: parent
        spacing: 0

        Loader {
            id: inputLoader
            active: root.isInput
            visible: root.isInput
            Layout.fillWidth: true
            sourceComponent: StyledTextArea { // Input area
                id: inputTextArea
                placeholderText: root.placeholderText
                wrapMode: TextEdit.Wrap
                textFormat: TextEdit.PlainText
                font.pixelSize: root.textSize
                color: root.textColor
                padding: 15
                background: null
                onTextChanged: root.inputTextChanged()
            }
        }

        Loader {
            id: outputLoader
            active: !root.isInput
            visible: !root.isInput
            Layout.fillWidth: true
            sourceComponent: StyledText { // Output area
                id: outputTextArea
                padding: 15
                wrapMode: Text.Wrap
                font.pixelSize: root.textSize
                color: root.text.length > 0 ? root.textColor : Appearance.colors.colSubtext
                Behavior on font.pixelSize { NumberAnimation { duration: 120 } }
                text: root.text.length > 0 ? root.text : root.placeholderText
            }
        }

        Item { Layout.fillHeight: true } 

        RowLayout { // Status row
            Layout.fillWidth: true
            Layout.margins: 10
            spacing: 10

            Loader {
                active: root.isInput
                visible: root.isInput
                Layout.leftMargin: 10
                sourceComponent: Text {
                    text: Translation.tr("%1 characters").arg(inputLoader.item.text.length)
                    color: Appearance.colors.colSubtext
                    font.pixelSize: Appearance.font.pixelSize.smaller
                }
            }
            Item { Layout.fillWidth: true }
            ButtonGroup {
                id: actions
            }
        }
    }
}