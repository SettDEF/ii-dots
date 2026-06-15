import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Qt5Compat.GraphicalEffects
import Qt.labs.synchronizer
import qs.modules.ii.sidebarRight.quickToggles.classicStyle

Item {
    id: root
    required property var scopeRoot
    property int sidebarPadding: 10
    anchors.fill: parent
    property bool aiChatEnabled: Config.options.policies.ai !== 0
    property bool translatorEnabled: Config.options.sidebar.translator.enable
    property bool animeEnabled: Config.options.policies.weeb !== 0
    property bool animeCloset: Config.options.policies.weeb === 2
    property bool drawEnabled: true
    // Title pill expand state — tapping the "Tools" pill toggles this and
    // reveals the tab chips inline, growing the pill horizontally. The pill's
    // grid_view icon rotates as the affordance.
    property bool toolsOpen: false

    property var pillTabs: []
    function updatePillTabs() {
        const tabs = [];
        if (Config.options.policies.ai !== 0) tabs.push({"id": "intelligence", "icon": "neurology", "label": Translation.tr("Intelligence")});
        if (Config.options.sidebar.translator.enable) tabs.push({"id": "translator", "icon": "translate", "label": Translation.tr("Translator")});
        if (Config.options.policies.weeb !== 0 && Config.options.policies.weeb !== 2) tabs.push({"id": "anime", "icon": "bookmark_heart", "label": Translation.tr("Anime")});
        if (root.drawEnabled) tabs.push({"id": "draw", "icon": "draw", "label": Translation.tr("Draw")});
        pillTabs = tabs;
    }
    Component.onCompleted: {
        if (Config.ready) {
            updatePillTabs();
        }
        if (GlobalStates.sidebarLeftFocusDraw) {
            if (root.drawTabIndex >= 0)
                swipeView.currentIndex = root.drawTabIndex
            GlobalStates.sidebarLeftFocusDraw = false
        } else if (GlobalStates.sidebarLeftFocusAi) {
            if (root.aiTabIndex >= 0)
                swipeView.currentIndex = root.aiTabIndex
            GlobalStates.sidebarLeftFocusAi = false
        }
        updateActiveTab();
    }
    property int tabCount: swipeView.count

    function focusActiveItem() {
        if (swipeView.currentItem) {
            if (swipeView.currentItem.item) {
                swipeView.currentItem.item.forceActiveFocus();
            } else {
                swipeView.currentItem.forceActiveFocus();
            }
        }
    }

    // Index of the Draw tab in pillTabs (== position in SwipeView).
    readonly property int drawTabIndex: pillTabs.findIndex(t => t.icon === "draw")
    readonly property int aiTabIndex: pillTabs.findIndex(t => t.id === "intelligence")

    function updateActiveTab() {
        if (swipeView.currentIndex >= 0 && swipeView.currentIndex < pillTabs.length) {
            GlobalStates.sidebarLeftActiveTab = pillTabs[swipeView.currentIndex].id;
        }
    }

    onPillTabsChanged: root.updateActiveTab()

    Connections {
        target: swipeView
        function onCurrentIndexChanged() {
            root.updateActiveTab()
        }
    }

    // The Draw shortcut sets GlobalStates.sidebarLeftFocusDraw.
    // When that's true, jump to the Draw tab once and clear the flag.
    Connections {
        target: GlobalStates
        function onSidebarLeftFocusDrawChanged() {
            if (!GlobalStates.sidebarLeftFocusDraw) return
            if (root.drawTabIndex >= 0)
                swipeView.currentIndex = root.drawTabIndex
            GlobalStates.sidebarLeftFocusDraw = false
        }
        function onSidebarLeftFocusAiChanged() {
            if (!GlobalStates.sidebarLeftFocusAi) return
            if (root.aiTabIndex >= 0) {
                swipeView.currentIndex = root.aiTabIndex
            }
            GlobalStates.sidebarLeftFocusAi = false
        }
        function onRequestSidebarLeftTab(tabId) {
            if (tabId === "draw" && root.drawTabIndex >= 0) {
                swipeView.currentIndex = root.drawTabIndex
                GlobalStates.sidebarLeftFocusDraw = false
            } else if (tabId === "intelligence" && root.aiTabIndex >= 0) {
                swipeView.currentIndex = root.aiTabIndex
                GlobalStates.sidebarLeftFocusAi = false
            }
        }
    }

    Connections {
        target: Config
        function onReadyChanged() {
            updatePillTabs();
        }
    }

    ColumnLayout {
        anchors {
            fill: parent
            margins: sidebarPadding
        }
        spacing: sidebarPadding

        // Top Header System Row matching SidebarRight style
        Item {
            Layout.fillWidth: true
            Layout.fillHeight: false
            implicitHeight: Math.max(leftSidebarTitleContainer.implicitHeight, leftSidebarButtonsRow.implicitHeight)

            // ── Tools pill (clickable, expands to reveal tab chips) ────────
            // Tap the pill → toolsOpen flips → the grid_view icon rotates and
            // a horizontal strip of tab chips slides out inside the same pill.
            // Pill auto-grows because its implicitWidth comes from the Row's
            // implicitWidth, which scales with the animated tabsContainer.
            Rectangle {
                id: leftSidebarTitleContainer
                anchors {
                    top: parent.top
                    bottom: parent.bottom
                    left: parent.left
                }
                color: titleHov.hovered
                    ? Appearance.colors.colLayer1Hover
                    : Appearance.colors.colLayer1
                radius: height / 2
                implicitWidth: leftSidebarTitleRow.implicitWidth + 24
                implicitHeight: leftSidebarTitleRow.implicitHeight + 8
                Behavior on color        { ColorAnimation  { duration: 180 } }
                Behavior on implicitWidth { NumberAnimation { duration: 240; easing.type: Easing.OutCubic } }

                HoverHandler { id: titleHov }
                TapHandler   { onTapped: root.toolsOpen = !root.toolsOpen }

                Row {
                    id: leftSidebarTitleRow
                    anchors.centerIn: parent
                    spacing: 8
                    MaterialSymbol {
                        anchors.verticalCenter: parent.verticalCenter
                        text: "grid_view"
                        iconSize: 20
                        color: Appearance.colors.colOnLayer0
                        rotation: root.toolsOpen ? 45 : 0
                        Behavior on rotation { NumberAnimation { duration: 260; easing.type: Easing.OutCubic } }
                    }
                    StyledText {
                        anchors.verticalCenter: parent.verticalCenter
                        font.pixelSize: Appearance.font.pixelSize.normal
                        color: Appearance.colors.colOnLayer0
                        text: Translation.tr("Tools")
                        font.weight: Font.DemiBold
                    }

                    // ── Expanding tab chip strip ───────────────────────────
                    // Sits at width 0 when closed (Row collapses it), grows to
                    // tabsRow.implicitWidth + a divider when open. `clip: true`
                    // keeps the chips from spilling out during the transition.
                    Item {
                        id: tabsContainer
                        anchors.verticalCenter: parent.verticalCenter
                        height: parent.height
                        clip: true
                        visible: root.pillTabs.length > 0
                        width: root.toolsOpen ? tabsRow.implicitWidth + 8 : 0
                        opacity: root.toolsOpen ? 1 : 0
                        Behavior on width   { NumberAnimation { duration: 260; easing.type: Easing.OutCubic } }
                        Behavior on opacity { NumberAnimation { duration: 200 } }

                        Row {
                            id: tabsRow
                            anchors.left: parent.left
                            anchors.leftMargin: 8
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 4

                            // Slim vertical divider between "Tools" label and chips.
                            Rectangle {
                                anchors.verticalCenter: parent.verticalCenter
                                width: 1; height: 14
                                color: Appearance.colors.colOnLayer0
                                opacity: 0.25
                            }

                            Repeater {
                                model: root.pillTabs
                                delegate: Rectangle {
                                    id: pill
                                    required property var modelData
                                    required property int index
                                    readonly property bool active: swipeView.currentIndex === index

                                    anchors.verticalCenter: parent.verticalCenter
                                    implicitHeight: 26
                                    implicitWidth: pillRow.implicitWidth + (active ? 16 : 10)
                                    radius: 13

                                    color: active
                                        ? Appearance.colors.colSecondaryContainer
                                        : (pillHov.hovered ? Appearance.colors.colLayer2 : "transparent")
                                    Behavior on color         { ColorAnimation  { duration: 160 } }
                                    Behavior on implicitWidth { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }

                                    HoverHandler { id: pillHov }
                                    TapHandler { onTapped: swipeView.currentIndex = pill.index }

                                    Row {
                                        id: pillRow
                                        anchors.centerIn: parent
                                        spacing: 5
                                        MaterialSymbol {
                                            anchors.verticalCenter: parent.verticalCenter
                                            text: pill.modelData.icon
                                            iconSize: 15
                                            fill: pill.active ? 1 : 0
                                            color: pill.active
                                                ? Appearance.m3colors.m3onSecondaryContainer
                                                : Appearance.colors.colOnLayer0
                                            Behavior on color { ColorAnimation { duration: 160 } }
                                        }
                                        StyledText {
                                            anchors.verticalCenter: parent.verticalCenter
                                            text: pill.modelData.label
                                            font.pixelSize: Appearance.font.pixelSize.smaller - 1
                                            font.weight: Font.DemiBold
                                            visible: pill.active
                                            color: Appearance.m3colors.m3onSecondaryContainer
                                        }
                                    }

                                    StyledToolTip {
                                        visible: pillHov.hovered && !pill.active
                                        text: pill.modelData.label
                                    }
                                }
                            }
                        }
                    }
                }
            }

            ButtonGroup {
                id: leftSidebarButtonsRow
                anchors {
                    top: parent.top
                    bottom: parent.bottom
                    right: parent.right
                }
                color: Appearance.colors.colLayer1
                padding: 4

                QuickToggleButton {
                    toggled: root.scopeRoot.pin
                    buttonIcon: "push_pin"
                    onClicked: root.scopeRoot.togglePin()
                    StyledToolTip {
                        text: Translation.tr("Pin sidebar (keep active workspace zone)")
                    }
                }
                QuickToggleButton {
                    toggled: root.scopeRoot.detach
                    buttonIcon: "open_in_new"
                    onClicked: root.scopeRoot.toggleDetach()
                    StyledToolTip {
                        text: Translation.tr("Detach sidebar into a floating window")
                    }
                }
                QuickToggleButton {
                    toggled: root.scopeRoot.extend
                    buttonIcon: root.scopeRoot.extend ? "first_page" : "last_page"
                    onClicked: root.scopeRoot.extend = !root.scopeRoot.extend
                    StyledToolTip {
                        text: root.scopeRoot.extend ? Translation.tr("Shrink sidebar width") : Translation.tr("Extend sidebar width")
                    }
                }
                QuickToggleButton {
                    toggled: false
                    buttonIcon: "close"
                    onClicked: GlobalStates.sidebarLeftOpen = false
                    StyledToolTip {
                        text: Translation.tr("Close sidebar")
                    }
                }
            }
        }

        Rectangle {
            Layout.fillWidth: true
            Layout.fillHeight: true
            implicitWidth: swipeView.implicitWidth
            implicitHeight: swipeView.implicitHeight
            radius: Appearance.rounding.normal
            color: Appearance.colors.colLayer1

            SwipeView { // Content pages
                id: swipeView
                anchors.fill: parent
                spacing: 10

                clip: true
                layer.enabled: true
                layer.effect: OpacityMask {
                    maskSource: Rectangle {
                        width: swipeView.width
                        height: swipeView.height
                        radius: Appearance.rounding.small
                    }
                }

                Repeater {
                    model: root.pillTabs
                    delegate: Loader {
    id: tabLoader
    required property var modelData
    required property int index
    active: true
    sourceComponent: {
        if (modelData.id === "intelligence") return aiChat;
        if (modelData.id === "translator") return translator;
        if (modelData.id === "anime") return anime;
        if (modelData.id === "draw") return drawPage;
        return placeholder;
    }
}
                }

                Loader {
                    active: root.pillTabs.length === 0
                    visible: active
                    sourceComponent: placeholder
                }
            }
        }

        Component {
            id: aiChat
            AiChat {}
        }
        Component {
            id: translator
            Translator {}
        }
        Component {
            id: anime
            Anime {}
        }
        Component {
            id: drawPage
            SidebarDrawPage {}
        }
        Component {
            id: placeholder
            Item {
                StyledText {
                    anchors.centerIn: parent
                    text: root.animeCloset ? Translation.tr("Nothing") : Translation.tr("Enjoy your empty sidebar...")
                    color: Appearance.colors.colSubtext
                }
            }
        }
    }

    // Expose a helper function to show a context menu from child items.
    function showContextMenu(targetItem, x, y, model) {
        const p = targetItem.mapToItem(root, x, y);
        sidebarContextMenu.popup(p.x, p.y, model);
    }

    PopupContextMenu {
        id: sidebarContextMenu
    }
}