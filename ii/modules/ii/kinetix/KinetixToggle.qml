// A labelled switch row for the pointer panel, matching KinetixSlider.
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts

Rectangle {
    id: row

    property string label: ""
    property string hint: ""
    property bool checked: false
    // Named to avoid colliding with StyledSwitch's own `toggled` signal.
    signal toggledValue(bool v)

    Layout.fillWidth: true
    implicitHeight: 52
    radius: Appearance.rounding.small
    color: Appearance.colors.colLayer1

    RowLayout {
        anchors { fill: parent; leftMargin: 12; rightMargin: 12 }
        spacing: 10
        ColumnLayout {
            Layout.fillWidth: true
            spacing: 0
            StyledText {
                text: row.label
                font.pixelSize: Appearance.font.pixelSize.small
                color: Appearance.colors.colOnLayer1
            }
            StyledText {
                Layout.fillWidth: true
                text: row.hint
                elide: Text.ElideRight
                font.pixelSize: Appearance.font.pixelSize.smallest
                color: Appearance.colors.colSubtext
            }
        }
        StyledSwitch {
            checked: row.checked
            onToggled: row.toggledValue(checked)
        }
    }
}
