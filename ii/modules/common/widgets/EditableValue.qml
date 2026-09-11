import QtQuick
import qs.modules.common
import qs.modules.common.widgets

// A slider's value readout that you can click to type an exact number.
Item {
    id: root
    property real value: 0
    property real from: 0
    property real to: 1
    property int decimals: 2
    property string suffix: ""
    property string display: root.value.toFixed(root.decimals) + root.suffix
    property color color: Appearance.colors.colPrimary
    property bool bold: true
    signal committed(real v)

    property bool editing: false
    implicitWidth: Math.max(label.implicitWidth, 40)
    implicitHeight: 20

    function commit() {
        const n = parseFloat(String(input.text).replace(",", "."));
        if (isFinite(n)) root.committed(Math.max(root.from, Math.min(root.to, n)));
        root.editing = false;
    }

    StyledText {
        id: label
        visible: !root.editing
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        text: root.display
        font.pixelSize: Appearance.font.pixelSize.small
        font.bold: root.bold
        color: root.color
        HoverHandler { cursorShape: Qt.PointingHandCursor }
        TapHandler {
            onTapped: {
                input.text = root.value.toFixed(root.decimals);
                root.editing = true;
                input.forceActiveFocus();
                input.selectAll();
            }
        }
    }

    TextInput {
        id: input
        visible: root.editing
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        width: 52
        horizontalAlignment: Text.AlignRight
        font.family: Appearance.font.family.main
        font.pixelSize: Appearance.font.pixelSize.small
        font.bold: root.bold
        color: root.color
        selectByMouse: true
        inputMethodHints: Qt.ImhFormattedNumbersOnly
        onAccepted: root.commit()
        onActiveFocusChanged: if (!activeFocus && root.editing) root.commit()
        Rectangle {
            anchors.fill: parent
            anchors.margins: -3
            z: -1
            radius: 4
            color: Qt.alpha(Appearance.colors.colPrimary, 0.15)
            border.width: 1
            border.color: Appearance.colors.colPrimary
        }
    }
}
