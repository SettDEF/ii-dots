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

    /// A widget asking the dock to stay visible — a hovered app preview, a
    /// playing track. Used to reach Dock.qml through the ids of the two
    /// hardcoded children; they are behind loaders now, so it goes through
    /// here. One flag per source rather than a counter, because a counter
    /// drifts the moment a widget is reloaded mid-hover.
    property bool appsRequestShow: false
    property bool mediaRequestShow: false
    readonly property bool anyRequestShow: root.appsRequestShow || root.mediaRequestShow

    /// "tile" is a 35px square in a 50px button; "inline" sizes itself and
    /// gets no button chrome. Apps and media were hardcoded siblings of the
    /// widget row purely because the host only knew how to draw a tile.
    function kindOf(id) {
        const e = (root.catalog ?? []).find(w => w.id === id);
        return e?.kind ?? "tile";
    }

    readonly property var catalog: [
        {
            id: "apps", name: Translation.tr("Applications"), icon: "apps",
            kind: "inline", noPanel: true,
            // Was Layout.topMargin on DockApps itself, with a "why does this
            // work" beside it. It works because the row is anchored to the
            // window top and the gap has to come off somewhere.
            topMargin: Appearance.sizes.hyprlandGapsOut
        },
        {
            id: "media", name: Translation.tr("Now playing"), icon: "music_note",
            kind: "inline", noPanel: true, topMargin: 12, bottomMargin: 8
        },
        {
            id: "clock", name: Translation.tr("Clock"), icon: "schedule",
            app: Paths.projects + "/desktop/timos/timos.qml", appName: "Timos", w: Appearance.sizes.dockWidgetWindow.widthNarrow, h: Appearance.sizes.dockWidgetWindow.heightTall,
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
            id: "resources", name: Translation.tr("CPU / RAM"), icon: "memory",
            // installed by vitals/install.sh: a copy, so editing the project never reloads an open window
            app: Quickshell.env("HOME") + "/.local/share/vitals/gui/vitals.qml", appName: "Vitals", w: Appearance.sizes.dockWidgetWindow.widthNormal, h: Appearance.sizes.dockWidgetWindow.heightNormal,
            settings: [
                { key: "showSwap", label: Translation.tr("Show swap bar"), type: "bool", def: false },
                { key: "showTemp", label: Translation.tr("Show CPU temperature bar (from Vitals)"), type: "bool", def: true }
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
