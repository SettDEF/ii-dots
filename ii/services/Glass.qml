pragma Singleton
pragma ComponentBehavior: Bound

import qs
import qs.modules.common
import QtQuick
import Quickshell
import Quickshell.Io

/**
 * Palette > Glass: see-through app windows over Hyprland blur.
 *
 * Two kinds of app:
 *  - "native": the app makes only its BACKGROUND see-through, from a glass
 *    file its config includes; text stays solid. Hyprland blurs behind it.
 *  - "window": Hyprland fades the whole window, text included.
 *
 * Everything is applied live. Window rules are named `glass-<id>` and
 * re-setting a name replaces the rule, so an app switched off gets its rule
 * pointed at a class that never exists. The same Lua is saved to
 * hypr/lua/glass.lua (loaded by lua/local.lua) so `hyprctl reload` keeps it.
 */
Singleton {
    id: root

    readonly property var cfg: Config.options.appearance.glass
    readonly property bool onBattery: Battery.available && !Battery.isPluggedIn
    /// Glass is on and the battery rule does not switch it off right now.
    readonly property bool active: (cfg?.enable ?? false) && !(cfg.battery === "off" && root.onBattery)
    readonly property bool lighter: (cfg?.battery ?? "") === "lighter" && root.onBattery

    readonly property string home: Quickshell.env("HOME")

    // `cls` is a Hyprland class regex; "" = no window (a layer, e.g. fuzzel).
    readonly property var apps: [
        { id: "zash",     name: "zash",     icon: "terminal",       kind: "native", cls: "^(zash)$",
          note: "" },
        { id: "wezterm",  name: "WezTerm",  icon: "terminal",       kind: "native", cls: "^(org\\.wezfurlong\\.wezterm)$",
          note: "" },
        { id: "kitty",    name: "Kitty",    icon: "terminal",       kind: "native", cls: "^(kitty)$",
          note: qsTr("Windows opened before the first switch-on need a restart once") },
        { id: "discord",  name: "Discord",  icon: "forum",          kind: "native", cls: "(?i)^(discord|vesktop|legcord|equibop)$",
          note: qsTr("Turn on the “Glass” theme once in Discord → Settings → Themes") },
        { id: "fuzzel",   name: "Launcher (Fuzzel)", icon: "search", kind: "native", cls: "",
          note: "" },
        { id: "zathura",  name: "Zathura",  icon: "picture_as_pdf", kind: "native", cls: "(?i)^(org\\.pwmt\\.zathura)$",
          note: "" },
        { id: "websites", name: "Websites", icon: "public", kind: "native", cls: "",
          note: qsTr("Page backgrounds go see-through via the tinct live userscript (1.2.0). In tela-zen, needs Zen browser's Glass on too.") },
        { id: "zen",      name: "tela-zen", icon: "language",    kind: "native", cls: "^(zen)$",
          note: qsTr("tela-zen 1.21.16b-8 or newer: sidebar and toolbar see-through, pages solid.") },
        { id: "qutebrowser", name: "qutebrowser", icon: "language", kind: "window", cls: "(?i)^(org\\.qutebrowser\\.qutebrowser|qutebrowser)$", note: "" },
        { id: "telegram", name: "Telegram", icon: "send",           kind: "window", cls: "(?i)^(org\\.telegram\\.desktop|telegramdesktop)$", note: "" },
        { id: "obsidian", name: "Obsidian", icon: "description",    kind: "window", cls: "(?i)^(obsidian|md\\.obsidian\\.obsidian)$", note: "" },
        { id: "code",     name: "VS Code",  icon: "code",           kind: "window", cls: "(?i)^(code|code-oss|code-url-handler)$", note: "" },
        { id: "dolphin",  name: "Dolphin",  icon: "folder",         kind: "window", cls: "(?i)^(org\\.kde\\.dolphin|dolphin)$", note: "" },
        { id: "nautilus", name: "Files (Nautilus)", icon: "folder", kind: "window", cls: "(?i)^(org\\.gnome\\.nautilus)$", note: "" },
        { id: "steam",    name: "Steam",    icon: "sports_esports", kind: "window", cls: "(?i)^(steam)$", note: "" },
        { id: "blender",  name: "Blender",  icon: "deployed_code",  kind: "window", cls: "(?i)^(blender)$", note: "" },
        { id: "bitwig",   name: "Bitwig Studio", icon: "piano",     kind: "window", cls: "(?i)^(com\\.bitwig\\.bitwigstudio|bitwig.*)$", note: "" },
    ]

    function app(id) { return root.apps.find(a => a.id === id) ?? null }

    /// Saved settings for an app, with defaults filled in. Whole-window apps
    /// start off: faded text is harder to read.
    function appState(id) {
        const saved = (root.cfg?.apps ?? {})[id] ?? {};
        return {
            // Websites start off: until tela-zen is see-through (#38) a
            // transparent page only shows the browser's own background.
            on: saved.on ?? (root.app(id)?.kind === "native" && id !== "websites" && id !== "zen"),
            opacity: saved.opacity ?? root.cfg?.strength ?? 0.85,
            blur: saved.blur ?? true,
        };
    }

    function setApp(id, patch) {
        const next = Object.assign({}, root.cfg.apps ?? {});
        next[id] = Object.assign(root.appState(id), patch);
        root.cfg.apps = next;
    }

    /// Whether an app is see-through right now.
    function isLive(id) { return root.active && root.appState(id).on }

    /* --- what gets written ------------------------------------------------ */

    function _hex2(v) { return Math.round(Math.max(0, Math.min(1, v)) * 255).toString(16).padStart(2, "0") }
    function _rgba(c, a) {
        return `rgba(${Math.round(c.r * 255)}, ${Math.round(c.g * 255)}, ${Math.round(c.b * 255)}, ${a.toFixed(2)})`;
    }
    function _hex(c) { return _hex2(c.r) + _hex2(c.g) + _hex2(c.b) }

    function _compositorLua() {
        const c = root.cfg.compositor;
        // Off = general.conf's own values, so Glass off is exactly as before.
        const on = root.active;
        const size = on ? c.size : 6;
        const passes = on ? (root.lighter ? 1 : c.passes) : 1;
        return "hl.config({ decoration = {\n"
            + `  blur = { size = ${size}, passes = ${passes}, noise = ${(on ? c.noise : 0.05).toFixed(3)},`
            + ` contrast = ${(on ? c.contrast : 0.89).toFixed(3)}, brightness = ${(on ? c.brightness : 1).toFixed(3)},`
            + ` vibrancy = ${(on ? c.vibrancy : 0.5).toFixed(3)}, xray = ${on ? c.xray : true},`
            + ` popups = ${on ? c.popups : false} },\n`
            + `  dim_inactive = ${on ? c.dimInactive : true}, dim_strength = ${(on ? c.dimStrength : 0.05).toFixed(3)},\n`
            + "} })\n";
    }

    function _rulesLua() {
        let out = "";
        for (const a of root.apps) {
            if (!a.cls) continue;
            const st = root.appState(a.id);
            const live = root.active && st.on;
            const cls = live ? a.cls : "^(__glass_off__)$";
            let props = `no_blur = ${live ? !st.blur : true}`;
            // The border is transparent in this config: blurred, it showed as a
            // bright line of wallpaper around the window.
            if (live) props += ", border_size = 0";
            if (live && a.kind === "window")
                props += `, opacity = '${st.opacity.toFixed(2)} override ${st.opacity.toFixed(2)} override'`;
            out += `hl.window_rule({ name = 'glass-${a.id}', match = { class = '${cls.replace(/\\/g, "\\\\")}' }, ${props} })\n`;
        }
        return out;
    }

    /// path -> content for every native app's glass file.
    function _files() {
        const m = Appearance.m3colors;
        const f = {};
        const st = id => ({ live: root.isLive(id), o: root.appState(id).opacity });

        const wz = st("wezterm");
        f[root.home + "/.config/wezterm/glass.lua"] =
            "-- Written by the shell (Palette > Glass).\n"
            + (wz.live ? `return { opacity = ${wz.o.toFixed(2)} }\n` : "return {}\n");

        const zs = st("zash");
        f[root.home + "/.config/zash/glass.lua"] =
            "-- Written by the shell (Palette > Glass).\n"
            + (zs.live ? `return { opacity = ${zs.o.toFixed(2)} }\n` : "return {}\n");

        const kt = st("kitty");
        f[root.home + "/.config/kitty/glass.conf"] =
            "# Written by the shell (Palette > Glass).\ndynamic_background_opacity yes\n"
            + `background_opacity ${(kt.live ? kt.o : 1).toFixed(2)}\n`;

        const fz = st("fuzzel");
        f[root.home + "/.config/fuzzel/glass.ini"] = fz.live
            ? `# Written by the shell (Palette > Glass).\n[colors]\nbackground=${root._hex(m.m3surface)}${root._hex2(fz.o)}\n`
            : "";

        const zt = st("zathura");
        f[root.home + "/.config/zathura/glass.rc"] = zt.live
            ? `# Written by the shell (Palette > Glass).\nset default-bg "${root._rgba(m.m3surface, zt.o)}"\n`
            : "";

        const dc = st("discord");
        f[root.home + "/.config/BetterDiscord/themes/glass.theme.css"] =
            "/**\n * @name Glass\n * @description See-through Discord, set from the shell's Palette > Glass panel.\n"
            + " * @author caesar\n * @version 1.0.0\n*/\n"
            + (dc.live ? root._discordCss(dc.o) : "/* Glass is off for Discord. */\n");
        const ws = st("websites");
        f[root.home + "/.local/share/stylus-themes/glass.json"] =
            JSON.stringify({ enabled: ws.live, opacity: Number(ws.o.toFixed(2)) });
        // tela-zen follows this live (TelaGlass.sys.mjs); "pages" lets the
        // userscript's see-through pages show the glass.
        const zn = st("zen");
        f[root.home + "/.config/tela-zen/glass.json"] =
            JSON.stringify({ enabled: zn.live, opacity: Number(zn.o.toFixed(2)), pages: ws.live });
        f[root.home + "/.config/hypr/ii-decor.json"] = root._decorJson();
        return f;
    }

    function _discordCss(o) {
        const m = Appearance.m3colors;
        // Midnight's layers, at the chosen opacity. Only ONE element paints
        // the window: stacked translucent layers would multiply into opaque.
        return "body {\n  --remove-bg-layer: on;\n}\n"
            + ":root {\n"
            + `  --bg-1: ${root._rgba(m.m3surfaceContainerHighest, Math.min(1, o + 0.1))};\n`
            + `  --bg-2: ${root._rgba(m.m3surfaceContainerHigh, Math.min(1, o + 0.05))};\n`
            + `  --bg-3: ${root._rgba(m.m3surface, o)};\n`
            + `  --bg-4: ${root._rgba(m.m3surfaceContainer, o)};\n`
            + "}\n"
            + "html:root, html body, html #app-mount {\n  background-color: transparent !important;\n}\n"
            + `html .app_a3002d {\n  background-color: ${root._rgba(m.m3surface, o * 0.6)} !important;\n}\n`;
    }

    /// ii-decor (window title bars). Bar follows Glass: see-through at the
    /// strength slider while Glass is on, solid otherwise. Dots match
    /// Midnight's in Discord: tertiary, a green pulled to primary, error.
    function _decorJson() {
        const m = Appearance.m3colors;
        const d = root.cfg.decor;
        const hex = c => root._hex(c);
        const green = Qt.rgba(0.341 * 0.8 + m.m3primary.r * 0.2, 0.820 * 0.8 + m.m3primary.g * 0.2,
                              0.545 * 0.8 + m.m3primary.b * 0.2, 1);
        const barAlpha = d.barOpacity >= 0 ? d.barOpacity : (root.active ? (root.cfg.strength ?? 0.85) : 1);
        const role = r => ({ surface: m.m3surface, low: m.m3surfaceContainerLow, container: m.m3surfaceContainer,
                             high: m.m3surfaceContainerHigh, highest: m.m3surfaceContainerHighest })[r] ?? m.m3surface;
        const perClass = {};
        // Follow the app: its own toolbar colour (scripts/decor/appcolors.sh) at
        // its own Glass opacity, so a solid app gets a solid bar.
        const kde = root.decorAppColors.__kde__;
        if (d.followApp && d.colorSource === "app") {
            for (const cls in root.decorAppColors) {
                if (cls === "__kde__") continue;
                const c = root.decorAppColors[cls];
                const a = root._appOpacityFor(cls) * (c.alpha ?? 1);
                perClass[cls] = { bar: `rgba(${c.bar.slice(1)}${root._hex2(a)})` };
                if (c.text) perClass[cls].text = `rgb(${c.text.slice(1)})`;
            }
        }
        // Per-app choices win (Palette > Glass > Title bars > Per app). An entry
        // is { color, alpha, hidden, title }; a bare string is the old "shade only".
        for (const cls in (d.perApp ?? {})) {
            const raw = d.perApp[cls];
            const o = typeof raw === "string" ? { color: raw } : (raw ?? {});
            const own = root.decorAppColors[cls];
            const out = perClass[cls] ?? {};
            const autoAlpha = own ? root._appOpacityFor(cls) * (own.alpha ?? 1) : barAlpha;
            const alpha = (typeof o.alpha === "number" && o.alpha >= 0) ? o.alpha : autoAlpha;
            let base = null, text = null;
            if (o.color === "app" && own) { base = own.bar.slice(1); text = own.text; }
            else if (o.color === "kde" && kde) { base = kde.bar.slice(1); text = kde.text; }
            else if (o.color === "shell") { base = hex(role(d.barRole)); text = "#" + hex(m.m3onSurface); }
            else if (o.color && o.color !== "auto") { base = hex(role(o.color)); text = "#" + hex(m.m3onSurface); }
            else if (out.bar) base = out.bar.slice(5, 11);   // auto: keep what follow-app chose
            else base = hex(role(d.barRole));
            out.bar = `rgba(${base}${root._hex2(alpha)})`;
            if (text) out.text = `rgb(${text.replace("#", "")})`;
            if (o.hidden === true) out.height = 0;
            if (typeof o.title === "boolean") out.title = o.title;
            perClass[cls] = out;
        }
        return JSON.stringify({
            enabled: d.enable,
            mode: "exclude",
            classes: [
                "(?i)^(discord|vesktop|legcord|equibop|webcord)$",
                "(?i)^(zen|zen-browser|zen-beta|zen-alpha|tela-zen.*)$",
                "(?i)^(firefox.*|librewolf)$",
                "^org\\.gnome\\..*",
                "^org\\.quickshell$",
                // our quickshell apps (//@ pragma AppId) draw their own title bars
                "^(vitals|dotos|kalends|reel|vane|tinct-cast|knurl)$",
            ],
            height: d.height,
            buttons: d.buttons,
            buttonSize: d.buttonSize,
            buttonGap: d.buttonGap,
            padding: d.padding,
            title: d.title,
            titleSize: d.titleSize,
            titleWeight: d.titleBold ? 700 : 500,
            titleFont: Appearance.font.family.main,
            doubleClick: d.doubleClick,
            // "hide" parks windows on a named scratch workspace of their own.
            minimizeTo: d.minimizeTo === "hide" ? "special:minimized" : "special",
            blur: d.blur,
            icon: d.icon,
            iconSize: d.iconSize,
            icons: root.decorIcons,
            perClass: perClass,
            // Button themes: "breeze" draws generated glyph images (scripts/decor/theme.sh).
            buttonStyle: d.theme === "breeze" && Object.keys(root.decorThemeImages).length > 0 ? "images" : "dots",
            buttonImages: d.theme === "breeze" ? root.decorThemeImages : {},
            layout: ({
                "macos-left": { left: ["close", "minimize", "maximize"], right: [] },
                "extended": { left: [], right: ["pin", "float", "minimize", "maximize", "close"] },
            })[d.layout],
            separator: d.separator ? `rgba(${hex(m.m3outlineVariant)}99)` : "rgba(00000000)",
            colors: {
                bar: d.colorSource === "kde" && kde
                    ? `rgba(${kde.bar.slice(1)}${root._hex2(barAlpha)})`
                    : `rgba(${hex(role(d.barRole))}${root._hex2(barAlpha)})`,
                text: d.colorSource === "kde" && kde && kde.text
                    ? `rgb(${kde.text.slice(1)})` : `rgb(${hex(m.m3onSurface)})`,
                close: d.dots === "macos" ? "rgb(ff5f56)" : `rgb(${hex(m.m3error)})`,
                minimize: d.dots === "macos" ? "rgb(ffbd2e)" : `rgb(${hex(m.m3tertiary)})`,
                maximize: d.dots === "macos" ? "rgb(27c93f)" : `rgb(${hex(green)})`,
            },
        }, null, 2);
    }

    /* --- applying ---------------------------------------------------------- */

    /// Everything that can change the output; any change re-applies.
    readonly property string signature: JSON.stringify({
        active: root.active, lighter: root.lighter,
        comp: root.cfg ? [root.cfg.compositor.size, root.cfg.compositor.passes, root.cfg.compositor.noise,
               root.cfg.compositor.contrast, root.cfg.compositor.brightness, root.cfg.compositor.vibrancy,
               root.cfg.compositor.xray, root.cfg.compositor.popups, root.cfg.compositor.dimInactive,
               root.cfg.compositor.dimStrength] : [],
        apps: root.cfg?.apps ?? {}, strength: root.cfg?.strength ?? 0,
        decor: root.cfg ? JSON.stringify(root.cfg.decor) + JSON.stringify(root.decorIcons) + JSON.stringify(root.decorAppColors)
               + JSON.stringify(root.decorThemeImages) : "",
        colors: [String(Appearance.m3colors.m3surface), String(Appearance.m3colors.m3surfaceContainer),
                 String(Appearance.m3colors.m3surfaceContainerHigh), String(Appearance.m3colors.m3surfaceContainerHighest)],
    })
    onSignatureChanged: {
        if (!Config.ready) return;
        // A blur change re-sends hl.config, which briefly blanks an external
        // screen: wait for the slider to settle so it happens once.
        applyTimer.interval = root._compositorLua() !== root._sentBlur ? 700 : 120;
        applyTimer.restart();
    }
    property string _sentBlur: ""

    Connections {
        target: Config
        function onReadyChanged() { if (Config.ready) applyTimer.restart() }
    }

    // Sliders move continuously; one apply per pause, not per pixel.
    Timer {
        id: applyTimer
        interval: 120
        onTriggered: root.apply()
    }

    property string lastError: ""

    function apply() {
        if (!Config.ready) return;
        if (applyProc.running) { applyTimer.restart(); return; }
        const head = "-- Written by the shell (Palette > Glass). Regenerated on every change.\n";
        const files = root._files();
        // Two files: blur settings go through hl.config, which re-applies the
        // monitor setup (an external screen blanks for a moment), so they are
        // only re-sent when a blur value changed. Rules are safe to resend.
        root._sentBlur = root._compositorLua();
        files[root.home + "/.config/hypr/lua/glass_blur.lua"] = head + root._compositorLua();
        files[root.home + "/.config/hypr/lua/glass_rules.lua"] = head + root._rulesLua();

        const args = [];
        for (const p in files) args.push(p, files[p]);
        const kt = root.isLive("kitty") ? root.appState("kitty").opacity : 1;
        applyProc.command = ["bash", "-c", root._script, "glass", kt.toFixed(2)].concat(args);
        applyProc.running = true;
    }

    // $1 = kitty opacity, then path/content pairs. A file is only replaced
    // when its content changed, so watchers (wezterm, BetterDiscord) do not
    // reload for nothing; each app's live reload runs only for its own file.
    readonly property string _script: `
kitty_op="$1"; shift
changed=" "
while [ $# -ge 2 ]; do
    mkdir -p "$(dirname "$1")"
    # cmp, not "$(cat)": command substitution strips the trailing newline,
    # so every file compared as changed and blur was re-sent on every move.
    printf '%s\\n' "$2" > "$1.glass-tmp"
    if cmp -s "$1.glass-tmp" "$1"; then
        rm -f "$1.glass-tmp"
    else
        mv -f "$1.glass-tmp" "$1"
        changed="$changed$1 "
    fi
    shift 2
done
# dofile, not the text: the files open with a Lua comment, and hyprctl
# reads a leading "--" argument as one of its own flags.
for part in rules blur; do
    case "$changed" in *"/hypr/lua/glass_$part.lua "*)
        hyprctl eval "dofile('$HOME/.config/hypr/lua/glass_$part.lua')" | grep -qx ok || echo "hyprctl eval failed: $part" >&2 ;;
    esac
done
case "$changed" in *"/hypr/ii-decor.json "*)
    # Harmless while the plugin is not loaded: hyprctl just reports an unknown request.
    hyprctl iidecor reload >/dev/null 2>&1 ;;
esac
case "$changed" in *"/kitty/glass.conf "*)
    pgrep -x kitty >/dev/null && kitten @ --to unix:@kitty set-background-opacity --all "$kitty_op" >/dev/null 2>&1 ;;
esac
case "$changed" in *"/zathura/glass.rc "*)
    for n in $(busctl --user list --no-legend 2>/dev/null | awk '/^org\\.pwmt\\.zathura/{print $1}'); do
        busctl --user call "$n" /org/pwmt/zathura org.pwmt.zathura ExecuteCommand s "source" >/dev/null 2>&1
    done ;;
esac
true
`

    /// Title-bar icons: window class -> cached 64px PNG (scripts/decor/icons.sh).
    /// A compositor plugin cannot read icon themes or SVGs, so the shell does.
    property var decorIcons: ({})
    readonly property string _iconClasses: {
        const seen = {};
        for (const w of (HyprlandData.windowList ?? []))
            if (w?.class) seen[w.class] = true;
        return Object.keys(seen).sort().join("\n");
    }
    on_IconClassesChanged: iconTimer.restart()
    Timer { id: iconTimer; interval: 600; onTriggered: root.refreshIcons() }
    function refreshIcons() {
        if (iconProc.running) { iconTimer.restart(); return; }
        const args = [];
        for (const cls of root._iconClasses.split("\n"))
            if (cls) args.push(cls, AppSearch.guessIcon(cls));
        iconProc.command = ["bash", Quickshell.shellPath("scripts") + "/decor/icons.sh"].concat(args);
        iconProc.running = true;
    }
    Process {
        id: iconProc
        command: ["true"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const next = JSON.parse(this.text);
                    if (JSON.stringify(next) !== JSON.stringify(root.decorIcons)) root.decorIcons = next;
                } catch (e) {}
            }
        }
    }

    /// Breeze theme: button -> {normal, hover, pressed} PNGs (scripts/decor/theme.sh),
    /// regenerated when the theme or its colours change. Same paths each time,
    /// so the plugin's mtime check reloads them.
    property var decorThemeImages: ({})
    readonly property string _themeKey: {
        const d = root.cfg?.decor;
        if (!d || d.theme !== "breeze") return "";
        const kde = root.decorAppColors.__kde__;
        const fg = d.colorSource === "kde" && kde?.text ? kde.text : "#" + root._hex(Appearance.m3colors.m3onSurface);
        return [fg, "#" + root._hex(Appearance.m3colors.m3surfaceContainerHighest),
                "#" + root._hex(Appearance.m3colors.m3error)].join(" ");
    }
    on_ThemeKeyChanged: themeTimer.restart()
    Timer { id: themeTimer; interval: 300; onTriggered: root.refreshTheme() }
    function refreshTheme() {
        if (root._themeKey === "") { root.decorThemeImages = ({}); return; }
        if (themeProc.running) { themeTimer.restart(); return; }
        themeProc.command = ["bash", Quickshell.shellPath("scripts") + "/decor/theme.sh", "breeze"]
            .concat(root._themeKey.split(" "));
        themeProc.running = true;
    }
    Process {
        id: themeProc
        command: ["true"]
        stdout: StdioCollector {
            onStreamFinished: {
                try { root.decorThemeImages = JSON.parse(this.text); } catch (e) {}
            }
        }
    }

    /// class -> { bar, text } from each app's own theme (KDE header, GTK
    /// window, terminal background). Refreshed with the icons and whenever
    /// the palette changes (tinct rewrites those theme files).
    property var decorAppColors: ({})
    readonly property string _pidArgs: {
        const seen = {};
        for (const w of (HyprlandData.windowList ?? []))
            if (w?.class && w?.pid && !seen[w.class]) seen[w.class] = w.pid;
        return JSON.stringify(seen);
    }
    on_PidArgsChanged: appColorTimer.restart()
    readonly property string _paletteKey: String(Appearance.m3colors.m3surface) + String(Appearance.m3colors.m3primary)
    on_PaletteKeyChanged: appColorTimer.restart()
    // Long enough for tinct to finish writing kdeglobals / gtk.css.
    Timer { id: appColorTimer; interval: 1500; onTriggered: root.refreshAppColors() }
    function refreshAppColors() {
        if (appColorProc.running) { appColorTimer.restart(); return; }
        const pids = JSON.parse(root._pidArgs);
        const args = [];
        for (const cls in pids) args.push(cls, String(pids[cls]));
        appColorProc.command = ["bash", Quickshell.shellPath("scripts") + "/decor/appcolors.sh"].concat(args);
        appColorProc.running = true;
    }
    Process {
        id: appColorProc
        command: ["true"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const next = JSON.parse(this.text);
                    if (JSON.stringify(next) !== JSON.stringify(root.decorAppColors)) root.decorAppColors = next;
                } catch (e) {}
            }
        }
    }

    /// The Glass opacity of the app a window class belongs to; 1 if none.
    function _appOpacityFor(cls) {
        for (const a of root.apps) {
            if (!a.cls) continue;
            const ci = a.cls.startsWith("(?i)");
            let re;
            try { re = new RegExp(ci ? a.cls.slice(4) : a.cls, ci ? "i" : ""); } catch (e) { continue; }
            if (re.test(cls)) return root.isLive(a.id) ? root.appState(a.id).opacity : 1;
        }
        return 1;
    }

    /// Whether ii-decor is loaded in Hyprland. Checked at start, after every
    /// apply, and on demand (the panel re-checks when shown).
    property bool decorLoaded: false
    function checkDecor() { if (!decorProbe.running) decorProbe.running = true }
    Process {
        id: decorProbe
        command: ["hyprctl", "iidecor", "status"]
        stdout: StdioCollector {
            onStreamFinished: {
                try { root.decorLoaded = (JSON.parse(this.text)?.plugin ?? "") !== ""; }
                catch (e) { root.decorLoaded = false; }
            }
        }
    }
    Component.onCompleted: root.checkDecor()

    IpcHandler {
        target: "glass"
        /// Debug: the icon file the shell resolves for a window class.
        function iconFor(cls: string): string { return Quickshell.iconPath(AppSearch.guessIcon(cls), true) }
        function status(): string {
            return JSON.stringify({ active: root.active, onBattery: root.onBattery, lighter: root.lighter,
                                    apps: root.apps.reduce((o, a) => { o[a.id] = root.appState(a.id); return o; }, {}),
                                    error: root.lastError });
        }
        function enable(on: string): string {
            root.cfg.enable = (on === "on" || on === "1" || on === "true");
            return "glass -> " + root.cfg.enable;
        }
        /// `glass app <id> <on|off|0.0-1.0>`
        function app(id: string, value: string): string {
            if (!root.app(id)) return "unknown app: " + id;
            if (value === "on" || value === "off") root.setApp(id, { on: value === "on" });
            else if (!isNaN(parseFloat(value))) root.setApp(id, { opacity: Math.max(0.3, Math.min(1, parseFloat(value))) });
            else return "usage: app <id> on|off|<opacity>";
            return id + " -> " + JSON.stringify(root.appState(id));
        }
    }

    Process {
        id: applyProc
        command: ["true"]
        stderr: StdioCollector { onStreamFinished: root.lastError = this.text.trim() }
        onExited: root.checkDecor()
    }
}
