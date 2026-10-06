// The bar's widget catalog. Mechanism is WidgetRegistry, shared with the dock;
// adding a widget is a file in bar/widgets/ plus an entry below.
pragma Singleton

import qs.modules.common
import QtQuick
import Quickshell

Singleton {
    id: root

    readonly property var catalog: [
        {
            id: "uptime", name: Translation.tr("Uptime"), icon: "timer",
            settings: [
                { key: "compact", label: Translation.tr("Compact (1d 4h)"), type: "bool", def: true }
            ]
        },
        {
            id: "loadavg", name: Translation.tr("Load average"), icon: "monitoring",
            settings: [
                // SysStats keeps only the 1- and 5-minute figures.
                { key: "fiveMinute", label: Translation.tr("Use the 5-minute average"), type: "bool", def: false }
            ]
        },
        {
            id: "battery", name: Translation.tr("Battery"), icon: "battery_full",
            settings: [
                { key: "showPercent", label: Translation.tr("Show percentage"), type: "bool", def: true }
            ]
        },
        {
            id: "resources", name: Translation.tr("CPU / RAM"), icon: "memory",
            settings: [
                { key: "showMemory", label: Translation.tr("Show memory beside CPU"), type: "bool", def: true }
            ]
        }
    ]

    readonly property WidgetRegistry registry: WidgetRegistry {
        catalog: root.catalog
        enabledJson: Config.options.bar.widgets
        writeEnabled: (v) => Config.options.bar.widgets = v
        settingsJson: Config.options.bar.widgetSettings
        writeSettings: (v) => Config.options.bar.widgetSettings = v
    }

    // Mirrors DockWidgets' surface, so call sites read the same.
    readonly property var enabled: root.registry.enabled
    function entry(id) { return root.registry.entry(id) }
    function isEnabled(id) { return root.registry.isEnabled(id) }
    function toggle(id) { root.registry.toggle(id) }
    function move(id, delta) { root.registry.move(id, delta) }
    function moveTo(id, index) { root.registry.moveTo(id, index) }
    function add(id) { root.registry.add(id) }
    function remove(id) { root.registry.remove(id) }
    function beginEdit() { root.registry.beginEdit() }
    function endEdit() { root.registry.endEdit() }
    function undo() { root.registry.undo() }
    readonly property bool canUndo: root.registry.canUndo
    function schema(id, key) { return root.registry.schema(id, key) }
    function get(id, key) { return root.registry.get(id, key) }
    function set(id, key, value) { root.registry.set(id, key, value) }
}
