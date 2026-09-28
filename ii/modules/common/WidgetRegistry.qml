// Which widgets exist, which are on, in what order, and their settings — the
// half of a widget system the bar and the dock share.
//
// Config keys come in as a value plus a setter, not a path: a property alias
// cannot be built from a string at runtime.
import QtQuick

QtObject {
    id: reg

    /// [{ id, name, icon, settings: [{ key, label, type, def, ... }] }, …]
    property var catalog: []

    /// The JSON array of enabled ids, and how to write it back.
    property string enabledJson: "[]"
    property var writeEnabled: null      // function(jsonString)
    /// The JSON object of per-widget overrides, and how to write it back.
    property string settingsJson: "{}"
    property var writeSettings: null     // function(jsonString)

    function entry(id) {
        return (reg.catalog ?? []).find(w => w.id === id) ?? null;
    }

    // ── Which are on ─────────────────────────────────────────────────────
    // Unknown ids are dropped: a removed catalog entry would throw every frame.
    readonly property var enabled: {
        let ids = [];
        try { ids = JSON.parse(reg.enabledJson || "[]") ?? []; }
        catch (e) { ids = []; }
        return ids.filter(id => reg.entry(id) !== null);
    }

    function isEnabled(id) { return reg.enabled.indexOf(id) >= 0; }

    function toggle(id) {
        if (!reg.writeEnabled) return;
        const next = reg.isEnabled(id)
            ? reg.enabled.filter(w => w !== id)
            : reg.enabled.concat([id]);
        reg.writeEnabled(JSON.stringify(next));
    }

    function move(id, delta) {
        if (!reg.writeEnabled) return;
        const list = reg.enabled.slice();
        const i = list.indexOf(id);
        const j = i + delta;
        if (i < 0 || j < 0 || j >= list.length) return;
        list[i] = list[j];
        list[j] = id;
        reg.writeEnabled(JSON.stringify(list));
    }

    // ── Per-widget settings ──────────────────────────────────────────────
    readonly property var overrides: {
        try { return JSON.parse(reg.settingsJson || "{}") ?? ({}); }
        catch (e) { return ({}); }
    }

    function schema(id, key) {
        return (reg.entry(id)?.settings ?? []).find(s => s.key === key) ?? null;
    }

    /// Reads through to the schema default, so a widget never sees undefined.
    function get(id, key) {
        const v = reg.overrides?.[id]?.[key];
        return v === undefined ? reg.schema(id, key)?.def : v;
    }

    function set(id, key, value) {
        if (!reg.writeSettings) return;
        const all = Object.assign({}, reg.overrides);
        all[id] = Object.assign({}, all[id] ?? {});
        all[id][key] = value;
        reg.writeSettings(JSON.stringify(all));
    }
}
