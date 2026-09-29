// Registry of the dock's widgets: which exist, which are on, and each one's
// own settings.
//
// A widget declares its settings as schema here, so the edit panel renders
// controls for it without knowing anything about the widget. Adding one is a
// file in dock/widgets/ plus an entry below.
pragma Singleton

import qs.modules.common
import QtQuick
import Quickshell

Singleton {
    id: root

    /// The app behind a widget, or "" if it has none yet.
    function appFor(id) {
        const e = (root.catalog ?? []).find(w => w.id === id);
        return e?.app ?? "";
    }
    function appNameFor(id) {
        const e = (root.catalog ?? []).find(w => w.id === id);
        return e?.appName ?? "";
    }

    readonly property var catalog: [
        {
            id: "clock", name: Translation.tr("Clock"), icon: "schedule",
            app: "/mnt/storage/dev/projects/desktop/timos/timos.qml", appName: "Timos", w: Appearance.sizes.dockWidgetWindow.widthNarrow, h: Appearance.sizes.dockWidgetWindow.heightTall,
            settings: [
                { key: "stacked", label: Translation.tr("Stack hours over minutes"), type: "bool", def: true },
                { key: "twelveHour", label: Translation.tr("12-hour clock"), type: "bool", def: false },
                { key: "seconds", label: Translation.tr("Show seconds"), type: "bool", def: false },
                { key: "showDate", label: Translation.tr("Show date instead of minutes"), type: "bool", def: false }
            ]
        },
        {
            id: "battery", name: Translation.tr("Battery"), icon: "battery_full", w: Appearance.sizes.dockWidgetWindow.widthNarrow, h: Appearance.sizes.dockWidgetWindow.heightNormal,
            settings: [
                { key: "showPercent", label: Translation.tr("Show percentage"), type: "bool", def: true }
            ]
        },
        {
            id: "volume", name: Translation.tr("Volume"), icon: "volume_up", w: Appearance.sizes.dockWidgetWindow.widthNormal, h: Appearance.sizes.dockWidgetWindow.heightShort,
            settings: [
                { key: "step", label: Translation.tr("Scroll step (%)"), type: "int", def: 2, min: 1, max: 20 }
            ]
        },
        {
            id: "places", name: Translation.tr("Folders"), icon: "folder_open", w: Appearance.sizes.dockWidgetWindow.widthWide, h: Appearance.sizes.dockWidgetWindow.heightTall,
            settings: [
                { key: "columns", label: Translation.tr("Columns"), type: "int", def: 3, min: 2, max: 5 }
            ]
        },
        {
            id: "resources", name: Translation.tr("CPU / RAM"), icon: "memory", w: Appearance.sizes.dockWidgetWindow.widthNormal, h: Appearance.sizes.dockWidgetWindow.heightNormal,
            settings: [
                { key: "showSwap", label: Translation.tr("Show swap bar"), type: "bool", def: false }
            ]
        }
    ]

    readonly property WidgetRegistry registry: WidgetRegistry {
        catalog: root.catalog
        enabledJson: Config.options.dock.widgets
        writeEnabled: (v) => Config.options.dock.widgets = v
        settingsJson: Config.options.dock.widgetSettings
        writeSettings: (v) => Config.options.dock.widgetSettings = v
    }

    // Same surface as before, so no call site changes.
    readonly property var enabled: root.registry.enabled
    function entry(id) { return root.registry.entry(id) }
    function isEnabled(id) { return root.registry.isEnabled(id) }
    function toggle(id) { root.registry.toggle(id) }
    function move(id, delta) { root.registry.move(id, delta) }
    function schema(id, key) { return root.registry.schema(id, key) }
    function get(id, key) { return root.registry.get(id, key) }
    function set(id, key, value) { root.registry.set(id, key, value) }
}
