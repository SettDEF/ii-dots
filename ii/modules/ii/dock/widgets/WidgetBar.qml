import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts

// Label/value line over a thin progress track; turns to error colour when full.
ColumnLayout {
    id: root
    property string label: ""
    property string value: ""
    property real fraction: 0
    property bool critical: root.fraction > 0.9

    Layout.fillWidth: true
    spacing: 1

    WidgetRow {
        visible: root.label.length > 0 || root.value.length > 0
        label: root.label
        value: root.value
    }
    Rectangle {
        Layout.fillWidth: true
        implicitHeight: 5
        radius: Appearance.rounding.full
        color: Qt.alpha(Appearance.colors.colOnLayer0, 0.18)
        Rectangle {
            anchors { left: parent.left; top: parent.top; bottom: parent.bottom }
            width: parent.width * Math.max(0, Math.min(1, root.fraction))
            radius: parent.radius
            color: root.critical ? Appearance.m3colors.m3error : Appearance.colors.colPrimary
        }
    }
}
