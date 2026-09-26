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

    function entry(id) { return root.catalog.find(w => w.id === id) ?? null }

    // ── Which are on ─────────────────────────────────────────────────────
    readonly property var enabled: {
        Config.options.dock.widgets;
        let ids = [];
        try { ids = JSON.parse(Config.options.dock.widgets || "[]") ?? []; }
        catch (e) { ids = []; }
        return ids.filter(id => root.entry(id) !== null);
    }

    function isEnabled(id) { return root.enabled.indexOf(id) >= 0 }

    function toggle(id) {
        const next = root.isEnabled(id)
            ? root.enabled.filter(w => w !== id)
            : root.enabled.concat([id]);
        Config.options.dock.widgets = JSON.stringify(next);
    }

    function move(id, delta) {
        const list = root.enabled.slice();
        const i = list.indexOf(id);
        const j = i + delta;
        if (i < 0 || j < 0 || j >= list.length) return;
        list[i] = list[j];
        list[j] = id;
        Config.options.dock.widgets = JSON.stringify(list);
    }

    // ── Per-widget settings ──────────────────────────────────────────────
    readonly property var overrides: {
        Config.options.dock.widgetSettings;
        try { return JSON.parse(Config.options.dock.widgetSettings || "{}") ?? ({}); }
        catch (e) { return ({}); }
    }

    function schema(id, key) {
        return (root.entry(id)?.settings ?? []).find(s => s.key === key) ?? null;
    }

    /// Reads through to the schema default, so a widget never sees undefined.
    function get(id, key) {
        const v = root.overrides?.[id]?.[key];
        return v === undefined ? root.schema(id, key)?.def : v;
    }

    function set(id, key, value) {
        const all = Object.assign({}, root.overrides);
        all[id] = Object.assign({}, all[id] ?? {});
        all[id][key] = value;
        Config.options.dock.widgetSettings = JSON.stringify(all);
    }
}
