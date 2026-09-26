// Which dock widget has its panel open. One panel for the whole dock, like
// DockTooltip — the dock surface is too short to host anything itself.
pragma Singleton

import QtQuick
import Quickshell

Singleton {
    id: root
    property Item target: null
    property string widgetId: ""
    property bool showSettings: false

    function toggle(item, id) {
        if (root.target === item && root.widgetId === id) { root.close(); return; }
        root.target = item;
        root.widgetId = id;
        root.showSettings = false;
    }
    function close() {
        root.target = null;
        root.widgetId = "";
        root.showSettings = false;
    }
}
