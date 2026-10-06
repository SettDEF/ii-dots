// One dock widget, by id, and the RowLayout child that holds it.
//
// Inline widgets (apps, media) were written as direct children of the row:
// they declare Layout.fillHeight on themselves and read parent.height. Neither
// survives being loaded, so this host carries the layout role for them and the
// catalog says what margins each wants.
import qs
import qs.services
import qs.modules.common
import QtQuick
import QtQuick.Layouts

Item {
    id: root
    required property string widgetId

    readonly property var entry: DockWidgets.entry(root.widgetId)
    readonly property string kind: DockWidgets.kindOf(root.widgetId)
    readonly property bool inline: root.kind === "inline"
    readonly property url widgetUrl: root.widgetId.length > 0
        ? Qt.resolvedUrl(`widgets/${root.widgetId.charAt(0).toUpperCase()}${root.widgetId.slice(1)}Widget.qml`)
        : ""

    /// Edit mode: a widget with nothing to show (media with no track, apps with
    /// no windows) would vanish and could not be moved or removed, so it holds
    /// a placeholder slot while editing.
    readonly property bool editing: GlobalStates.dockEditMode
    /// Set by WidgetEditChrome while this widget is being dragged.
    property real dragOffset: 0
    transform: Translate { x: root.dragOffset }
    z: chrome.item?.dragging ? 10 : 0

    Layout.fillHeight: root.inline
    Layout.topMargin: root.entry?.topMargin ?? 0
    Layout.bottomMargin: root.entry?.bottomMargin ?? 0

    // From the loaded item, so a widget that collapses to nothing (media with
    // no track) takes no width in the row.
    implicitWidth: root.editing && root.inline ? Math.max(72, ldr.item?.implicitWidth ?? 0)
                                               : (ldr.item?.implicitWidth ?? 0)
    implicitHeight: root.inline ? (ldr.item?.implicitHeight ?? 0)
                                : (ldr.item?.implicitHeight ?? 0)
    // Never from the item's own `visible`: that is EFFECTIVE visibility, which
    // includes this host, so a host that starts hidden (nothing loaded yet)
    // keeps its item hidden and itself hidden for good. Width stands in for
    // "has nothing to show" instead.
    visible: ldr.item !== null && (root.editing || !root.inline || root.implicitWidth > 0)

    Loader {
        id: ldr
        anchors.fill: parent

        // setSource, not a source binding: DockTileButton has required
        // properties, and only setSource can supply them at construction.
        function reload() {
            if (root.widgetUrl.toString().length === 0) { ldr.setSource(""); return }
            if (root.inline) ldr.setSource(root.widgetUrl, {});
            else ldr.setSource(Qt.resolvedUrl("DockTileButton.qml"), {
                widgetId: root.widgetId,
                widgetUrl: root.widgetUrl
            });
        }
        Component.onCompleted: ldr.reload()
    }
    // Edit chrome, from the shared widgets. Loaded by path with its properties,
    // because it has required ones and only setSource can supply them.
    Loader {
        id: chrome
        anchors.fill: parent
        z: 5
        function sync() {
            if (!root.editing) { chrome.setSource(""); return }
            chrome.setSource(Qt.resolvedUrl("../../common/widgets/WidgetEditChrome.qml"), {
                target: root,
                widgetId: root.widgetId,
                registry: DockWidgets
            });
        }
        Component.onCompleted: chrome.sync()
    }
    onEditingChanged: chrome.sync()
    Connections {
        target: chrome.item
        function onConfigure() {
            DockWidgetPanel.close();
            DockWidgetPanel.toggle(root, root.widgetId);
            DockWidgetPanel.showSettings = true;
        }
    }

    onWidgetUrlChanged: ldr.reload()
    onKindChanged: ldr.reload()
}
