// Registry of the bar's widgets: which exist, which are on, and each one's
// own settings.
//
// The mechanism is WidgetRegistry, shared with the dock; this file is only the
// catalog and the two config keys. Adding a widget is a file in bar/widgets/
// plus an entry below — nothing else changes.
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
                // SysStats reads /proc/loadavg but only keeps the 1- and
                // 5-minute figures, so this is a choice between those two
                // rather than the usual three.
                { key: "fiveMinute", label: Translation.tr("Use the 5-minute average"), type: "bool", def: false }
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

    // The surface of DockWidgets, so the two read the same at every call site.
    readonly property var enabled: root.registry.enabled
    function entry(id) { return root.registry.entry(id) }
    function isEnabled(id) { return root.registry.isEnabled(id) }
    function toggle(id) { root.registry.toggle(id) }
    function move(id, delta) { root.registry.move(id, delta) }
    function schema(id, key) { return root.registry.schema(id, key) }
    function get(id, key) { return root.registry.get(id, key) }
    function set(id, key, value) { root.registry.set(id, key, value) }
}
