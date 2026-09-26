// StartMenuContent — search field on top, then either the home page
// (pinned/frequent/all apps + power row) or live search results underneath,
// depending on whether there's a query. All search state and matching comes
// from services/LauncherSearch.qml; nothing here re-implements it.
pragma ComponentBehavior: Bound
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts

ColumnLayout {
    id: root
    spacing: 10

    readonly property bool searching: LauncherSearch.query.length > 0

    RowLayout {
        Layout.fillWidth: true
        spacing: 8

        MaterialSymbol {
            text: "search"
            iconSize: Appearance.font.pixelSize.larger
            color: Appearance.colors.colSubtext
        }

        ToolbarTextField {
            id: searchInput
            Layout.fillWidth: true
            implicitHeight: 40
            font.pixelSize: Appearance.font.pixelSize.small
            placeholderText: Translation.tr("Search apps, settings, files…")
            // Bound the same way Overview's SearchBar binds its focus to
            // GlobalStates.overviewOpen (modules/ii/overview/SearchBar.qml:180)
            focus: GlobalStates.startMenuOpen
            // One-directional (typing → LauncherSearch.query) on purpose: a
            // two-way `text: LauncherSearch.query` binding would be torn out
            // by this very handler the first time it fires (assigning to a
            // property clears its declarative binding), so a later reset of
            // LauncherSearch.query from outside would stop reaching the
            // field. Reset instead goes through the Connections below.
            onTextChanged: LauncherSearch.query = text

            Connections {
                target: GlobalStates
                function onStartMenuOpenChanged() {
                    if (GlobalStates.startMenuOpen)
                        searchInput.text = ""
                }
            }

            onAccepted: {
                const first = LauncherSearch.results?.[0]
                if (first) {
                    GlobalStates.startMenuOpen = false
                    first.execute()
                }
            }

            Keys.onDownPressed: resultsLoader.item?.focusFirst?.()
        }

        RippleButton {
            visible: root.searching
            implicitWidth: 32
            implicitHeight: 32
            buttonRadius: Appearance.rounding.full
            onClicked: LauncherSearch.query = ""
            contentItem: MaterialSymbol {
                anchors.centerIn: parent
                text: "close"
                iconSize: Appearance.font.pixelSize.large
                color: Appearance.colors.colOnLayer1
            }
        }
    }

    Loader {
        id: resultsLoader
        Layout.fillWidth: true
        Layout.fillHeight: true
        sourceComponent: root.searching ? resultsComp : homeComp
    }

    Component {
        id: homeComp
        StartMenuHome {}
    }
    Component {
        id: resultsComp
        StartMenuResults {
            query: LauncherSearch.query
        }
    }
}
