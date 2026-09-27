pragma Singleton
pragma ComponentBehavior: Bound

// Per-application display settings. Each profile has a scope — "screen" (swaps
// Hyprland's global screen_shader) or "window" (a click-through overlay that can
// only dim/tint: a Wayland surface can't sample what's beneath it) — and a
// trigger, "focus" or "workspace". Sole owner of decoration:screen_shader.

import qs.services
import qs.modules.common
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import Qt.labs.folderlistmodel
import QtQml.Models

Singleton {
    id: root

    property bool enabled: false

    // Live effect thumbnails; costs GPU (each visible row runs the real renderer).
    property bool livePreview: true

    property var profiles: ({})

    // Global shader when no profile governs. Owned by DisplaySettings.
    property string baseShader: ""
    /*
     * The VALUES behind a generated base shader, not just its path.
     *
     * `baseShader` used to be saved on its own, and the file it named lives in
     * /dev/shm — which is emptied on reboot. So the path came back and the file
     * did not: Hyprland was handed a shader that was not there, and the global
     * grading was silently gone besides. Keeping the six numbers means the file
     * can simply be written again at startup.
     *
     * Null when the base shader is a real file of your own rather than one
     * generated from the sliders.
     */
    property var baseGrading: null

    readonly property var defaults: ({
        scope: "screen",        // "screen" | "window"
        trigger: "focus",       // "focus"  | "workspace"
        // window scope
        dim: 0.0,               // 0..0.9   black over the window
        tint: "#000000",
        tintStrength: 0.0,      // 0..0.8   colour over the window
        // screen scope
        saturation: 1.0,
        contrast: 1.0,
        gain: 1.0,
        gamma: 1.0,
        invert: false,
        grayscale: false,
        shader: "",             // a .frag path overrides the grading values
        // window scope: an animated effect from a pack (path to its .json)
        effect: "",
        // { <effect path>: { <param id>: value } }
        effectParams: ({})
    })

    readonly property string storePath:
        Quickshell.env("HOME") + "/.local/state/quickshell/user/appDisplay.json"

    // ── Profile access ──────────────────────────────────────────────────
    function has(appId) { return root.profiles.hasOwnProperty(appId); }

    function get(appId) {
        return Object.assign({}, root.defaults, root.profiles[appId] ?? {});
    }

    function setProfile(appId, p) {
        if (!appId || appId.length === 0) return;
        const next = Object.assign({}, root.profiles);
        next[appId] = Object.assign({}, root.defaults, p);
        root.profiles = next;
        root.save();
    }

    function update(appId, key, value) {
        const p = root.get(appId);
        p[key] = value;
        root.setProfile(appId, p);
    }

    function clearProfile(appId) {
        if (!root.has(appId)) return;
        const next = Object.assign({}, root.profiles);
        delete next[appId];
        root.profiles = next;
        root.save();
    }

    // Profile override if set, else the effect's declared default.
    function paramValue(appId, effectPath, param) {
        const p = root.get(appId);
        const over = (p.effectParams ?? {})[effectPath];
        if (over && over[param.id] !== undefined) return over[param.id];
        return param.value;
    }

    function setParam(appId, effectPath, id, value) {
        const p = root.get(appId);
        const all = Object.assign({}, p.effectParams ?? {});
        const one = Object.assign({}, all[effectPath] ?? {});
        one[id] = value;
        all[effectPath] = one;
        root.update(appId, "effectParams", all);
    }

    function resetParams(appId, effectPath) {
        const p = root.get(appId);
        const all = Object.assign({}, p.effectParams ?? {});
        delete all[effectPath];
        root.update(appId, "effectParams", all);
    }

    // ── Theme colours ───────────────────────────────────────────────────
    // Effects may name an M3 role ("@primary") instead of hex, so packs follow the wallpaper.
    function themeColor(name) {
        const key = String(name).replace(/^@/, "");
        const m3 = Appearance.m3colors;
        // Roles are stored as m3<role>; accept both "primary" and "m3primary".
        if (m3[key] !== undefined) return m3[key];
        const pref = "m3" + key;
        if (m3[pref] !== undefined) return m3[pref];
        const alias = ({
            accent: "m3primary", text: "m3onSurface", bg: "m3background",
            surface: "m3surface", outline: "m3outline"
        });
        if (alias[key] && m3[alias[key]] !== undefined) return m3[alias[key]];
        return "#000000";
    }

    function resolveColor(v) {
        return (typeof v === "string" && v.startsWith("@")) ? root.themeColor(v) : v;
    }

    function isNeutral(p) {
        return p.saturation === 1.0 && p.contrast === 1.0 && p.gain === 1.0
            && p.gamma === 1.0 && !p.invert && !p.grayscale;
    }

    function shaderName(path) {
        if (!path || String(path).length === 0) return "None";
        return String(path).split("/").pop().replace(/\.(frag|glsl)$/, "");
    }


    function save() {
        store.setText(JSON.stringify({ enabled: root.enabled,
                                       livePreview: root.livePreview,
                                       baseShader: root.baseShader,
                                       baseGrading: root.baseGrading,
                                       profiles: root.profiles }, null, 1));
    }

    // ── Context: what is focused, what is on the visible workspace ───────
    readonly property string focusedApp: ToplevelManager.activeToplevel?.appId ?? ""

    // Hyprland's class matches ToplevelManager's appId (native and XWayland), so the two mix.
    readonly property var workspaceApps: {
        const ws = HyprlandData.activeWorkspace?.id;
        const out = [];
        const wl = HyprlandData.windowList ?? [];
        for (let i = 0; i < wl.length; ++i) {
            const w = wl[i];
            if (!w || w.workspace?.id !== ws) continue;
            if (w.class && out.indexOf(w.class) === -1) out.push(w.class);
        }
        return out;
    }

    function triggerMatches(appId) {
        const p = root.get(appId);
        if (p.trigger === "focus") return appId === root.focusedApp;
        return root.workspaceApps.indexOf(appId) !== -1;
    }

    // ── Screen scope: which profile owns the display right now ───────────
    // The focused app wins; otherwise the first workspace-triggered profile.
    readonly property string governing: {
        if (!root.enabled) return "";
        const f = root.focusedApp;
        if (f.length > 0 && root.has(f) && root.get(f).scope === "screen"
            && root.triggerMatches(f))
            return f;
        const ws = root.workspaceApps;
        for (let i = 0; i < ws.length; ++i) {
            const a = ws[i];
            if (root.has(a) && root.get(a).scope === "screen"
                && root.get(a).trigger === "workspace")
                return a;
        }
        return "";
    }

    // ── Effect packs ────────────────────────────────────────────────────
    // Effects are JSON-described animated overlays; a pack is a folder of them. Not Hyprland
    // shaders: those get no time uniform, so anything animated is drawn by us.
    readonly property string packDir: Quickshell.env("HOME") + "/.config/hypr/shaderpacks"
    readonly property string shaderSrcDir:
        Quickshell.env("HOME") + "/.config/quickshell/ii/modules/ii/display/shaders"
    readonly property string packFolderStore:
        Quickshell.env("HOME") + "/.local/state/quickshell/user/effectFolders.json"
    property var extraPackDirs: []

    // [{ path, pack, name, kind, color, strength, speed, icon, desc }]
    property var effects: []

    readonly property var packNames: {
        const seen = [];
        for (let i = 0; i < root.effects.length; ++i) {
            const p = root.effects[i].pack;
            if (seen.indexOf(p) === -1) seen.push(p);
        }
        return seen.sort();
    }

    function effectsInPack(pack) {
        return root.effects.filter(e => e.pack === pack);
    }

    function effectByPath(path) {
        if (!path || path.length === 0) return null;
        return root.effects.find(e => e.path === path) ?? null;
    }

    function effectName(path) {
        const e = root.effectByPath(path);
        return e ? e.name : "None";
    }

    // path → parsed effect; debounced into `effects` so a folder yields one update.
    property var effectMap: ({})

    function publishEffects() {
        const out = [];
        for (const k in root.effectMap) out.push(root.effectMap[k]);
        out.sort((a, b) => (a.pack + a.name).localeCompare(b.pack + b.name));
        root.effects = out;
    }

    Timer {
        id: publishDebounce
        interval: 90
        onTriggered: root.publishEffects()
    }

    function noteEffect(path, obj) {
        const next = Object.assign({}, root.effectMap);
        if (obj === null) delete next[path];
        else next[path] = obj;
        root.effectMap = next;
        publishDebounce.restart();
    }

    // Params: @param lines for glsl effects, plus the JSON fields the renderer uses.
    function paramsFor(j, shaderSrc) {
        const ps = [];
        if (j.kind === "glsl" && shaderSrc) {
            // Anchored on ABI slot names so prose mentioning "@param" isn't parsed.
            const re = /@param\s+(p[1-9]|c[1-9])\s+(\S+)\s+(.+)/g;
            let m;
            while ((m = re.exec(shaderSrc)) !== null) {
                const slot = m[1], label = m[2], rest = m[3].trim();
                if (rest.startsWith("#")) {
                    ps.push({ id: slot, label: label, type: "color",
                              value: rest.split(/\s+/)[0] });
                } else if (rest.startsWith("toggle")) {
                    const t = rest.split(/\s+/);
                    ps.push({ id: slot, label: label, type: "toggle",
                              value: t.length > 1 ? parseFloat(t[1]) || 0 : 0 });
                } else {
                    const toks = rest.split(/\s+/);
                    let step = 0;
                    const nums = [];
                    for (let i = 0; i < toks.length; ++i) {
                        if (toks[i].startsWith("step=")) {
                            step = parseFloat(toks[i].slice(5)) || 0;
                        } else {
                            const v = parseFloat(toks[i]);
                            if (!isNaN(v)) nums.push(v);
                        }
                    }
                    if (nums.length >= 3)
                        ps.push({ id: slot, label: label, type: "float",
                                  min: nums[0], max: nums[1], value: nums[2], step: step });
                }
            }
        }
        // JSON defaults override the shader's, so one shader can back many presets.
        const over = j.defaults ?? {};
        for (let i = 0; i < ps.length; ++i)
            if (over[ps[i].id] !== undefined) ps[i].value = over[ps[i].id];

        ps.push({ id: "strength", label: "Strength", type: "float",
                  min: 0.0, max: 1.0, value: j.strength, step: 0 });
        ps.push({ id: "speed", label: "Speed", type: "float",
                  min: 0.0, max: 6.0, value: j.speed, step: 0 });
        if (j.kind !== "glsl")
            ps.push({ id: "color", label: "Colour", type: "color", value: j.color });
        return ps;
    }

    // FolderListModel doesn't watch for added/removed files; bumping the nonce forces a re-read.
    property int scanNonce: 0
    function rescanEffects() {
        root.scanNonce++;
        root.publishEffects();
    }

    readonly property var packRoots: [root.packDir].concat(root.extraPackDirs)

    Instantiator {
        model: root.packRoots
        delegate: QtObject {
            id: packRootItem
            required property string modelData

            // FolderListModel isn't recursive: one lists pack folders, a nested one their files.
            property FolderListModel dirs: FolderListModel {
                // Referencing the nonce makes this re-evaluate on rescan.
                folder: root.scanNonce >= 0
                    ? "file://" + packRootItem.modelData + (root.scanNonce % 2 ? "/." : "")
                    : ""
                showFiles: false
                showDirs: true
                showDotAndDotDot: false
            }

            property Instantiator packs: Instantiator {
                model: packRootItem.dirs
                delegate: QtObject {
                    id: packItem
                    required property string filePath

                    property FolderListModel files: FolderListModel {
                        folder: "file://" + packItem.filePath
                        nameFilters: ["*.json"]
                        showDirs: false
                        showDotAndDotDot: false
                    }

                    property Instantiator entries: Instantiator {
                        model: packItem.files
                        delegate: QtObject {
                            id: fileItem
                            required property string filePath
                            required property string fileName

                            // Parsed JSON, held until the shader source has loaded too.
                            property var pending: null

                            property FileView view: FileView {
                                path: "file://" + fileItem.filePath
                                watchChanges: true
                                onFileChanged: reload()
                                onLoaded: {
                                    let j;
                                    try { j = JSON.parse(view.text() || "{}"); }
                                    catch (e) { return; }
                                    if (!j.kind) return;
                                    j.path = fileItem.filePath;
                                    j.pack = String(packItem.filePath).split("/").pop();
                                    if (!j.name) j.name = fileItem.fileName.replace(/\.json$/, "");
                                    if (!j.color) j.color = "#000000";
                                    if (j.strength === undefined) j.strength = 0.3;
                                    if (j.speed === undefined) j.speed = 1.0;
                                    if (!j.icon) j.icon = "auto_awesome";
                                    if (!j.desc) j.desc = "";
                                    if (j.kind === "glsl" && j.shader) {
                                        fileItem.pending = j;
                                        shaderView.path = "file://" + root.shaderSrcDir
                                            + "/" + String(j.shader).replace(".qsb", "");
                                    } else {
                                        j.params = root.paramsFor(j, "");
                                        root.noteEffect(j.path, j);
                                    }
                                }
                                onLoadFailed: root.noteEffect(fileItem.filePath, null)
                            }

                            // glsl only: tunables are declared in the shader source.
                            property FileView shaderView: FileView {
                                onLoaded: {
                                    const j = fileItem.pending;
                                    if (!j) return;
                                    j.params = root.paramsFor(j, shaderView.text() || "");
                                    root.noteEffect(j.path, j);
                                }
                                onLoadFailed: {
                                    const j = fileItem.pending;
                                    if (!j) return;
                                    j.params = root.paramsFor(j, "");
                                    root.noteEffect(j.path, j);
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    FileView {
        id: packFolders
        path: Qt.resolvedUrl(root.packFolderStore)
        onLoaded: {
            try { root.extraPackDirs = JSON.parse(packFolders.text() || "[]"); }
            catch (e) { root.extraPackDirs = []; }
            root.rescanEffects();
        }
        onLoadFailed: (error) => {
            if (error === FileViewError.FileNotFound) packFolders.setText("[]");
            root.rescanEffects();
        }
    }

    // Overlays follow Hyprland's live corner rounding.
    property int rounding: 18

    Process {
        id: roundingQuery
        command: ["hyprctl", "getoption", "decoration:rounding", "-j"]
        running: true
        stdout: StdioCollector {
            onStreamFinished: {
                try { root.rounding = JSON.parse(text).int ?? 18; } catch (e) {}
            }
        }
    }

    Connections {
        target: Hyprland
        function onRawEvent(event) {
            if (event.name === "configreloaded") roundingQuery.running = true;
        }
    }

    // ── Window scope: rects to paint an overlay over ─────────────────────
    readonly property var overlays: {
        if (!root.enabled || GameMode.active) return [];
        const out = [];
        const ws = HyprlandData.activeWorkspace?.id;
        const wl = HyprlandData.windowList ?? [];
        for (let i = 0; i < wl.length; ++i) {
            const w = wl[i];
            if (!w || !w.class || !w.at || !w.size) continue;
            if (w.workspace?.id !== ws) continue;
            if (w.hidden) continue;
            if (!root.has(w.class)) continue;
            const p = root.get(w.class);
            if (p.scope !== "window") continue;
            if (!root.triggerMatches(w.class)) continue;
            let fx = root.effectByPath(p.effect);
            if (fx) {
                const vals = ({});
                for (let k = 0; k < (fx.params ?? []).length; ++k) {
                    const prm = fx.params[k];
                    // Colours stay raw ("@primary"); the renderer binds them live so theme changes apply.
                    vals[prm.id] = root.paramValue(w.class, fx.path, prm);
                }
                fx = Object.assign({}, fx, { values: vals });
            }
            if (p.dim <= 0.001 && p.tintStrength <= 0.001 && !fx) continue;
            out.push({
                address: w.address,
                appId: w.class,
                x: w.at[0], y: w.at[1], w: w.size[0], h: w.size[1],
                // Fullscreen windows are drawn square by Hyprland.
                rounding: (w.fullscreen && w.fullscreen > 0) ? 0 : root.rounding,
                dim: p.dim, tint: p.tint, tintStrength: p.tintStrength,
                effect: fx
            });
        }
        return out;
    }

    // ── Shader construction ─────────────────────────────────────────────
    // MUST be GLES3 (#version 300 es): Hyprland's vertex shader is versioned, and GLES2
    // syntax fails to link — reported only as a toast, never in the log.
    function buildGradingFrag(sat, con, gainV, gam, inv, gray) {
        const s = gray ? 0.0 : sat;
        return "#version 300 es\n"
            + "precision highp float;\n"
            + "in vec2 v_texcoord;\n"
            + "uniform sampler2D tex;\n"
            + "out vec4 fragColor;\n"
            + "void main() {\n"
            + "    vec4 c = texture(tex, v_texcoord);\n"
            + "    vec3 col = c.rgb;\n"
            + "    col = pow(max(col, vec3(0.0)), vec3(1.0 / " + gam.toFixed(4) + "));\n"
            + "    col *= " + gainV.toFixed(4) + ";\n"
            + "    col = (col - 0.5) * " + con.toFixed(4) + " + 0.5;\n"
            + "    float luma = dot(col, vec3(0.2126, 0.7152, 0.0722));\n"
            + "    col = mix(vec3(luma), col, " + s.toFixed(4) + ");\n"
            + "    col = mix(col, vec3(1.0) - col, " + (inv ? "1.0" : "0.0") + ");\n"
            + "    fragColor = vec4(clamp(col, 0.0, 1.0), c.a);\n"
            + "}\n";
    }

    readonly property string appShaderPath: "/dev/shm/qs-appdisplay.frag"

    // What the screen should be running, ignoring file-generation timing.
    readonly property string desiredShader: {
        const g = root.governing;
        const p = g.length > 0 ? root.get(g) : null;
        // A shader set on the focused app's OWN profile beats GameMode: GameMode drops the generic
        // grading and base shader to save frames, but a shader picked for this very game (a shadow
        // boost for a dark shooter) is the reason the profile exists.
        if (p && p.shader && p.shader.length > 0) return p.shader;
        if (GameMode.active) return "";
        if (g.length === 0) return root.baseShader;
        if (root.isNeutral(p)) return "";
        return root.appShaderPath;   // needs generating first
    }

    property string applied: " unset"
    property string pendingFrag: ""

    function reapply(force) {
        const want = root.desiredShader;

        // Grading for the governing app has to be written before it is named.
        if (want === root.appShaderPath) {
            const p = root.get(root.governing);
            const frag = root.buildGradingFrag(p.saturation, p.contrast, p.gain,
                                               p.gamma, p.invert, p.grayscale);
            if (frag === root.pendingFrag && want === root.applied && !force) return;
            root.pendingFrag = frag;
            writer.command = ["bash", "-c",
                "cat > '" + root.appShaderPath + "' <<'QSEOF'\n" + frag + "QSEOF"];
            writer.running = true;
            return;
        }

        if (!force && want === root.applied) return;
        root.push(want);
    }

    /// Point Hyprland at a shader file, but never at one that is not there.
    ///
    /// Hyprland answers a missing path with "screen shader parser failed to
    /// check screen shader path: No such file or directory" and then has BOTH
    /// no shader and an error — and it is reachable without anyone doing
    /// anything wrong, because the generated shaders live in /dev/shm and
    /// /dev/shm is emptied on reboot. The saved path outlived the file.
    function push(path) {
        if (path.length === 0) {
            root.pushNow("");
            return;
        }
        // One `test -f` per shader change, which is debounced to 110ms — far
        // cheaper than the error it prevents, and it also covers a shader of
        // your own that was deleted or renamed while the shell was running.
        shaderCheck.wanted = path;
        shaderCheck.command = ["test", "-f", path];
        shaderCheck.running = true;
    }

    Process {
        id: shaderCheck
        property string wanted: ""
        onExited: (code) => {
            if (code === 0) {
                root.pushNow(shaderCheck.wanted);
                return;
            }
            console.warn(`[AppDisplay] shader file is gone, clearing instead of naming it: ${shaderCheck.wanted}`);
            // Forget it as well as clearing it, or the next reapply() tries the
            // same dead path and warns again for the rest of the session.
            if (shaderCheck.wanted === root.baseShader) {
                root.baseShader = "";
                root.save();
            }
            root.pushNow("");
        }
    }

    function pushNow(path) {
        root.applied = path;
        // Startup guard: don't wipe a screen_shader set in hyprland.conf on restart.
        if (path.length === 0 && root.everPushed === false) return;
        root.everPushed = true;
        // Not `hyprctl keyword`: under a Lua config it silently answers "unknown request".
        // `eval` with hl.config is the live transport; an empty string clears the shader.
        const esc = String(path).replace(/\\/g, "\\\\").replace(/"/g, '\\"');
        Quickshell.execDetached(["hyprctl", "eval",
            `hl.config({ decoration = { screen_shader = "${esc}" } })`]);
    }
    property bool everPushed: false

    Process {
        id: writer
        onExited: (code) => {
            if (code !== 0) return;
            // Same path, new contents: Hyprland only re-reads the file when set again.
            root.applied = "";
            root.push(root.appShaderPath);
        }
    }

    readonly property string baseGradingPath: "/dev/shm/qs-display-shader.frag"

    /// Write the global grading shader from its values and apply it. Owning the
    /// generation here rather than in the settings panel is what lets it be
    /// rebuilt on load, when no panel is instantiated.
    function setBaseGrading(g) {
        if (!g || root.isNeutral(g)) {
            root.baseGrading = null;
            root.setBase("", false);
            return;
        }
        root.baseGrading = ({ saturation: g.saturation, contrast: g.contrast,
                              gain: g.gain, gamma: g.gamma,
                              invert: g.invert === true, grayscale: g.grayscale === true });
        const frag = root.buildGradingFrag(g.grayscale === true ? 0.0 : g.saturation,
                                           g.contrast, g.gain, g.gamma,
                                           g.invert === true, g.grayscale === true);
        baseWriter.command = ["bash", "-c",
            "cat > '" + root.baseGradingPath + "' <<'QSEOF'\n" + frag + "QSEOF"];
        baseWriter.running = true;
    }

    Process {
        id: baseWriter
        // force: the path does not change but its contents just did, and
        // Hyprland only re-reads the file when the keyword is set again.
        onExited: (code) => {
            if (code === 0) root.setBase(root.baseGradingPath, true);
        }
    }

    // Called by DisplaySettings when it changes the global (no-profile) shader.
    function setBase(path, force) {
        root.baseShader = path;
        if (force === true && root.governing.length === 0) {
            root.applied = "";   // contents changed under an unchanged path
        }
        root.save();
        root.reapply(force === true);
    }

    onDesiredShaderChanged: root.reapply(false)
    onEnabledChanged: { root.save(); root.reapply(false); }
    onLivePreviewChanged: root.save()

    FileView {
        id: store
        path: Qt.resolvedUrl(root.storePath)
        onLoaded: {
            try {
                const d = JSON.parse(store.text() || "{}");
                root.profiles = d.profiles ?? {};
                root.enabled = d.enabled === true;
                if (d.livePreview !== undefined) root.livePreview = d.livePreview === true;
                // A generated base shader is rebuilt from its values rather
                // than restored by path: the path survives a reboot and the
                // file in /dev/shm does not.
                if (d.baseGrading && !root.isNeutral(d.baseGrading)) {
                    Qt.callLater(() => root.setBaseGrading(d.baseGrading));
                } else if (typeof d.baseShader === "string" && d.baseShader.length > 0
                           && !d.baseShader.startsWith("/dev/shm/")) {
                    // A real shader file of your own. reapply(), not just
                    // assignment: baseShader alone doesn't push it — and push()
                    // checks it still exists before naming it.
                    root.baseShader = d.baseShader;
                    Qt.callLater(() => root.reapply(true));
                }
            } catch (e) {
                root.profiles = ({});
            }
        }
        onLoadFailed: (error) => {
            if (error === FileViewError.FileNotFound)
                store.setText(JSON.stringify({ enabled: false, profiles: {} }));
        }
    }
}
























