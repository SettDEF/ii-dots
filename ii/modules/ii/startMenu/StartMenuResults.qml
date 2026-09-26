// StartMenuResults — live search results. Reuses SearchItem exactly as the
// overview launcher renders it (modules/ii/overview/SearchItem.qml) over
// services/LauncherSearch.qml's `results` list — no new matching logic here.
pragma ComponentBehavior: Bound
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.overview
import QtQuick
import Quickshell

Item {
    id: root
    required property string query

    function focusFirst() {
        if (resultsList.count === 0) return
        resultsList.currentIndex = 0
        resultsList.itemAtIndex(0)?.forceActiveFocus()
    }

    StyledListView {
        id: resultsList
        anchors.fill: parent
        clip: true
        spacing: 2

        model: ScriptModel {
            objectProp: "key"
            // Capped: a Start Menu popup is not the place to render an
            // unbounded results list, and 30 is already more than fits.
            values: LauncherSearch.results.slice(0, 30)
        }

        delegate: SearchItem {
            id: item
            required property var modelData
            anchors.left: parent?.left
            anchors.right: parent?.right
            entry: modelData
            query: root.query
        }
    }

    StyledText {
        anchors.centerIn: parent
        visible: resultsList.count === 0
        text: Translation.tr("No results")
        color: Appearance.colors.colSubtext
        font.pixelSize: Appearance.font.pixelSize.small
    }
}
