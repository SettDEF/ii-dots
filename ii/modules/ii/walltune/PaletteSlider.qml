import qs
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts

/// Title and value on one line, the slider under it.
ColumnLayout {
    id: sr
    property string title: ""
    property string valueText: ""
    property real from: 0
    property real to: 1
    property real stepSize: 0
    property real value: 0
    signal moved(real v)
    Layout.fillWidth: true
    Layout.leftMargin: 10
    Layout.rightMargin: 10
    Layout.topMargin: 6
    Layout.bottomMargin: 2
    spacing: 0
    RowLayout {
        Layout.fillWidth: true
        StyledText {
            Layout.fillWidth: true
            text: sr.title
            font.pixelSize: Appearance.font.pixelSize.smaller
            color: Appearance.colors.colOnLayer1
        }
        StyledText {
            text: sr.valueText
            font.pixelSize: Appearance.font.pixelSize.smallest
            font.family: Appearance.font.family.monospace
            color: Appearance.colors.colSubtext
        }
    }
    StyledSlider {
        Layout.fillWidth: true
        configuration: StyledSlider.Configuration.S
        from: sr.from
        to: sr.to
        stepSize: sr.stepSize
        value: sr.value
        onMoved: sr.moved(value)
    }
}
