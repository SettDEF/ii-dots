import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts

/// Segmented selector with square cells: items = [{ id, label }].
Rectangle {
    id: seg
    property var items: []
    property string current: ""
    signal picked(string id)
    Layout.fillWidth: true
    implicitHeight: 26
    radius: 3
    color: "transparent"
    border.width: 1
    border.color: Qt.alpha(Appearance.colors.colOnLayer1, 0.10)
    RowLayout {
        anchors.fill: parent
        anchors.margins: 1
        spacing: 0
        Repeater {
            model: seg.items
            delegate: Rectangle {
                id: cell
                required property var modelData
                required property int index
                readonly property bool sel: seg.current === modelData.id
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.preferredWidth: 1
                radius: 2
                color: sel ? Qt.alpha(Appearance.m3colors.m3primary, 0.18) : cellMouse.containsMouse ? Qt.alpha(Appearance.colors.colOnLayer1, 0.05) : "transparent"
                Rectangle { visible: cell.index > 0; width: 1; height: parent.height - 8; anchors.verticalCenter: parent.verticalCenter; color: Qt.alpha(Appearance.colors.colOnLayer1, 0.10) }
                StyledText {
                    anchors.centerIn: parent
                    text: cell.modelData.label
                    font.pixelSize: 10
                    font.weight: Font.DemiBold
                    font.letterSpacing: 1
                    color: cell.sel ? Appearance.m3colors.m3primary : Appearance.colors.colSubtext
                }
                MouseArea { id: cellMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: seg.picked(cell.modelData.id) }
            }
        }
    }
}