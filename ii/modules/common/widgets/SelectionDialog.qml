import qs.modules.common
import qs.modules.common.widgets
import qs.services
import QtQuick
import QtQuick.Layouts
import Quickshell

Item {
    id: root
    property real dialogPadding: 15
    property real dialogMargin: 30
    property string titleText: "Selection Dialog"
    property var items: []
    property int selectedId: choiceListView.currentIndex
    property var defaultChoice

    property string searchQuery: ""
    readonly property var filteredItems: {
        if (!items) return [];
        if (searchQuery === "") return items;
        var query = searchQuery.toLowerCase();
        return items.filter(function(item) {
            return item.toString().toLowerCase().indexOf(query) !== -1;
        });
    }

    onFilteredItemsChanged: {
        choiceListView.currentIndex = root.defaultChoice !== undefined ? root.filteredItems.indexOf(root.defaultChoice) : -1;
    }
    onDefaultChoiceChanged: {
        choiceListView.currentIndex = root.defaultChoice !== undefined ? root.filteredItems.indexOf(root.defaultChoice) : -1;
    }
    Component.onCompleted: {
        choiceListView.currentIndex = root.defaultChoice !== undefined ? root.filteredItems.indexOf(root.defaultChoice) : -1;
    }

    signal canceled();
    signal selected(var result);

    Rectangle { // Scrim
        id: scrimOverlay
        anchors.fill: parent
        radius: Appearance.rounding.small
        color: Appearance.colors.colScrim
        MouseArea {
            hoverEnabled: true
            anchors.fill: parent
            preventStealing: true
            propagateComposedEvents: false
        }
    }

    Rectangle { // The dialog
        id: dialog
        color: Appearance.m3colors.m3surfaceContainerHigh
        radius: Appearance.rounding.normal
        anchors.fill: parent
        anchors.margins: dialogMargin
        implicitHeight: dialogColumnLayout.implicitHeight
        
        ColumnLayout {
            id: dialogColumnLayout
            anchors.fill: parent
            spacing: 16

            StyledText {
                id: dialogTitle
                Layout.topMargin: dialogPadding
                Layout.leftMargin: dialogPadding
                Layout.rightMargin: dialogPadding
                Layout.alignment: Qt.AlignLeft
                color: Appearance.m3colors.m3onSurface
                font.pixelSize: Appearance.font.pixelSize.larger
                text: root.titleText
            }

            Rectangle {
                color: Appearance.m3colors.m3outline
                implicitHeight: 1
                Layout.fillWidth: true
                Layout.leftMargin: dialogPadding
                Layout.rightMargin: dialogPadding
            }

            MaterialTextField {
                id: searchField
                visible: root.items.length > 8
                Layout.fillWidth: true
                Layout.leftMargin: root.dialogPadding
                Layout.rightMargin: root.dialogPadding
                placeholderText: Translation.tr("Search...")
                onTextChanged: {
                    root.searchQuery = text;
                }
                onVisibleChanged: {
                    if (visible) {
                        forceActiveFocus();
                    }
                }
                Component.onCompleted: {
                    if (visible) {
                        forceActiveFocus();
                    }
                }
                onAccepted: {
                    let index = choiceListView.currentIndex;
                    if (index === -1 && root.filteredItems.length > 0) {
                        index = 0;
                    }
                    if (index !== -1) {
                        root.selected(root.filteredItems[index]);
                    }
                }
            }

            StyledListView {
                id: choiceListView
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                currentIndex: root.defaultChoice !== undefined ? root.filteredItems.indexOf(root.defaultChoice) : -1
                spacing: 6

                model: ScriptModel {
                    id: choiceModel
                    values: root.filteredItems
                }

                delegate: StyledRadioButton {
                    id: radioButton
                    required property var modelData
                    required property int index
                    anchors {
                        left: parent?.left
                        right: parent?.right
                        leftMargin: root.dialogPadding
                        rightMargin: root.dialogPadding
                    }

                    description: modelData.toString()
                    checked: index === choiceListView.currentIndex

                    onCheckedChanged: {
                        if (checked) {
                            choiceListView.currentIndex = index;
                        }
                    }
                }
            }

            Rectangle {
                color: Appearance.m3colors.m3outline
                implicitHeight: 1
                Layout.fillWidth: true
                Layout.leftMargin: dialogPadding
                Layout.rightMargin: dialogPadding
            }

            RowLayout {
                id: dialogButtonsRowLayout
                Layout.bottomMargin: dialogPadding
                Layout.leftMargin: dialogPadding
                Layout.rightMargin: dialogPadding
                Layout.alignment: Qt.AlignRight

                DialogButton {
                    buttonText: Translation.tr("Cancel")
                    onClicked: root.canceled()
                }
                DialogButton {
                    buttonText: Translation.tr("OK")
                    onClicked: root.selected(
                        root.selectedId === -1 ? null :
                        root.filteredItems[root.selectedId]
                    )
                }
            }
        }
    }
}
