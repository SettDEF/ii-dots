// The dock's settings, applying live. Shaped like Latte/Plasma's config
// windows: tab bar on top, action bar at the bottom.
//
// Own PopupWindow: the dock's surface is only as tall as the dock, and
// rect.y places the popup's BOTTOM.
pragma ComponentBehavior: Bound
import qs
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts
import Quickshell

PopupWindow {
    id: root

    /// Any item inside the dock window; used to find that window.
    required property Item anchorItem
    property real panelWidth: Appearance.sizes.dockEditPanelWidth

    readonly property real hostWidth: root.anchorItem?.QsWindow?.window?.width ?? 0
    readonly property real hostHeight: root.anchorItem?.QsWindow?.window?.height ?? 0

    color: "transparent"
    visible: GlobalStates.dockEditMode && root.hostWidth > 0 && root.hostHeight > 0

    // mapFromItem() latches, so re-sync while the dock animates.
    property int _tick: 0
    Timer { running: root.visible; interval: 100; repeat: true; onTriggered: root._tick++ }
    readonly property real dockTop: {
        root._tick;
        root.hostHeight;
        return Appearance.sizes.elevationMargin;
    }

    anchor {
        window: root.anchorItem ? root.anchorItem.QsWindow.window : null
        gravity: Edges.Top | Edges.Right
        edges: Edges.Top | Edges.Left
        adjustment: PopupAdjustment.None
        rect: Qt.rect(0, root.dockTop, 1, 1)
    }

    implicitWidth: Math.max(1, root.hostWidth)
    /// Room above the dock, so the panel can't run off a shorter screen.
    readonly property real maxCardHeight: {
        const win = root.anchorItem?.QsWindow?.window ?? null;
        if (!win) return 400;
        return Math.max(200, ScreenFit.logicalHeight(win) - ScreenFit.reservedTop(win)
            - win.height - Appearance.sizes.elevationMargin * 2 - 8);
    }
    implicitHeight: Math.max(1, card.implicitHeight + Appearance.sizes.elevationMargin * 2)

    mask: Region { item: card }

    Rectangle {
        id: card
        x: Math.round((parent.width - width) / 2)
        anchors.bottom: parent.bottom
        anchors.bottomMargin: Appearance.sizes.elevationMargin
        width: root.panelWidth
        // shell sums its children, so nothing is hand-counted. Not circular:
        // no child uses fillHeight, so none of them measure the card back.
        implicitHeight: shell.implicitHeight + shell.anchors.margins * 2
        height: card.implicitHeight
        radius: Appearance.rounding.large
        color: Appearance.colors.colLayer0Base
        border.width: 1
        border.color: Appearance.colors.colLayer0Border

        focus: root.visible
        Keys.onEscapePressed: event => { GlobalStates.dockEditMode = false; event.accepted = true }

        MouseArea { anchors.fill: parent; acceptedButtons: Qt.AllButtons }

        ColumnLayout {
            id: shell
            anchors { fill: parent; margins: 10 }
            spacing: 6

            // ── Title bar ───────────────────────────────────────────────
            RowLayout {
                id: header
                Layout.fillWidth: true
                spacing: 8
                MaterialSymbol {
                    text: "tune"
                    iconSize: Appearance.font.pixelSize.larger
                    color: Appearance.colors.colPrimary
                }
                StyledText {
                    Layout.fillWidth: true
                    text: Translation.tr("Editing dock")
                    font.pixelSize: Appearance.font.pixelSize.normal
                    font.weight: Font.Medium
                    color: Appearance.colors.colOnLayer0
                }
                RippleButton {
                    implicitWidth: 28
                    implicitHeight: 28
                    buttonRadius: Appearance.rounding.full
                    onClicked: GlobalStates.dockEditMode = false
                    contentItem: MaterialSymbol {
                        anchors.centerIn: parent
                        text: "close"
                        iconSize: Appearance.font.pixelSize.large
                        color: Appearance.colors.colOnLayer0
                    }
                }
            }

            SecondaryTabBar {
                id: tabBar
                Layout.fillWidth: true
                // Restored once, not bound: TabBar assigns currentIndex during
                // construction, which would destroy a binding here.
                Component.onCompleted: tabBar.currentIndex = Persistent.states.dock.editTab
                onCurrentIndexChanged: Persistent.states.dock.editTab = tabBar.currentIndex
                SecondaryTabButton { buttonIcon: "sync_alt"; buttonText: Translation.tr("Behaviour") }
                SecondaryTabButton { buttonIcon: "palette"; buttonText: Translation.tr("Appearance") }
                SecondaryTabButton { buttonIcon: "widgets"; buttonText: Translation.tr("Widgets") }
            }

            // ── Page ────────────────────────────────────────────────────
            // Not a StackLayout: its implicitHeight is the tallest page.
            StyledFlickable {
                id: body
                Layout.fillWidth: true
                // Capped, not filled: fillHeight contributes 0 to shell's implicit
                // height and collapsed the page to nothing.
                Layout.preferredHeight: Math.min(page.implicitHeight, root.maxCardHeight - 200)
                contentHeight: page.implicitHeight
                interactive: contentHeight > height
                clip: true

                Loader {
                    id: page
                    width: body.width
                    sourceComponent: tabBar.currentIndex === 0 ? behaviourPage
                        : tabBar.currentIndex === 1 ? appearancePage : widgetsPage
                }
            }

            // ── Action bar ──────────────────────────────────────────────
            Rectangle {
                Layout.fillWidth: true
                implicitHeight: 1
                color: Appearance.colors.colOutlineVariant
            }
            RowLayout {
                id: footer
                Layout.fillWidth: true
                Layout.topMargin: 2
                spacing: 8
                StyledText {
                    Layout.fillWidth: true
                    text: Translation.tr("Drag the dock's top edge to resize it.")
                    font.pixelSize: Appearance.font.pixelSize.smallest
                    color: Appearance.colors.colSubtext
                    wrapMode: Text.WordWrap
                }
                RippleButton {
                    implicitHeight: 30
                    implicitWidth: doneLabel.implicitWidth + 28
                    buttonRadius: Appearance.rounding.full
                    colBackground: Appearance.colors.colPrimary
                    onClicked: GlobalStates.dockEditMode = false
                    contentItem: StyledText {
                        id: doneLabel
                        anchors.centerIn: parent
                        text: Translation.tr("Done")
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        font.weight: Font.Medium
                        color: Appearance.colors.colOnPrimary
                    }
                }
            }
        }
    }

    // ── What the dock does ──────────────────────────────────────────────
    Component {
        id: behaviourPage
        ColumnLayout {
            spacing: 2
            ConfigSwitch {
                buttonIcon: "visibility"
                text: Translation.tr("Reveal on hover")
                checked: Config.options.dock.hoverToReveal
                onCheckedChanged: Config.options.dock.hoverToReveal = checked
            }
            ConfigSpinBox {
                text: Translation.tr("Reveal zone")
                value: Config.options.dock.hoverRegionHeight
                from: 1; to: 20; stepSize: 1
                enabled: Config.options.dock.hoverToReveal
                onValueChanged: Config.options.dock.hoverRegionHeight = value
            }
            ConfigSwitch {
                buttonIcon: "push_pin"
                text: Translation.tr("Pinned at startup")
                checked: Config.options.dock.pinnedOnStartup
                onCheckedChanged: Config.options.dock.pinnedOnStartup = checked
            }
            ConfigSwitch {
                buttonIcon: "keep"
                text: Translation.tr("Pin button")
                checked: Config.options.dock.showPinButton
                onCheckedChanged: Config.options.dock.showPinButton = checked
            }
        }
    }

    // ── What the dock looks like ────────────────────────────────────────
    Component {
        id: appearancePage
        ColumnLayout {
            spacing: 2
            ConfigSpinBox {
                text: Translation.tr("Height")
                value: Config.options.dock.height
                from: 40; to: 120; stepSize: 2
                onValueChanged: Config.options.dock.height = value
            }
            ConfigSpinBox {
                text: Translation.tr("Item spacing")
                value: Config.options.dock.spacing
                from: 0; to: 24; stepSize: 1
                onValueChanged: Config.options.dock.spacing = value
            }
            ConfigSwitch {
                buttonIcon: "wallpaper"
                text: Translation.tr("Background")
                checked: Config.options.dock.showBackground
                onCheckedChanged: Config.options.dock.showBackground = checked
            }
            ConfigSwitch {
                buttonIcon: "select_all"
                text: Translation.tr("Floating")
                checked: Config.options.dock.floating
                onCheckedChanged: Config.options.dock.floating = checked
            }
            ConfigSpinBox {
                text: Translation.tr("Floating margin")
                value: Config.options.dock.floatingMargin
                from: 0; to: 40; stepSize: 1
                enabled: Config.options.dock.floating
                onValueChanged: Config.options.dock.floatingMargin = value
            }
            ConfigSwitch {
                buttonIcon: "filter_b_and_w"
                text: Translation.tr("Monochrome icons")
                checked: Config.options.dock.monochromeIcons
                onCheckedChanged: Config.options.dock.monochromeIcons = checked
            }
        }
    }

    // ── What the dock contains ──────────────────────────────────────────
    Component {
        id: widgetsPage
        ColumnLayout {
            spacing: 2

            ConfigSwitch {
                buttonIcon: "apps"
                text: Translation.tr("Apps button")
                checked: Config.options.dock.showAppsButton
                onCheckedChanged: Config.options.dock.showAppsButton = checked
            }
            ConfigSwitch {
                buttonIcon: "music_note"
                text: Translation.tr("Media player")
                checked: Config.options.dock.showMedia
                onCheckedChanged: Config.options.dock.showMedia = checked
            }
            ConfigSwitch {
                buttonIcon: "open_in_full"
                text: Translation.tr("Expand media on hover")
                checked: Config.options.dock.mediaExpandOnHover
                enabled: Config.options.dock.showMedia
                onCheckedChanged: Config.options.dock.mediaExpandOnHover = checked
            }

            StyledText {
                Layout.fillWidth: true
                Layout.topMargin: 8
                Layout.leftMargin: 4
                text: Translation.tr("Folder grid")
                font.pixelSize: Appearance.font.pixelSize.smallest
                font.weight: Font.Medium
                color: Appearance.colors.colSubtext
            }
            ConfigSelectionArray {
                currentValue: Config.options.dock.folderGrid
                onSelected: newValue => { Config.options.dock.folderGrid = newValue; }
                options: [
                    { displayName: Translation.tr("Always"), icon: "check", value: "always" },
                    { displayName: Translation.tr("No windows"), icon: "filter_alt", value: "noWindows" },
                    { displayName: Translation.tr("Off"), icon: "close", value: "off" }
                ]
            }

            StyledText {
                Layout.fillWidth: true
                Layout.topMargin: 8
                Layout.leftMargin: 4
                text: Translation.tr("Dock widgets")
                font.pixelSize: Appearance.font.pixelSize.smallest
                font.weight: Font.Medium
                color: Appearance.colors.colSubtext
            }
            Repeater {
                model: DockWidgets.catalog
                delegate: Rectangle {
                    id: widgetBlock
                    required property var modelData
                    readonly property bool on: DockWidgets.isEnabled(widgetBlock.modelData.id)
                    readonly property var schema: widgetBlock.modelData.settings ?? []

                    Layout.fillWidth: true
                    Layout.topMargin: 4
                    implicitHeight: widgetCol.implicitHeight + 12
                    radius: Appearance.rounding.normal
                    // An enabled widget carries its settings, so it gets a
                    // surface; a disabled one is just a row in a list.
                    color: widgetBlock.on ? Appearance.colors.colLayer1 : ColorUtils.transparentize(Appearance.colors.colLayer1)
                    Behavior on color { ColorAnimation { duration: 160 } }

                    ColumnLayout {
                        id: widgetCol
                        anchors {
                            left: parent.left; right: parent.right
                            verticalCenter: parent.verticalCenter
                            leftMargin: 4; rightMargin: 4
                        }
                        spacing: 0

                        RowLayout {
                            id: widgetRow
                            readonly property var modelData: widgetBlock.modelData
                            readonly property bool on: widgetBlock.on
                            Layout.fillWidth: true
                            spacing: 0

                            ConfigSwitch {
                                Layout.fillWidth: true
                                buttonIcon: widgetRow.modelData.icon
                                text: widgetRow.modelData.name
                                checked: widgetRow.on
                                onCheckedChanged: {
                                    if (checked !== widgetRow.on)
                                        DockWidgets.toggle(widgetRow.modelData.id);
                                }
                            }
                            // Reorder only makes sense once it is on the dock.
                            RippleButton {
                                visible: widgetRow.on
                                implicitWidth: 26
                                implicitHeight: 26
                                buttonRadius: Appearance.rounding.full
                                onClicked: DockWidgets.move(widgetRow.modelData.id, -1)
                                contentItem: MaterialSymbol {
                                    anchors.centerIn: parent
                                    text: "chevron_left"
                                    iconSize: Appearance.font.pixelSize.large
                                    color: Appearance.colors.colOnLayer0
                                }
                            }
                            RippleButton {
                                visible: widgetRow.on
                                implicitWidth: 26
                                implicitHeight: 26
                                buttonRadius: Appearance.rounding.full
                                onClicked: DockWidgets.move(widgetRow.modelData.id, 1)
                                contentItem: MaterialSymbol {
                                    anchors.centerIn: parent
                                    text: "chevron_right"
                                    iconSize: Appearance.font.pixelSize.large
                                    color: Appearance.colors.colOnLayer0
                                }
                            }
                        }

                        // Hairline between a widget and its own settings, so
                        // the sub-rows read as belonging to it rather than as
                        // more widgets.
                        Rectangle {
                            visible: widgetBlock.on && widgetBlock.schema.length > 0
                            Layout.fillWidth: true
                            Layout.leftMargin: 10
                            Layout.rightMargin: 10
                            Layout.topMargin: 2
                            Layout.bottomMargin: 2
                            implicitHeight: 1
                            color: Appearance.colors.colOutlineVariant
                            opacity: 0.6
                        }

                        // Rendered from the widget's schema; this panel knows no widget.
                        Repeater {
                            model: widgetBlock.on ? widgetBlock.schema : []
                            delegate: Loader {
                                required property var modelData
                                readonly property string wid: widgetBlock.modelData.id
                                Layout.fillWidth: true
                                Layout.leftMargin: 10
                                sourceComponent: modelData.type === "int" ? intSetting : boolSetting
                            }
                        }
                    }
                }
            }
        }
    }

    Component {
        id: boolSetting
        ConfigSwitch {
            text: parent.modelData.label
            checked: DockWidgets.get(parent.wid, parent.modelData.key) === true
            onCheckedChanged: {
                if (checked !== (DockWidgets.get(parent.wid, parent.modelData.key) === true))
                    DockWidgets.set(parent.wid, parent.modelData.key, checked);
            }
        }
    }
    Component {
        id: intSetting
        ConfigSpinBox {
            text: parent.modelData.label
            value: DockWidgets.get(parent.wid, parent.modelData.key) ?? 0
            from: parent.modelData.min ?? 0
            to: parent.modelData.max ?? 100
            stepSize: 1
            onValueChanged: DockWidgets.set(parent.wid, parent.modelData.key, value)
        }
    }
}
