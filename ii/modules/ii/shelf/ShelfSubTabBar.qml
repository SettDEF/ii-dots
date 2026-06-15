pragma ComponentBehavior: Bound
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts

Item {
    id: root

    required property var tabs      // [{ id, label, icon }]
    required property string current
    property int orientation: Qt.Horizontal      // Qt.Horizontal | Qt.Vertical
    signal tabSelected(string tabId)

    readonly property bool _vertical: orientation === Qt.Vertical

    implicitHeight: _vertical ? content.implicitHeight + 8 : 40
    implicitWidth:  content.implicitWidth + 8

    GridLayout {
        id: content
        anchors.centerIn: parent
        rows:    root._vertical ? root.tabs.length : 1
        columns: root._vertical ? 1 : root.tabs.length
        rowSpacing: 4
        columnSpacing: 4

        Repeater {
            model: root.tabs
            delegate: PillTab {
                required property var modelData
                Layout.fillWidth: root._vertical
                horizontalPadding: 10
                verticalPadding: root._vertical ? 8 : 0
                iconSize: Appearance.font.pixelSize.small
                labelSize: Appearance.font.pixelSize.smaller
                dimInactive: true
                icon: modelData.icon
                label: modelData.label
                active: root.current === modelData.id
                onTriggered: root.tabSelected(modelData.id)
            }
        }
    }
}
