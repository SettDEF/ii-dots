import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts

// Section container for dock widget windows; the config's card idiom.
Rectangle {
    id: root
    property string title: ""
    property bool padded: true
    default property alias content: inner.data

    Layout.fillWidth: true
    implicitHeight: inner.implicitHeight + (root.padded ? 24 : 12)
    radius: Appearance.rounding.normal
    color: Appearance.colors.colLayer1

    ColumnLayout {
        id: inner
        anchors {
            left: parent.left
            right: parent.right
            verticalCenter: parent.verticalCenter
            margins: root.padded ? 12 : 6
        }
        spacing: 6

        StyledText {
            visible: root.title.length > 0
            Layout.fillWidth: true
            text: root.title
            font.pixelSize: Appearance.font.pixelSize.smallest
            font.weight: Font.Medium
            color: Appearance.colors.colSubtext
        }
    }
}
