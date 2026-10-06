// One dock widget, by id. Dispatches on kind: a tile gets DockButton chrome
// around a 35px square, an inline widget is the content itself and sizes
// itself. Apps and media were hardcoded siblings of the widget row only
// because this host could draw nothing but a tile.
import qs.services
import qs.modules.common
import QtQuick

Loader {
    id: root
    required property string widgetId

    readonly property string kind: DockWidgets.kindOf(root.widgetId)
    readonly property url widgetUrl: root.widgetId.length > 0
        ? Qt.resolvedUrl(`widgets/${root.widgetId.charAt(0).toUpperCase()}${root.widgetId.slice(1)}Widget.qml`)
        : ""

    sourceComponent: root.kind === "inline" ? inlineComp : tileComp

    Component {
        id: inlineComp
        Loader { source: root.widgetUrl }
    }
    Component {
        id: tileComp
        DockTileButton {
            widgetId: root.widgetId
            widgetUrl: root.widgetUrl
        }
    }
}
