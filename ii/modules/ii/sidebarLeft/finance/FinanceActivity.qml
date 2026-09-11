import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts

// Activity — the full transaction list, searchable and filterable by category.
Item {
    id: root

    property string query: ""
    property string categoryFilter: ""

    // Filtering lives here rather than in the service because it is view state:
    // two different tabs could want different filters over the same data.
    readonly property var filtered: {
        const q = root.query.trim().toLowerCase();
        const cat = root.categoryFilter;
        return Finance.transactions.filter(t => {
            if (cat.length > 0 && t.category !== cat) return false;
            if (q.length === 0) return true;
            return (t.counterparty ?? "").toLowerCase().includes(q)
                || (t.reference ?? "").toLowerCase().includes(q)
                || (t.category ?? "").toLowerCase().includes(q);
        });
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 8

        // ── Search ───────────────────────────────────────────────────────
        // PillTextField already does the leading icon, floating label and
        // clear button; hand-rolling a third search box would be the exact
        // duplication this config keeps asking me not to add.
        PillTextField {
            id: searchInput
            Layout.fillWidth: true
            pillWidth: parent.width
            placeholderText: qsTr("Search transactions")
            leadingIcon: "search"
            notchColor: Appearance.colors.colLayer1
            onTextChanged: root.query = text
        }

        // ── Category chips ───────────────────────────────────────────────
        Flow {
            Layout.fillWidth: true
            spacing: 5
            Repeater {
                model: [{ name: "" }].concat(Finance.categoriesSorted)
                delegate: Rectangle {
                    required property var modelData
                    readonly property bool sel: root.categoryFilter === modelData.name
                    implicitHeight: 26
                    implicitWidth: chipLabel.implicitWidth + 18
                    radius: Appearance.rounding.full
                    color: sel ? Appearance.colors.colPrimary : Appearance.colors.colLayer2
                    Behavior on color { ColorAnimation { duration: 140 } }
                    TapHandler { onTapped: root.categoryFilter = sel ? "" : modelData.name }
                    StyledText {
                        id: chipLabel
                        anchors.centerIn: parent
                        text: modelData.name.length === 0 ? qsTr("all") : modelData.name
                        font.pixelSize: Appearance.font.pixelSize.smallest
                        font.weight: Font.DemiBold
                        color: parent.sel ? Appearance.colors.colOnPrimary : Appearance.colors.colOnLayer2
                    }
                }
            }
        }

        StyledText {
            Layout.fillWidth: true
            visible: root.filtered.length === 0
            horizontalAlignment: Text.AlignHCenter
            topPadding: 20
            text: qsTr("Nothing matches")
            font.pixelSize: Appearance.font.pixelSize.smaller
            color: Appearance.colors.colSubtext
        }

        // ── The list ─────────────────────────────────────────────────────
        // A ListView, not a Repeater in a Flickable: this is the one place
        // that can hold hundreds of rows, and only a ListView recycles them.
        StyledListView {
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            spacing: 2
            model: root.filtered

            delegate: Rectangle {
                required property var modelData
                width: ListView.view.width
                implicitHeight: 44
                radius: Appearance.rounding.small
                color: rowHov.hovered ? Appearance.colors.colLayer2 : "transparent"
                Behavior on color { ColorAnimation { duration: 140 } }
                HoverHandler { id: rowHov }

                RowLayout {
                    anchors { fill: parent; leftMargin: 8; rightMargin: 8 }
                    spacing: 8

                    BrandIcon {
                        names: MerchantIcons.iconNamesFor(modelData.counterparty)
                        symbol: MerchantIcons.symbolFor(modelData.counterparty, modelData.category)
                        size: 20
                    }
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 0
                        StyledText {
                            text: modelData.counterparty.length > 0 ? modelData.counterparty : qsTr("(unknown)")
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            color: Appearance.colors.colOnLayer1
                            elide: Text.ElideRight
                            Layout.fillWidth: true
                        }
                        StyledText {
                            text: `${modelData.date} · ${modelData.category}`
                            font.pixelSize: Appearance.font.pixelSize.smallest
                            color: Appearance.colors.colSubtext
                            elide: Text.ElideRight
                            Layout.fillWidth: true
                        }
                    }
                    StyledText {
                        text: (modelData.amount < 0 ? "" : "+") + modelData.amount.toFixed(2)
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        font.family: Appearance.font.family.numbers
                        font.weight: Font.DemiBold
                        color: modelData.amount < 0
                            ? Appearance.colors.colOnLayer1 : Appearance.colors.colPrimary
                    }
                }
            }
        }
    }
}
