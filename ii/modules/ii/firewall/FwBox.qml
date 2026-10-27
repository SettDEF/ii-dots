import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts

/// Opaque firewall box: hairline border, 3 px corners.
Rectangle {
    id: box
    default property alias body: boxCol.data
    property alias spacing: boxCol.spacing
    property int pad: 0
    Layout.fillWidth: true
    implicitHeight: boxCol.implicitHeight + pad * 2
    radius: 3
    color: Appearance.colors.colLayer1
    border.width: 1
    border.color: Qt.alpha(Appearance.colors.colOnLayer1, 0.10)
    ColumnLayout {
        id: boxCol
        anchors { left: parent.left; right: parent.right; top: parent.top; margins: box.pad }
        spacing: 0
    }
}