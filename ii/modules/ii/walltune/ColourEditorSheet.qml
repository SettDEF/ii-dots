import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts

/// Palette > Edit colours: every variable of the palette and the terminal, by name. Click one to
/// pick a theme colour or type a hex; drag a swatch onto another to swap the two; reset undoes it.
PanelSheet {
    id: sheet
    title: qsTr("Edit colours")
    subtitle: ExactTheme.current !== "" ? ExactTheme.currentName : qsTr("Wallpaper colours")
    maxWidth: 420

    /// the variable whose picker is open
    property string editing: ""
    /// the variable being dragged
    property string dragging: ""
    property color dragColor: "transparent"

    onOpenChanged: if (open) { editing = ""; ExactTheme.loadVariables(); }

    readonly property var groups: [
        { id: "surfaces", label: qsTr("Surfaces") },
        { id: "text", label: qsTr("Text and lines") },
        { id: "accents", label: qsTr("Accents") },
        { id: "terminal", label: qsTr("Terminal") },
    ]
    readonly property int changed: Object.keys(ExactTheme.overrides).length

    RowLayout {
        Layout.fillWidth: true
        spacing: 8
        StyledText {
            Layout.fillWidth: true
            wrapMode: Text.WordWrap
            text: ExactTheme.applying ? qsTr("Applying…")
                : qsTr("Click to change · drag a swatch onto another to swap")
            font.pixelSize: Appearance.font.pixelSize.smallest
            color: ExactTheme.applying ? Appearance.colors.colPrimary : Appearance.colors.colSubtext
        }
        RippleButton {
            visible: sheet.changed > 0
            implicitHeight: 28
            implicitWidth: resetAllText.implicitWidth + 24
            buttonRadius: Appearance.rounding.full
            colBackground: Appearance.colors.colLayer2
            colBackgroundHover: Appearance.colors.colLayer2Hover
            onClicked: ExactTheme.resetAll()
            contentItem: StyledText {
                id: resetAllText
                horizontalAlignment: Text.AlignHCenter
                text: qsTr("Reset %1").arg(sheet.changed)
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: Appearance.colors.colOnLayer2
            }
        }
    }

    StyledFlickable {
        id: list
        Layout.fillWidth: true
        // the sheet does not scroll by itself: the list does, inside the card's height
        Layout.preferredHeight: Math.min(listCol.implicitHeight, sheet.height - 190)
        contentHeight: listCol.implicitHeight
        clip: true
        interactive: sheet.dragging === ""

        ColumnLayout {
            id: listCol
            width: list.width
            spacing: 10

            Repeater {
                model: sheet.groups
                delegate: ColumnLayout {
                    id: group
                    required property var modelData
                    readonly property var vars: ExactTheme.variables.filter(v => ExactTheme.groupOf(v.name) === modelData.id)
                    Layout.fillWidth: true
                    visible: vars.length > 0
                    spacing: 4

                    StyledText {
                        text: group.modelData.label
                        font.pixelSize: Appearance.font.pixelSize.smallest
                        font.weight: Font.DemiBold
                        color: Appearance.colors.colSubtext
                        Layout.leftMargin: 4
                    }
                    PaletteCard {
                        Repeater {
                            model: group.vars
                            delegate: ColumnLayout {
                                id: varRow
                                required property var modelData
                                required property int index
                                readonly property bool open: sheet.editing === modelData.name
                                readonly property bool target: drop.containsDrag && sheet.dragging !== modelData.name
                                Layout.fillWidth: true
                                spacing: 0

                                PaletteDivider { visible: varRow.index > 0 }
                                Rectangle {
                                    Layout.fillWidth: true
                                    implicitHeight: 44
                                    radius: Appearance.rounding.small
                                    color: varRow.target ? Appearance.colors.colPrimaryContainer
                                         : rowHover.hovered || varRow.open ? Appearance.colors.colLayer1Hover
                                         : "transparent"
                                    Behavior on color { ColorAnimation { duration: 120 } }

                                    HoverHandler { id: rowHover }
                                    TapHandler { onTapped: sheet.editing = varRow.open ? "" : varRow.modelData.name }
                                    DropArea {
                                        id: drop
                                        anchors.fill: parent
                                        keys: ["tinct-variable"]
                                        onDropped: ExactTheme.swap(sheet.dragging, varRow.modelData.name)
                                    }

                                    RowLayout {
                                        anchors.fill: parent
                                        anchors.leftMargin: 8
                                        anchors.rightMargin: 6
                                        spacing: 10

                                        // the swatch is the drag handle
                                        Rectangle {
                                            id: swatch
                                            Layout.preferredWidth: 28
                                            Layout.preferredHeight: 28
                                            radius: Appearance.rounding.verysmall
                                            color: varRow.modelData.value
                                            border.width: 1
                                            border.color: Appearance.colors.colLayer0Border
                                            opacity: sheet.dragging === varRow.modelData.name ? 0.35 : 1
                                            DragHandler {
                                                id: drag
                                                target: null
                                                grabPermissions: PointerHandler.CanTakeOverFromAnything
                                                onActiveChanged: {
                                                    if (active) {
                                                        sheet.dragging = varRow.modelData.name;
                                                        sheet.dragColor = varRow.modelData.value;
                                                    } else {
                                                        proxy.Drag.drop();
                                                        sheet.dragging = "";
                                                    }
                                                }
                                                onCentroidChanged: if (active) {
                                                    const p = proxy.parent.mapFromItem(null, centroid.scenePosition.x, centroid.scenePosition.y);
                                                    proxy.x = p.x - proxy.width / 2;
                                                    proxy.y = p.y - proxy.height / 2;
                                                }
                                            }
                                            HoverHandler { cursorShape: Qt.OpenHandCursor }
                                        }
                                        ColumnLayout {
                                            Layout.fillWidth: true
                                            spacing: 0
                                            StyledText {
                                                Layout.fillWidth: true
                                                text: varRow.modelData.name
                                                elide: Text.ElideRight
                                                font.family: Appearance.font.family.monospace
                                                font.pixelSize: Appearance.font.pixelSize.smaller
                                                color: Appearance.colors.colOnLayer1
                                            }
                                            StyledText {
                                                Layout.fillWidth: true
                                                // the ANSI name, the theme's own name for the colour, where it came from
                                                text: [varRow.modelData.ansi, varRow.modelData.colorName, varRow.modelData.source].filter(s => s).join(" · ")
                                                elide: Text.ElideRight
                                                font.pixelSize: Appearance.font.pixelSize.smallest
                                                color: varRow.modelData.source === "override" ? Appearance.colors.colPrimary : Appearance.colors.colSubtext
                                            }
                                        }
                                        StyledText {
                                            text: varRow.modelData.value
                                            font.family: Appearance.font.family.monospace
                                            font.pixelSize: Appearance.font.pixelSize.smaller
                                            color: Appearance.colors.colSubtext
                                        }
                                        RippleButton {
                                            visible: varRow.modelData.source === "override"
                                            implicitWidth: 28; implicitHeight: 28
                                            buttonRadius: 14
                                            colBackground: "transparent"
                                            colBackgroundHover: Appearance.colors.colLayer2Hover
                                            onClicked: ExactTheme.reset(varRow.modelData.name)
                                            contentItem: MaterialSymbol {
                                                horizontalAlignment: Text.AlignHCenter
                                                text: "undo"
                                                iconSize: Appearance.font.pixelSize.normal
                                                color: Appearance.colors.colOnLayer1
                                            }
                                            StyledToolTip { text: qsTr("Back to the theme's") }
                                        }
                                    }
                                }

                                // the picker: the theme's own colours, then a hex
                                ColumnLayout {
                                    visible: varRow.open
                                    Layout.fillWidth: true
                                    Layout.margins: 8
                                    spacing: 8

                                    Flow {
                                        Layout.fillWidth: true
                                        visible: ExactTheme.ownColors.length > 0
                                        spacing: 5
                                        Repeater {
                                            model: ExactTheme.ownColors
                                            delegate: Rectangle {
                                                id: own
                                                required property var modelData
                                                readonly property bool same: modelData.value.toLowerCase() === varRow.modelData.value
                                                width: 24; height: 24; radius: 12
                                                color: modelData.value
                                                border.width: same ? 2 : 1
                                                border.color: same ? Appearance.colors.colOnLayer1 : Appearance.colors.colLayer0Border
                                                TapHandler { onTapped: ExactTheme.setColor(varRow.modelData.name, own.modelData.name) }
                                                HoverHandler { id: ownHover }
                                                StyledToolTip { extraVisibleCondition: false; alternativeVisibleCondition: ownHover.hovered; text: own.modelData.name }
                                            }
                                        }
                                    }
                                    Rectangle {
                                        Layout.fillWidth: true
                                        implicitHeight: 34
                                        radius: Appearance.rounding.small
                                        color: Appearance.colors.colLayer2
                                        border.width: hex.activeFocus ? 1 : 0
                                        border.color: Appearance.colors.colPrimary
                                        StyledTextInput {
                                            id: hex
                                            anchors.fill: parent
                                            anchors.leftMargin: 10
                                            anchors.rightMargin: 10
                                            verticalAlignment: TextInput.AlignVCenter
                                            font.family: Appearance.font.family.monospace
                                            text: varRow.modelData.value
                                            validator: RegularExpressionValidator { regularExpression: /#?[0-9a-fA-F]{0,6}/ }
                                            onAccepted: {
                                                const v = (text.startsWith("#") ? text : "#" + text).toLowerCase();
                                                if (/^#[0-9a-f]{6}$/.test(v)) ExactTheme.setColor(varRow.modelData.name, v);
                                            }
                                        }
                                        StyledText {
                                            anchors.right: parent.right
                                            anchors.rightMargin: 10
                                            anchors.verticalCenter: parent.verticalCenter
                                            text: qsTr("Enter")
                                            font.pixelSize: Appearance.font.pixelSize.smallest
                                            color: Appearance.colors.colSubtext
                                            visible: hex.activeFocus
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    // what follows the pointer while a swatch is dragged (outside the list, so it is not clipped)
    Item {
        Layout.preferredHeight: 0
        Layout.fillWidth: true
        Rectangle {
            id: proxy
            parent: sheet
            visible: sheet.dragging !== ""
            z: 100
            width: 34; height: 34
            radius: Appearance.rounding.verysmall
            color: sheet.dragColor
            border.width: 2
            border.color: Appearance.colors.colOnLayer1
            Drag.active: sheet.dragging !== ""
            Drag.keys: ["tinct-variable"]
            Drag.hotSpot.x: width / 2
            Drag.hotSpot.y: height / 2
        }
    }
}
