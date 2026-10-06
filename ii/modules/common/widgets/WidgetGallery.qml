// "Add widgets": every widget the registry knows, searchable, as tiles. A tile
// adds its widget, or removes it when it is already on, so the gallery is also
// the quickest way to see what is currently in use. Knows no widget; draws
// whatever catalog the registry holds.
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts

ColumnLayout {
    id: root

    required property var registry
    property string title: Translation.tr("Add widgets")

    spacing: 6

    StyledText {
        Layout.fillWidth: true
        Layout.topMargin: 8
        Layout.leftMargin: 4
        text: root.title
        font.pixelSize: Appearance.font.pixelSize.smallest
        font.weight: Font.Medium
        color: Appearance.colors.colSubtext
    }

    MaterialTextField {
        id: search
        Layout.fillWidth: true
        placeholderText: Translation.tr("Search widgets…")
    }

    readonly property var shown: {
        const q = search.text.trim().toLowerCase();
        return (root.registry.catalog ?? []).filter(w => q.length === 0
            || String(w.name).toLowerCase().includes(q));
    }

    Flow {
        Layout.fillWidth: true
        spacing: 6

        Repeater {
            model: root.shown
            delegate: RippleButton {
                id: tile
                required property var modelData
                readonly property bool on: root.registry.isEnabled(tile.modelData.id)

                implicitWidth: 92
                implicitHeight: 74
                buttonRadius: Appearance.rounding.normal
                colBackground: tile.on ? Appearance.colors.colPrimaryContainer
                                       : Appearance.colors.colLayer1
                onClicked: root.registry.toggle(tile.modelData.id)

                contentItem: ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 6
                    spacing: 2
                    MaterialSymbol {
                        Layout.alignment: Qt.AlignHCenter
                        text: tile.modelData.icon
                        iconSize: 24
                        fill: tile.on ? 1 : 0
                        color: tile.on ? Appearance.colors.colOnPrimaryContainer
                                       : Appearance.colors.colOnLayer1
                    }
                    StyledText {
                        Layout.fillWidth: true
                        horizontalAlignment: Text.AlignHCenter
                        text: tile.modelData.name
                        elide: Text.ElideRight
                        font.pixelSize: Appearance.font.pixelSize.smallest
                        color: tile.on ? Appearance.colors.colOnPrimaryContainer
                                       : Appearance.colors.colOnLayer1
                    }
                }

                // The check says "this is on the surface"; the tile colour says
                // it too, but not to someone who cannot tell the two apart.
                MaterialSymbol {
                    visible: tile.on
                    anchors { top: parent.top; right: parent.right; margins: 4 }
                    text: "check_circle"; iconSize: 14; fill: 1
                    color: Appearance.colors.colPrimary
                }
            }
        }
    }

    StyledText {
        visible: root.shown.length === 0
        Layout.fillWidth: true
        text: Translation.tr("No widget matches “%1”.").arg(search.text)
        font.pixelSize: Appearance.font.pixelSize.smaller
        color: Appearance.colors.colSubtext
    }
}
