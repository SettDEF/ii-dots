import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts

/// Column header row of a firewall table: cols = [[label, width or -1 to fill]].
RowLayout {
    id: head
    property var cols: []
    Layout.fillWidth: true
    Layout.leftMargin: 10
    Layout.rightMargin: 10
    Layout.topMargin: 6
    Layout.bottomMargin: 4
    spacing: 8
    Repeater {
        model: head.cols
        delegate: StyledText {
            required property var modelData
            text: modelData[0]
            font.pixelSize: 9
            font.weight: Font.DemiBold
            font.letterSpacing: 1.2
            color: Appearance.colors.colSubtext
            Layout.preferredWidth: modelData[1] > 0 ? modelData[1] : -1
            Layout.fillWidth: modelData[1] < 0
        }
    }
}
