// One bar widget: the widget from BarWidgets.catalog, loaded by id.
//
// Deliberately thin. The dock's DockWidget carries click-to-launch and a popup
// panel because a dock tile is a button; a bar widget is a readout sitting in
// the bar's own row, so it inherits that row's spacing and grouping and adds
// nothing of its own. Adding a widget is a file in widgets/ plus a catalog
// entry — this file never changes.
import qs.modules.common
import QtQuick
// Layout.alignment below is an attached property from here, not QtQuick.
import QtQuick.Layouts

Loader {
    id: root
    required property string widgetId

    visible: status === Loader.Ready
    Layout.alignment: Qt.AlignVCenter

    /*
     * setSource(), not a `source` binding.
     *
     * The widgets declare `required property string widgetId`, and a required
     * property has to be supplied when the object is CONSTRUCTED — a binding
     * on `source` builds it with nothing, so Qt refuses it with "Required
     * property widgetId was not initialized" and the Loader lands in Error
     * with an empty source. setSource takes initial properties, which is the
     * only way to hand a required property to a Loader.
     */
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

    // Reports the file it looked for, not `source` — on an error that is empty,
    // which is what made the first version of this message useless.
    onStatusChanged: if (status === Loader.Error)
        console.warn(`[BarWidget] widget "${root.widgetId}" failed to load from ${root.widgetUrl}`);
}
