// One dock widget: DockButton chrome around a widget from DockWidgets.catalog.
//
// The widget itself is loaded by id from widgets/, so adding one is a new file
// plus a catalog entry — nothing here changes.
import qs.services
import qs.modules.common
import QtQuick
import Quickshell

DockButton {
    id: root
    required property string widgetId
    /// Matches DockAppButton.iconSize so tiles sit in the icon row.
    property real tileSize: 35

    topInset: Appearance.sizes.hyprlandGapsOut + dockRow.padding
    bottomInset: Appearance.sizes.hyprlandGapsOut + dockRow.padding
    // Same footprint as an app button (50 wide around a 35px icon).
    implicitWidth: 50

    // A Button stretches its contentItem to the content box, which pulled the
    // tiles into tall rectangles — so the Loader is a fixed square inside it.
    // Click opens the app behind this widget; the panel is the fallback for
    // widgets that do not have one yet, and right-click reaches it regardless.
    // The panel is still the quick glance — it needs no window — but a widget
    // whose app you have to hunt for at the bottom of a popup is one you never
    // open.
    readonly property string appPath: DockWidgets.appFor(root.widgetId)

    onClicked: {
        if (root.appPath.length > 0) {
            // execDetached so the app outlives the dock that launched it.
            Quickshell.execDetached(["qs", "-p", root.appPath]);
            DockWidgetPanel.close();
            return;
        }
        DockWidgetPanel.toggle(root, root.widgetId);
    }
    altAction: () => DockWidgetPanel.toggle(root, root.widgetId)

    contentItem: Item {
        Loader {
            anchors.centerIn: parent
            width: root.tileSize
            height: root.tileSize
            source: root.widgetId.length > 0
                ? Qt.resolvedUrl(`widgets/${root.widgetId.charAt(0).toUpperCase()}${root.widgetId.slice(1)}Widget.qml`)
                : ""
        }
    }
}
