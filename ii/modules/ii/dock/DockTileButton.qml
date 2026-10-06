// A widget drawn as a dock tile: DockButton chrome around a 35px square.
// Split out of DockWidget when inline widgets (apps, media) arrived — they
// are not tiles and must not be forced into one.
import qs.services
import qs.modules.common
import QtQuick
import Quickshell

DockButton {
    id: root
    required property string widgetId
    required property url widgetUrl
    /// Matches DockAppButton.iconSize so tiles sit in the icon row.
    property real tileSize: 35

    topInset: Appearance.sizes.hyprlandGapsOut + (Config.options?.dock.buttonPadding ?? 5)
    bottomInset: Appearance.sizes.hyprlandGapsOut + (Config.options?.dock.buttonPadding ?? 5)
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
            source: root.widgetUrl
        }
    }
}
