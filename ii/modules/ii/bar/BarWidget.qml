// One bar widget from BarWidgets.catalog, loaded by id. Thin on purpose: a bar
// widget is a readout in the bar's row, not a button like the dock's tiles.
import qs.modules.common
import QtQuick
import QtQuick.Layouts

Loader {
    id: root
    required property string widgetId

    // A widget with nothing to show hides itself (zeit with no job…), but the
    // Loader kept its width: an empty gap in the bar. `shown` folds that in;
    // it reads the item's own `visible`, which the Loader never overrides as
    // it stays visible itself (hiding it would hide the item and loop).
    readonly property bool shown: status === Loader.Ready && (root.item?.visible ?? false)
    Layout.alignment: Qt.AlignVCenter
    // A widget with `minimumWidth` gives up width when the bar is full, down
    // to that, instead of pushing the row over the clock. Others stay fixed.
    readonly property bool shrinks: root.shown && (root.item?.minimumWidth ?? -1) >= 0
    Layout.fillWidth: root.shrinks
    Layout.minimumWidth: root.shrinks ? root.item.minimumWidth : (root.shown ? -1 : 0)
    Layout.preferredWidth: root.shown ? root.implicitWidth : 0
    Layout.maximumWidth: root.shrinks ? root.implicitWidth : (root.shown ? -1 : 0)
    Layout.preferredHeight: root.shown ? root.implicitHeight : 0

    // setSource, not a `source` binding: a required property must be set at
    // construction, and only setSource takes initial properties.
    // ?r=: the type loader caches a component by URL across config reloads, so a
    // widget loaded by URL kept its old code after an edit; a fresh URL per
    // instance (instances are rebuilt on every reload) makes a save show up.
    readonly property double _born: Date.now()
    readonly property url widgetUrl: root.widgetId.length > 0
        ? Qt.resolvedUrl(`widgets/${root.widgetId.charAt(0).toUpperCase()}${root.widgetId.slice(1)}Widget.qml?r=${root._born}`)
        : ""

    onWidgetUrlChanged: root.load()
    Component.onCompleted: root.load()

    function load() {
        if (root.widgetUrl.toString().length === 0) {
            root.setSource("");
            return;
        }
        root.setSource(root.widgetUrl, { widgetId: root.widgetId });
    }

    // Reports widgetUrl, not `source` — the latter is empty on error.
    onStatusChanged: if (status === Loader.Error)
        console.warn(`[BarWidget] widget "${root.widgetId}" failed to load from ${root.widgetUrl}`);
}
