// One bar widget from BarWidgets.catalog, loaded by id. Thin on purpose: a bar
// widget is a readout in the bar's row, not a button like the dock's tiles.
import qs.modules.common
import QtQuick
import QtQuick.Layouts

Loader {
    id: root
    required property string widgetId

    visible: status === Loader.Ready
    Layout.alignment: Qt.AlignVCenter

    // setSource, not a `source` binding: a required property must be set at
    // construction, and only setSource takes initial properties.
    readonly property url widgetUrl: root.widgetId.length > 0
        ? Qt.resolvedUrl(`widgets/${root.widgetId.charAt(0).toUpperCase()}${root.widgetId.slice(1)}Widget.qml`)
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
