import qs
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts

/// A grouped settings card: rows inside share one height and one icon column.
Rectangle {
    default property alias content: cardCol.data
    Layout.fillWidth: true
    implicitHeight: cardCol.implicitHeight + 8
    radius: Appearance.rounding.normal
    color: Appearance.colors.colLayer1
    ColumnLayout {
        id: cardCol
        anchors { left: parent.left; right: parent.right; top: parent.top; margins: 4 }
        spacing: 0
    }
}
