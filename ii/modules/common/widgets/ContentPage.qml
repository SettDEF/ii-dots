import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets

StyledFlickable {
    id: root
    property real baseWidth: 600
    property bool forceWidth: false
    property real bottomContentPadding: 100

    default property alias data: contentColumn.data

    clip: true
    contentHeight: contentColumn.implicitHeight + root.bottomContentPadding // Add some padding at the bottom
    implicitWidth: contentColumn.implicitWidth
    
    ColumnLayout {
        id: contentColumn
        // Capped: a form whose rows run the full width of a 1100px window is
        // a long way for the eye to travel between a label and its control.
        // The cap is a constant, not root.width — root's own implicitWidth
        // comes from this column, so reading it back here is a binding loop
        // and the page lays out empty.
        readonly property real maxWidth: 880
        width: root.forceWidth ? root.baseWidth
             : Math.max(root.baseWidth, Math.min(implicitWidth, maxWidth))
        anchors {
            top: parent.top
            horizontalCenter: parent.horizontalCenter
            margins: 20
        }
        // The cards carry the separation now; 30 left them adrift.
        spacing: 18
    }

}
