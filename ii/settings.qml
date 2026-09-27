//@ pragma UseQApplication
//@ pragma Env QS_NO_RELOAD_POPUP=1
//@ pragma Env QT_QUICK_CONTROLS_STYLE=Basic
//@ pragma Env QT_QUICK_FLICKABLE_WHEEL_DECELERATION=10000

// Adjust this to make the app smaller or larger
//@ pragma Env QT_SCALE_FACTOR=1

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Window
import Quickshell
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions as CF

ApplicationWindow {
    id: root
    property string firstRunFilePath: CF.FileUtils.trimFileProtocol(`${Directories.state}/user/first_run.txt`)
    property string firstRunFileContent: "This file is just here to confirm you've been greeted :>"
    property real contentPadding: 8
    property bool showNextTime: false
    // Grouped, and ordered by how often somebody actually needs them rather
    // than alphabetically. `group` is the heading the rail draws ABOVE a page,
    // so only the first page of each group carries one — see
    // NavigationRailButton.groupLabel.
    //
    // The grouping is the point: a flat list is why Interface grew to a
    // thousand lines with twenty sections in it. New settings now have an
    // obvious page to land on instead of the nearest one that already exists.
    property var pages: [
        {
            group: Translation.tr("Setup"),
            name: Translation.tr("Quick"),
            icon: "instant_mix",
            component: "modules/settings/QuickConfig.qml"
        },
        {
            name: Translation.tr("System"),
            icon: "tune",
            component: "modules/settings/SystemConfig.qml"
        },
        {
            group: Translation.tr("Look"),
            name: Translation.tr("Bar"),
            icon: "toast",
            iconRotation: 180,
            component: "modules/settings/BarConfig.qml"
        },
        {
            name: Translation.tr("Background"),
            icon: "texture",
            component: "modules/settings/BackgroundConfig.qml"
        },
        {
            name: Translation.tr("Interface"),
            icon: "bottom_app_bar",
            component: "modules/settings/InterfaceConfig.qml"
        },
        {
            group: Translation.tr("Behaviour"),
            name: Translation.tr("General"),
            icon: "browse",
            component: "modules/settings/GeneralConfig.qml"
        },
        {
            name: Translation.tr("Pointer"),
            icon: "mouse",
            component: "modules/settings/PointerConfig.qml"
        },
        {
            name: Translation.tr("Services"),
            icon: "settings",
            component: "modules/settings/ServicesConfig.qml"
        },
        {
            group: Translation.tr("Machine"),
            name: Translation.tr("Performance"),
            icon: "speed",
            component: "modules/settings/PerformanceConfig.qml"
        },
        {
            name: Translation.tr("Advanced"),
            icon: "construction",
            component: "modules/settings/AdvancedConfig.qml"
        },
        {
            name: Translation.tr("About"),
            icon: "info",
            component: "modules/settings/About.qml"
        }
    ]
    property int currentPage: 0

    // Row that search asked us to reveal once its page has loaded.
    property string pendingReveal: ""

    // Depth-first hunt for the item showing this exact label. Rows are built
    // from shared widgets whose visible label is a nested StyledText, so we
    // match on text rather than on any id the page would have to declare.
    function findByText(item, txt) {
        if (!item) return null;
        if (item.text !== undefined && String(item.text) === txt) return item;
        const kids = item.children ?? [];
        for (let i = 0; i < kids.length; ++i) {
            const found = root.findByText(kids[i], txt);
            if (found) return found;
        }
        return null;
    }

    function revealPending() {
        const txt = root.pendingReveal;
        root.pendingReveal = "";
        const flick = pageLoader.item;
        if (txt.length === 0 || !flick) return;
        const target = root.findByText(flick, txt);
        if (!target) return;
        // ContentPage IS the flickable, so map into its contentItem to get a
        // content-space y, then park the row a third of the way down rather
        // than flush against the top edge.
        const pos = target.mapToItem(flick.contentItem, 0, 0);
        const maxY = Math.max(0, flick.contentHeight - flick.height);
        flick.contentY = Math.max(0, Math.min(pos.y - flick.height / 3, maxY));
        const inLoader = target.mapToItem(pageLoader, 0, 0);
        revealFlash.x = inLoader.x - 6;
        revealFlash.y = inLoader.y - 6;
        revealFlash.width = Math.max(target.width, 120) + 12;
        revealFlash.height = target.height + 12;
        flashAnim.restart();
    }

    Timer {
        id: revealTimer
        interval: 180          // let the page finish laying out before measuring
        onTriggered: root.revealPending()
    }

    visible: true
    onClosing: Qt.quit()
    title: "illogical-impulse Settings"

    Component.onCompleted: {
        MaterialThemeLoader.reapplyTheme()
        Config.readWriteDelay = 0 // Settings app always only sets one var at a time so delay isn't needed
        // Search maps an indexed row back to a page; derive it from the page
        // list above rather than hardcoding the mapping a second time.
        const map = ({});
        for (let i = 0; i < root.pages.length; ++i)
            map[String(root.pages[i].component).split("/").pop()] = i;
        SettingsIndex.pageForFile = map;
    }

    minimumWidth: 750
    minimumHeight: 500
    width: 1100
    height: 750
    color: Appearance.m3colors.m3background

    ColumnLayout {
        anchors {
            fill: parent
            margins: contentPadding
        }

        Keys.onPressed: (event) => {
            if (event.modifiers === Qt.ControlModifier) {
                if (event.key === Qt.Key_PageDown) {
                    root.currentPage = Math.min(root.currentPage + 1, root.pages.length - 1)
                    event.accepted = true;
                } 
                else if (event.key === Qt.Key_PageUp) {
                    root.currentPage = Math.max(root.currentPage - 1, 0)
                    event.accepted = true;
                }
                else if (event.key === Qt.Key_Tab) {
                    root.currentPage = (root.currentPage + 1) % root.pages.length;
                    event.accepted = true;
                }
                else if (event.key === Qt.Key_Backtab) {
                    root.currentPage = (root.currentPage - 1 + root.pages.length) % root.pages.length;
                    event.accepted = true;
                }
            }
        }

        Item { // Titlebar
            visible: Config.options?.windows.showTitlebar
            Layout.fillWidth: true
            Layout.fillHeight: false
            implicitHeight: Math.max(titleText.implicitHeight, windowControlsRow.implicitHeight)
            StyledText {
                id: titleText
                anchors {
                    left: Config.options.windows.centerTitle ? undefined : parent.left
                    horizontalCenter: Config.options.windows.centerTitle ? parent.horizontalCenter : undefined
                    verticalCenter: parent.verticalCenter
                    leftMargin: 12
                }
                color: Appearance.colors.colOnLayer0
                text: Translation.tr("Settings")
                font {
                    family: Appearance.font.family.title
                    pixelSize: Appearance.font.pixelSize.title
                    variableAxes: Appearance.font.variableAxes.title
                }
            }
            // ── Search over every setting ───────────────────────────
            Item {
                id: searchWrapper
                anchors.verticalCenter: parent.verticalCenter
                anchors.right: windowControlsRow.left
                anchors.rightMargin: 8
                implicitWidth: 230
                implicitHeight: 34

                PillTextField {
                    id: searchField
                    // Re-read pages, packs and shaders when you start typing —
                    // FolderListModel does not watch directories, so without
                    // this a newly added effect would be missing from search.
                    onActiveFocusChanged: if (activeFocus) SettingsIndex.refresh()
                    anchors.fill: parent
                    placeholderText: Translation.tr("Search settings…")
                    leadingIcon: "search"
                    onCleared: searchField.inputItem.forceActiveFocus()
                }

                // Results float over the content rather than pushing it.
                Rectangle {
                    id: resultsPopup
                    readonly property var results:
                        SettingsIndex.search(searchField.text, 10)
                    visible: searchField.text.length > 0 && searchField.activeFocus
                        || (searchField.text.length > 0 && resultsHov.hovered)
                    anchors.top: parent.bottom
                    anchors.topMargin: 6
                    anchors.right: parent.right
                    width: 330
                    implicitHeight: Math.min(340, resultsCol.implicitHeight + 12)
                    radius: Appearance.rounding.normal
                    color: Appearance.colors.colLayer1
                    border.width: 1
                    border.color: Appearance.colors.colLayer0Border
                    z: 500
                    HoverHandler { id: resultsHov }

                    StyledFlickable {
                        anchors.fill: parent
                        anchors.margins: 6
                        contentHeight: resultsCol.implicitHeight
                        clip: true

                        ColumnLayout {
                            id: resultsCol
                            width: parent.width
                            spacing: 2

                            StyledText {
                                Layout.fillWidth: true
                                Layout.margins: 6
                                visible: resultsPopup.results.length === 0
                                text: SettingsIndex.ready
                                    ? Translation.tr("No matching setting")
                                    : Translation.tr("Building index…")
                                font.pixelSize: Appearance.font.pixelSize.smaller
                                color: Appearance.colors.colSubtext
                            }

                            Repeater {
                                model: ScriptModel { values: resultsPopup.results }
                                delegate: Rectangle {
                                    id: hit
                                    required property var modelData
                                    readonly property int pageIdx: SettingsIndex.pageIndexOf(hit.modelData)
                                    readonly property bool external:
                                        String(hit.modelData.file).startsWith("@")
                                    readonly property bool inert:
                                        String(hit.modelData.file) === "@keybind"
                                    Layout.fillWidth: true
                                    implicitHeight: 46
                                    radius: Appearance.rounding.small
                                    color: hitHov.hovered ? Appearance.colors.colLayer1Hover : "transparent"
                                    Behavior on color { ColorAnimation { duration: 120 } }
                                    HoverHandler {
                                        id: hitHov
                                        cursorShape: hit.inert ? Qt.ArrowCursor : Qt.PointingHandCursor
                                    }
                                    TapHandler {
                                        onTapped: {
                                            // Effects and shaders don't live on
                                            // a settings page — they belong to
                                            // the display panel in the shell,
                                            // so hand off over IPC instead of
                                            // trying to navigate here.
                                            const f = String(hit.modelData.file);
                                            if (f === "@action") {
                                                // The search box doubles as a
                                                // command palette for anything
                                                // the shell exposes over IPC.
                                                Quickshell.execDetached(
                                                    ["qs", "-c", "ii", "ipc", "call",
                                                     hit.modelData.target, hit.modelData.func]);
                                                searchField.text = "";
                                                return;
                                            }
                                            if (f === "@keybind") {
                                                // Informational on purpose: some
                                                // binds exit the session, and a
                                                // search result is too easy to
                                                // hit by accident to fire those.
                                                return;
                                            }
                                            if (hit.external) {
                                                Quickshell.execDetached(
                                                    ["qs", "-c", "ii", "ipc", "call", "display", "open"]);
                                                searchField.text = "";
                                                return;
                                            }
                                            if (hit.pageIdx < 0) return;
                                            root.pendingReveal = hit.modelData.title;
                                            root.currentPage = hit.pageIdx;
                                            searchField.text = "";
                                        }
                                    }
                                    RowLayout {
                                        anchors.fill: parent
                                        anchors.leftMargin: 9
                                        anchors.rightMargin: 9
                                        spacing: 8
                                        MaterialSymbol {
                                            text: hit.modelData.file === "@effect" ? "animation"
                                                : hit.modelData.file === "@shader" ? "auto_awesome"
                                                : hit.modelData.file === "@action" ? "play_arrow"
                                                : hit.modelData.file === "@keybind" ? "keyboard"
                                                : (hit.pageIdx >= 0 && root.pages[hit.pageIdx]
                                                    ? root.pages[hit.pageIdx].icon : "settings")
                                            iconSize: 17
                                            color: hit.external ? Appearance.colors.colPrimary
                                                                : Appearance.colors.colSubtext
                                        }
                                        ColumnLayout {
                                            Layout.fillWidth: true
                                            spacing: -2
                                            StyledText {
                                                Layout.fillWidth: true
                                                text: hit.modelData.title
                                                font.pixelSize: Appearance.font.pixelSize.smaller
                                                color: Appearance.colors.colOnLayer1
                                                elide: Text.ElideRight
                                            }
                                            StyledText {
                                                Layout.fillWidth: true
                                                text: (hit.modelData.file === "@effect" ? "Effect"
                                                        : hit.modelData.file === "@shader" ? "Shader"
                                                        : hit.modelData.file === "@action" ? "Run"
                                                        : hit.modelData.file === "@keybind" ? "Key"
                                                        : (hit.pageIdx >= 0 && root.pages[hit.pageIdx]
                                                            ? root.pages[hit.pageIdx].name : "?"))
                                                    + (hit.modelData.section ? "  ›  " + hit.modelData.section : "")
                                                font.pixelSize: Appearance.font.pixelSize.smallest
                                                color: Appearance.colors.colSubtext
                                                elide: Text.ElideRight
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }

            RowLayout { // Window controls row
                id: windowControlsRow
                anchors.verticalCenter: parent.verticalCenter
                anchors.right: parent.right
                RippleButton {
                    buttonRadius: Appearance.rounding.full
                    implicitWidth: 35
                    implicitHeight: 35
                    onClicked: root.close()
                    contentItem: MaterialSymbol {
                        anchors.centerIn: parent
                        horizontalAlignment: Text.AlignHCenter
                        text: "close"
                        iconSize: 20
                    }
                }
            }
        }

        RowLayout { // Window content with navigation rail and content pane
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: contentPadding
            Item {
                id: navRailWrapper
                Layout.fillHeight: true
                Layout.margins: 5
                implicitWidth: navRail.expanded ? 150 : fab.baseSize
                Behavior on implicitWidth {
                    animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                }
                NavigationRail { // Window content with navigation rail and content pane
                    id: navRail
                    anchors {
                        left: parent.left
                        top: parent.top
                        bottom: parent.bottom
                    }
                    spacing: 10
                    expanded: root.width > 900
                    
                    NavigationRailExpandButton {
                        focus: root.visible
                    }

                    FloatingActionButton {
                        id: fab
                        property bool justCopied: false
                        iconText: justCopied ? "check" : "edit"
                        buttonText: justCopied ? Translation.tr("Path copied") : Translation.tr("Config file")
                        expanded: navRail.expanded
                        downAction: () => {
                            Qt.openUrlExternally(`${Directories.config}/illogical-impulse/config.json`);
                        }
                        altAction: () => {
                            Quickshell.clipboardText = CF.FileUtils.trimFileProtocol(`${Directories.config}/illogical-impulse/config.json`);
                            fab.justCopied = true;
                            revertTextTimer.restart()
                        }

                        Timer {
                            id: revertTextTimer
                            interval: 1500
                            onTriggered: {
                                fab.justCopied = false;
                            }
                        }

                        StyledToolTip {
                            text: Translation.tr("Open the shell config file\nAlternatively right-click to copy path")
                        }
                    }

                    // Scrollable, because the rail can be taller than the
                    // window: eleven pages at 56px plus four group headings
                    // comes to about 840px, and the content area of a
                    // default-sized window is around 690. It used to fit, and
                    // then it quietly did not — the last entries simply had
                    // nowhere to draw and the window has a 500px minimum.
                    // Wrapped, so the edge fades can sit OVER the list rather
                    // than in the column with it.
                    Item {
                        Layout.fillHeight: true
                        Layout.fillWidth: true
                        implicitWidth: railTabs.implicitWidth

                        StyledFlickable {
                            id: railFlick
                            anchors.fill: parent
                            contentHeight: railTabs.implicitHeight
                            contentWidth: width
                            // Only actually scrolls when it has to.
                            interactive: contentHeight > height
                            clip: true

                            NavigationRailTabArray {
                                id: railTabs
                                width: parent.width
                                currentIndex: root.currentPage
                                expanded: navRail.expanded
                                Repeater {
                                    model: root.pages
                                    NavigationRailButton {
                                        required property var index
                                        required property var modelData
                                        toggled: root.currentPage === index
                                        onPressed: root.currentPage = index;
                                        expanded: navRail.expanded
                                        buttonIcon: modelData.icon
                                        buttonIconRotation: modelData.iconRotation || 0
                                        buttonText: modelData.name
                                        groupLabel: modelData.group ?? ""
                                        showToggledHighlight: false
                                    }
                                }
                            }
                        }

                        // The scroll hint.
                        //
                        // The first attempt was a gradient band across the full
                        // width, fading into the window background. It read as
                        // a black footer bar: the band's square bottom edge met
                        // the window's rounded corner, and a filled rectangle
                        // over a list does not look like an edge however it is
                        // shaded. A floating pill has no edges to disagree with
                        // anything behind it.
                        Rectangle {
                            id: scrollHint
                            anchors.horizontalCenter: parent.horizontalCenter
                            anchors.bottom: parent.bottom
                            anchors.bottomMargin: 6
                            implicitWidth: 30
                            implicitHeight: 22
                            radius: Appearance.rounding.full
                            color: hintArea.containsMouse
                                ? Appearance.colors.colLayer1Hover
                                : Appearance.colors.colLayer1
                            border.width: 1
                            border.color: Appearance.colors.colLayer0Border

                            // More below than the couple of pixels of rounding
                            // error a Flickable sits at when it is exactly full.
                            readonly property bool more:
                                railFlick.contentHeight - railFlick.contentY - railFlick.height > 2
                            visible: opacity > 0
                            opacity: scrollHint.more ? 1 : 0
                            Behavior on opacity { NumberAnimation { duration: 150 } }
                            Behavior on color { ColorAnimation { duration: 140 } }

                            MaterialSymbol {
                                anchors.fill: parent
                                horizontalAlignment: Text.AlignHCenter
                                verticalAlignment: Text.AlignVCenter
                                text: "keyboard_arrow_down"
                                iconSize: 16
                                color: Appearance.colors.colOnLayer1
                            }

                            // The hint is also the control. Pointing at
                            // something and not letting anyone act on it is
                            // worse than not pointing.
                            MouseArea {
                                id: hintArea
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: scrollAnim.restart()
                            }
                            NumberAnimation {
                                id: scrollAnim
                                target: railFlick
                                property: "contentY"
                                to: Math.min(railFlick.contentY + railFlick.height * 0.8,
                                             Math.max(0, railFlick.contentHeight - railFlick.height))
                                duration: Appearance.animationCurves.expressiveFastSpatialDuration
                                easing.type: Easing.BezierSpline
                                easing.bezierCurve: Appearance.animationCurves.expressiveFastSpatial
                            }
                        }
                    }
                }
            }
            Rectangle { // Content container
                Layout.fillWidth: true
                Layout.fillHeight: true
                color: Appearance.m3colors.m3surfaceContainerLow
                radius: Appearance.rounding.windowRounding - root.contentPadding

                Rectangle {
                    id: revealFlash
                    z: 400
                    visible: opacity > 0.01
                    opacity: 0
                    radius: Appearance.rounding.small
                    color: Appearance.colors.colPrimary
                    SequentialAnimation {
                        id: flashAnim
                        NumberAnimation { target: revealFlash; property: "opacity"; to: 0.28; duration: 160 }
                        PauseAnimation { duration: 420 }
                        NumberAnimation { target: revealFlash; property: "opacity"; to: 0; duration: 520 }
                    }
                }

                Loader {
                    id: pageLoader
                    anchors.fill: parent
                    opacity: 1.0

                    onLoaded: if (root.pendingReveal.length > 0) revealTimer.restart()

                    active: Config.ready
                    Component.onCompleted: {
                        source = root.pages[0].component
                    }

                    Connections {
                        target: root
                        function onCurrentPageChanged() {
                            switchAnim.complete();
                            switchAnim.start();
                        }
                    }

                    SequentialAnimation {
                        id: switchAnim

                        NumberAnimation {
                            target: pageLoader
                            properties: "opacity"
                            from: 1
                            to: 0
                            duration: 100
                            easing.type: Appearance.animation.elementMoveExit.type
                            easing.bezierCurve: Appearance.animationCurves.emphasizedFirstHalf
                        }
                        ParallelAnimation {
                            PropertyAction {
                                target: pageLoader
                                property: "source"
                                value: root.pages[root.currentPage].component
                            }
                            PropertyAction {
                                target: pageLoader
                                property: "anchors.topMargin"
                                value: 20
                            }
                        }
                        ParallelAnimation {
                            NumberAnimation {
                                target: pageLoader
                                properties: "opacity"
                                from: 0
                                to: 1
                                duration: 200
                                easing.type: Appearance.animation.elementMoveEnter.type
                                easing.bezierCurve: Appearance.animationCurves.emphasizedLastHalf
                            }
                            NumberAnimation {
                                target: pageLoader
                                properties: "anchors.topMargin"
                                to: 0
                                duration: 200
                                easing.type: Appearance.animation.elementMoveEnter.type
                                easing.bezierCurve: Appearance.animationCurves.emphasizedLastHalf
                            }
                        }
                    }
                }
            }
        }
    }
}
