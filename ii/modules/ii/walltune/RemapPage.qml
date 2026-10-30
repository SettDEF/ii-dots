import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io

/// Look > Colour remap > palette: every preset in a list to search, by group, each with its colours.
PanelPage {
    id: page
    title: qsTr("Remap palette")
    /// WallTuneContent: its presets (remapPalettes) and the one picked (remapPalette)
    required property var look

    subtitle: shown.length === all.length ? qsTr("%1 palettes").arg(all.length)
                                          : qsTr("%1 of %2 palettes").arg(shown.length).arg(all.length)

    // the colours of each preset (palettes.json, the file the remap reads)
    FileView {
        id: palFile
        path: `${Directories.config}/quickshell/ii/scripts/colors/palettes.json`
        watchChanges: true
        onFileChanged: reload()
    }
    readonly property var colours: { try { return JSON.parse(palFile.text()) } catch (e) { return {} } }

    // the group of a preset: the house ones come before the first named theme in Look's list
    readonly property int firstTheme: look.remapPalettes.findIndex(p => p.id === "catppuccin_mocha")
    function group(p, i) {
        if (p.id === "") return "off";
        if (p.id.startsWith("base16_")) return "base16";
        return i < firstTheme ? "house" : "themes";
    }
    readonly property var all: look.remapPalettes.map((p, i) => Object.assign({ group: group(p, i) }, p))

    property string query: ""
    property string kind: "all"
    readonly property var shown: all.filter(p => p.group === "off"
        || ((kind === "all" || p.group === kind)
            && (query === "" || p.label.toLowerCase().includes(query.toLowerCase()) || p.id.includes(query.toLowerCase()))))

    onOpenChanged: if (open) search.forceActiveFocus()

    toolbar: [
        PillTextField {
            id: search
            Layout.fillWidth: true
            placeholderText: qsTr("Search palettes")
            onTextChanged: page.query = text.trim()
        },
        Flow {
            Layout.fillWidth: true
            spacing: 5
            Repeater {
                model: [{ id: "all", label: qsTr("All") }, { id: "themes", label: qsTr("Themes") },
                        { id: "base16", label: qsTr("Base16") }, { id: "house", label: qsTr("In-house") }]
                delegate: RippleButton {
                    id: kindChip
                    required property var modelData
                    readonly property bool sel: page.kind === modelData.id
                    implicitHeight: 28
                    implicitWidth: kindText.implicitWidth + 24
                    buttonRadius: Appearance.rounding.full
                    colBackground: sel ? Appearance.colors.colPrimary : Appearance.colors.colLayer2
                    colBackgroundHover: sel ? Appearance.colors.colPrimary : Appearance.colors.colLayer2Hover
                    onClicked: page.kind = modelData.id
                    contentItem: StyledText {
                        id: kindText
                        anchors.centerIn: parent
                        text: kindChip.modelData.label
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        color: kindChip.sel ? Appearance.colors.colOnPrimary : Appearance.colors.colOnLayer2
                    }
                }
            }
        }
    ]

    Rectangle {
        Layout.fillWidth: true
        Layout.fillHeight: true
        radius: Appearance.rounding.normal
        color: Appearance.colors.colLayer1
        StyledListView {
            id: list
            anchors.fill: parent
            anchors.margins: 4
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            reuseItems: true
            popin: false
            animateAppearance: false
            model: page.shown
            delegate: RippleButton {
                id: row
                required property var modelData
                readonly property bool chosen: page.look.remapPalette === modelData.id
                readonly property var cols: page.colours[modelData.id] ?? []
                width: ListView.view.width
                implicitHeight: 46
                buttonRadius: Appearance.rounding.small
                colBackground: chosen ? Appearance.colors.colPrimaryContainer : "transparent"
                colBackgroundHover: Appearance.colors.colLayer1Hover
                // the page stays: try one after another, back when done
                onClicked: page.look.remapPalette = modelData.id
                contentItem: RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 10
                    anchors.rightMargin: 10
                    spacing: 12
                    // up to eight of its colours, overlapping; "Off" gets an icon
                    Item {
                        Layout.preferredWidth: 20 + 7 * 10
                        Layout.preferredHeight: 20
                        MaterialSymbol {
                            visible: row.modelData.id === ""
                            anchors.verticalCenter: parent.verticalCenter
                            text: "block"
                            iconSize: Appearance.font.pixelSize.larger
                            color: Appearance.colors.colSubtext
                        }
                        Repeater {
                            model: row.cols.length > 8 ? row.cols.filter((c, i) => i % Math.ceil(row.cols.length / 8) === 0).slice(0, 8) : row.cols
                            delegate: Rectangle {
                                required property string modelData
                                required property int index
                                x: index * 10
                                anchors.verticalCenter: parent.verticalCenter
                                width: 20; height: 20; radius: 10
                                color: modelData
                                border.width: 2
                                border.color: Appearance.colors.colLayer1
                            }
                        }
                    }
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 0
                        StyledText {
                            Layout.fillWidth: true
                            text: row.modelData.label
                            elide: Text.ElideRight
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            font.weight: row.chosen ? Font.DemiBold : Font.Normal
                            color: row.chosen ? Appearance.colors.colOnPrimaryContainer : Appearance.colors.colOnLayer1
                        }
                        StyledText {
                            Layout.fillWidth: true
                            visible: row.modelData.id !== ""
                            text: ({ themes: qsTr("Theme"), base16: qsTr("Base16"), house: qsTr("In-house") })[row.modelData.group]
                                  + (row.cols.length ? " · " + qsTr("%1 colours").arg(row.cols.length) : "")
                            font.pixelSize: Appearance.font.pixelSize.smallest
                            color: Appearance.colors.colSubtext
                        }
                    }
                    MaterialSymbol {
                        visible: row.chosen
                        text: "check"
                        iconSize: Appearance.font.pixelSize.larger
                        color: Appearance.colors.colPrimary
                    }
                }
            }
        }
    }
}
