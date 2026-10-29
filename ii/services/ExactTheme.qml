pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import qs.modules.common
import qs.modules.common.functions

/**
 * Exact named themes (tinct's Catppuccin …) and the per-colour editor behind the Palette panel.
 *
 * A theme is its own colours exactly, not the wallpaper's: switchwall passes `--theme` when
 * appearance.wallpaperTheming.exactTheme is set. Every variable (palette roles, term0..15) can be
 * changed by hand; the changes live in ~/.config/tinct/overrides/<theme id or "wallpaper">.toml,
 * which tinct applies last, so they survive every wallpaper change and the theme stays resettable.
 */
Singleton {
    id: root

    readonly property string tinct: FileUtils.trimFileProtocol(`${Directories.home}/.local/bin/tinct`)
    readonly property string overridesDir: FileUtils.trimFileProtocol(`${Directories.home}/.config/tinct/overrides`)
    readonly property string generated: FileUtils.trimFileProtocol(`${Directories.state}/user/generated`)

    /// "" = the wallpaper's colours
    readonly property string current: Config.options.appearance.wallpaperTheming.exactTheme ?? ""
    /// what the overrides file and the editor are about
    readonly property string target: current !== "" ? current : "wallpaper"

    /// [{ id, name, dark, colors, swatches: [hex…] }]
    property var themes: []
    /// [{ name, value, source: theme|derived|override|generated, colorName, ansi }]
    property var variables: []
    /// the theme's own colours, offered first when picking a value: [{ name, value }]
    property var ownColors: []
    /// name -> value, as in the overrides file
    property var overrides: ({})
    property bool applying: false

    readonly property string currentName: themes.find(t => t.id === current)?.name ?? ""

    function refresh() {
        listProc.running = true;
        loadVariables();
    }

    /// what the theme leaves out: "theme" (its own manner) or "wallpaper" (switchwall passes --fill-from)
    readonly property string fill: Config.options.appearance.wallpaperTheming.exactFill ?? "theme"
    function setFill(f) {
        if (f === fill) return;
        Config.options.appearance.wallpaperTheming.exactFill = f;
        if (current !== "") apply();
    }

    function select(id) {
        if (id === current) return;
        Config.options.appearance.wallpaperTheming.exactTheme = id;
        apply();
    }

    function setColor(name, value) {
        const o = Object.assign({}, overrides);
        o[name] = value;
        writeOverrides(o);
    }

    /// Two variables trade values (dragging one swatch onto another).
    function swap(a, b) {
        if (a === b) return;
        const va = variables.find(v => v.name === a)?.value;
        const vb = variables.find(v => v.name === b)?.value;
        if (!va || !vb) return;
        const o = Object.assign({}, overrides);
        o[a] = vb;
        o[b] = va;
        writeOverrides(o);
    }

    function reset(name) {
        const o = Object.assign({}, overrides);
        delete o[name];
        writeOverrides(o);
    }

    function resetAll() {
        writeOverrides({});
    }

    /// The editor's groups, in the order a theme is read.
    function groupOf(name) {
        // the 128 shades (red_0 … grey_15): filled by tinct, not edited one by one, so in no group shown
        if (/_\d+$/.test(name)) return "shades";
        if (name.startsWith("term")) return "terminal";
        if (/^(on_)?(primary|secondary|tertiary|error|success)/.test(name) || name === "inverse_primary" || name === "surface_tint") return "accents";
        if (/^on_|outline|^inverse_on/.test(name)) return "text";
        return "surfaces";
    }

    // ── internals ──

    function writeOverrides(o) {
        overrides = o;
        // shown at once; tinct's own answer replaces it after the apply
        variables = variables.map(v => o[v.name] !== undefined
            ? Object.assign({}, v, { value: resolveValue(o[v.name]), source: "override" })
            : v);
        const lines = ["# Palette panel > Edit colours. A hex, or another variable's name."];
        for (const k of Object.keys(o).sort()) lines.push(`${k} = "${o[k]}"`);
        writeProc.command = ["sh", "-c", 'mkdir -p "$(dirname "$1")" && printf "%s\\n" "$2" > "$1"', "sh",
            `${overridesDir}/${target}.toml`, lines.join("\n")];
        writeProc.running = true;
    }

    function resolveValue(v) {
        if (v.startsWith("#")) return v.toLowerCase();
        return variables.find(x => x.name === v)?.value ?? v;
    }

    /// Re-runs the colour pipeline on the current wallpaper (switchwall reads exactTheme itself).
    /// Debounced: a drag or a few clicks are one run.
    function apply() {
        applyTimer.restart();
    }

    function loadVariables() {
        showProc.command = [tinct, "theme", "show", target, "--json"];
        showProc.running = true;
    }

    function ansiName(name) {
        const i = parseInt(name.slice(4));
        const base = ["black", "red", "green", "yellow", "blue", "magenta", "cyan", "white"][i % 8];
        return (i >= 8 ? "bright " : "") + base;
    }

    /// Wallpaper mode: what was generated (colors.json and the SCSS's terminal colours), marked
    /// where the user overrode it.
    function wallpaperVariables(overrideList) {
        const o = {};
        for (const v of overrideList) o[v.name] = v.value;
        overrides = o;
        let roles = {};
        try { roles = JSON.parse(colorsFile.text()); } catch (e) {}
        const vars = Object.keys(roles).sort().map(k => ({ name: k, value: roles[k], source: o[k] !== undefined ? "override" : "generated", colorName: "", ansi: "" }));
        const terms = (scssFile.text().match(/^\$term\d+: #[0-9a-fA-F]+/gm) ?? [])
            .map(l => { const [n, v] = l.slice(1).split(": "); return { name: n, value: v.toLowerCase(), source: o[n] !== undefined ? "override" : "generated", colorName: "", ansi: ansiName(n) }; })
            .sort((a, b) => parseInt(a.name.slice(4)) - parseInt(b.name.slice(4)));
        ownColors = [];
        variables = vars.concat(terms);
    }

    FileView { id: colorsFile; path: `${root.generated}/colors.json`; blockLoading: true }
    FileView { id: scssFile; path: `${root.generated}/material_colors.scss`; blockLoading: true }

    Process {
        id: listProc
        command: [root.tinct, "theme", "list", "--json"]
        stdout: StdioCollector {
            onStreamFinished: {
                try { root.themes = JSON.parse(text); } catch (e) { root.themes = []; }
            }
        }
    }

    Process {
        id: showProc
        stdout: StdioCollector {
            onStreamFinished: {
                let r;
                try { r = JSON.parse(text); } catch (e) { return; }
                if (r.id === "wallpaper") {
                    colorsFile.reload();
                    scssFile.reload();
                    root.wallpaperVariables(r.variables ?? []);
                    return;
                }
                // the file's own spelling (a name or a hex) is kept for writing it back
                root.ownColors = r.colors ?? [];
                root.variables = (r.variables ?? []).map(v => ({ name: v.name, value: v.value, source: v.source, colorName: v.color_name ?? "", ansi: v.ansi ?? "" }));
                overridesFile.reload();
            }
        }
    }

    // the overrides as written (a swap is stored as hexes, a pick as the theme's colour name)
    FileView {
        id: overridesFile
        path: `${root.overridesDir}/${root.target}.toml`
        printErrors: false
        onLoaded: {
            const o = {};
            for (const line of text().split("\n")) {
                const m = line.match(/^\s*([\w-]+)\s*=\s*"([^"]*)"/);
                if (m) o[m[1]] = m[2];
            }
            root.overrides = o;
        }
        onLoadFailed: root.overrides = {}
    }

    Process {
        id: writeProc
        onExited: root.apply()
    }

    Timer {
        id: applyTimer
        interval: 500
        onTriggered: {
            if (applyProc.running) { applyTimer.restart(); return; }
            root.applying = true;
            applyProc.running = true;
        }
    }

    Process {
        id: applyProc
        command: ["bash", FileUtils.trimFileProtocol(`${Directories.config}/quickshell/ii/scripts/colors/switchwall.sh`), "--noswitch"]
        onExited: {
            root.applying = false;
            root.loadVariables();
        }
    }

    onTargetChanged: loadVariables()
    Component.onCompleted: refresh()
}
