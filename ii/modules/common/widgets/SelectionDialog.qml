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
        // Accents do not count: "portugues" finds Português.
        const plain = s => s.toString().toLowerCase().normalize("NFD").replace(/[\u0300-\u036f]/g, "");
        var query = plain(searchQuery).trim();
        const exact = items.filter(function(item) {
            return plain(item).indexOf(query) !== -1;
        });
        if (exact.length > 0 || query.length < 3) return exact;
        // Nothing contains it: allow a typo or two ("englsih" → English),
        // closest first, against the start of each word of an item.
        const allowed = query.length <= 4 ? 1 : 2;
        return items
            .map(item => ({ item, d: Math.min(...plain(item).split(/[\s()\-]+/)
                .filter(w => w.length > 0)
                .map(w => root._typoDistance(query, w.slice(0, query.length + 1)))) }))
            .filter(x => x.d <= allowed)
            .sort((a, b) => a.d - b.d)
            .map(x => x.item);
    }

    /// Edits between two short strings, a swap of neighbours counting as one
    /// (optimal string alignment), with `b` allowed one extra trailing letter.
    function _typoDistance(a, b) {
        const m = a.length, n = b.length;
        const d = [];
        for (let i = 0; i <= m; i++) { d.push([i]); }
        for (let j = 1; j <= n; j++) d[0][j] = j;
        for (let i = 1; i <= m; i++) {
            for (let j = 1; j <= n; j++) {
                const cost = a[i - 1] === b[j - 1] ? 0 : 1;
                d[i][j] = Math.min(d[i - 1][j] + 1, d[i][j - 1] + 1, d[i - 1][j - 1] + cost);
                if (i > 1 && j > 1 && a[i - 1] === b[j - 2] && a[i - 2] === b[j - 1])
                    d[i][j] = Math.min(d[i][j], d[i - 2][j - 2] + 1);
            }
        }
        // the query may stop short of the word: best over b's prefixes near m
        return Math.min(d[m][Math.max(0, n - 1)], d[m][n]);
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
                // A search list changes by dozens of rows per keystroke. With
                // the slide-out remove animation, a row still leaving when the
                // next keystroke landed was left behind, frozen half-faded on
                // top of the new rows — names drawn over each other.
                animateAppearance: false

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
