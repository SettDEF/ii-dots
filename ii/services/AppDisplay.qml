pragma Singleton
pragma ComponentBehavior: Bound

// Per-application display settings.
//
// WHAT THE COMPOSITOR ACTUALLY ALLOWS (checked against Hyprland 0.55.0):
//   * `decoration:screen_shader` is global. There is no per-window shader —
//     no config option besides that one even contains "shader".
//   * `hyprctl setprop` answers "unknown request" in this build, so per-window
//     alpha is not reachable either.
//   * Anything that must READ the pixels under a window (saturation, contrast,
//     gamma, invert) is impossible to confine to one window: a Wayland surface
//     cannot sample what is beneath it.
//
// So each app profile picks a SCOPE, and the scope decides the mechanism:
//
//   scope "screen"  — the whole display is graded/shaded while the app is up.
//                     Full grading + custom shaders. Mechanism: swap the
//                     global screen_shader as the app comes and goes.
//   scope "window"  — only the app's own window is affected, nothing bleeds
//                     outside it. Mechanism: a click-through overlay surface
//                     pinned to the window rect. Composites ON TOP, so it can
//                     dim and tint, and deliberately offers nothing else.
//
// and a TRIGGER, which decides when the profile is live:
//
//   "focus"      — only while the app is the focused window.
//   "workspace"  — whenever the app is on the workspace you're looking at,
//                  so switching to its workspace brings the look with it.
//
// This singleton is the sole owner of `decoration:screen_shader`; colour
// grading and the manual effect picker in DisplaySettings both route through
// setBase() so the two can never fight over hyprctl.

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

    // Master opt-in. Off → every profile is ignored.
    property bool enabled: false

    // Live thumbnails in the effect lists. Off by default is wrong (they are
    // the point of the list) but they DO cost GPU — each visible row runs the
    // real renderer — so it stays a switch rather than something you cannot
    // turn off.
    property bool livePreview: true

    // { appId: partial profile } — only keys that differ from defaults matter,
    // but we store whole profiles for readability of the state file.
    property var profiles: ({})

    // Global shader when no profile governs: the manual effect, or the
    // generated colour-grading shader. Owned by DisplaySettings.
    property string baseShader: ""

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
        // { <effect path>: { <param id>: value } } — keyed by effect so
        // switching effects and back keeps each one's tuning.
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

    // Effective value of one of an effect's variables: the profile override
    // if the user has touched it, otherwise the default the effect declared.
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
    // Effects can name a Material You role instead of a hex literal, so a
    // pack follows the wallpaper instead of fighting it:
    //
    //   "color": "@primary"                 in an effect's JSON
    //   @param c1 Deep @surfaceContainer    in a shader's header
    //
    // Anything not starting with "@" is passed through untouched, so plain
    // hex keeps working exactly as before.
    function themeColor(name) {
        const key = String(name).replace(/^@/, "");
        const m3 = Appearance.m3colors;
        // Roles are stored as m3<role>; accept both "primary" and "m3primary".
        if (m3[key] !== undefined) return m3[key];
        const pref = "m3" + key;
        if (m3[pref] !== undefined) return m3[pref];
        // A few friendly aliases for roles the shell exposes under its own
        // names rather than the raw M3 ones.
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
                                       profiles: root.profiles }, null, 1));
    }

    // ── Context: what is focused, what is on the visible workspace ───────
    readonly property string focusedApp: ToplevelManager.activeToplevel?.appId ?? ""

    // Hyprland reports a window's class; ToplevelManager reports appId. They
    // agree for native apps and for XWayland under Hyprland, which is what
    // lets the two sources be mixed here.
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
    // An "effect" is an animated overlay described by a small JSON file, and
    // a "pack" is just a folder of them — so adding a folder adds effects,
    // no code change. These are NOT Hyprland shaders: Hyprland supplies no
    // time uniform to screen shaders (verified — a time-driven shader renders
    // completely static), so anything animated has to be drawn by us, on the
    // window overlay we already control.
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

    // Enumerating and reading the packs is done natively — FolderListModel
    // for the directories, FileView for each file — rather than shelling out
    // to a script. Besides dropping a subprocess and a python dependency, the
    // models are LIVE: drop a new .json into a pack folder and the effect
    // appears immediately, with no rescan.

    // path → parsed effect. Rebuilt into `effects` on a short debounce so a
    // folder of files produces one update instead of one per file.
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

    // Parameters an effect exposes. For a glsl effect these come from @param
    // lines in the shader source; the rest are the JSON fields that already
    // drive the renderer, so every effect ends up with controls.
    function paramsFor(j, shaderSrc) {
        const ps = [];
        if (j.kind === "glsl" && shaderSrc) {
            // Anchored on the fixed ABI slot names, so prose in the shader's
            // own header ("@param lines below say what ...") isn't parsed as
            // a declaration.
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
        // An effect's JSON may override the shader's declared defaults, which
        // is what lets one shader back many presets: every casino background
        // is the same domain-warp program with a different palette.
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

    // FolderListModel lists a directory ONCE — it does not watch for files
    // being added or removed. Clearing `folder` and setting it back forces a
    // re-read; the nested per-pack models live inside this model's delegates,
    // so rebuilding the top level re-reads every pack as well.
    property int scanNonce: 0
    function rescanEffects() {
        root.scanNonce++;
        root.publishEffects();
    }

    // Pack roots: the built-in folder plus anything the user added.
    readonly property var packRoots: [root.packDir].concat(root.extraPackDirs)

    Instantiator {
        model: root.packRoots
        delegate: QtObject {
            id: packRootItem
            required property string modelData

            // Each root holds pack FOLDERS; FolderListModel is not recursive,
            // so one model lists the folders and a nested one lists the files.
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

                            // Parsed JSON, held until the shader source (if
                            // any) has also loaded, so params are complete.
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

                            // Only used by glsl effects: the shader source is
                            // where their tunable variables are declared.
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

    // Hyprland rounds window corners, so a square overlay would spill past
    // them at every corner. Track the live value rather than hardcoding it.
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
    // One entry per window of every active window-scope profile.
    readonly property var overlays: {
        if (!root.enabled) return [];
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
                // Resolve every declared variable to its effective value here,
                // so the renderer never has to know about overrides.
                const vals = ({});
                for (let k = 0; k < (fx.params ?? []).length; ++k) {
                    const prm = fx.params[k];
                    // Colours are passed through RAW, "@primary" and all.
                    // Resolving here would freeze the effect to whatever the
                    // theme happened to be when this list was last rebuilt;
                    // the renderer resolves them as live bindings instead, so
                    // a wallpaper change recolours running effects at once.
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
    // MUST be GLES3 (#version 300 es) with in/out/texture(): Hyprland's own
    // vertex shader is versioned, and mixing it with legacy GLES2 syntax
    // (varying/texture2D/gl_FragColor, which defaults to #version 100) fails
    // to link — "all shaders must use same shading language version". That
    // error only ever surfaces as a toast, never in the log or configerrors.
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
        if (g.length === 0) return root.baseShader;
        const p = root.get(g);
        if (p.shader && p.shader.length > 0) return p.shader;
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

    function push(path) {
        root.applied = path;
        // Startup guard: with nothing configured, desired is "" — pushing
        // [[EMPTY]] then would wipe a screen_shader set in hyprland.conf on
        // every shell restart. Adopt the state instead of asserting it.
        if (path.length === 0 && root.everPushed === false) return;
        root.everPushed = true;
        // NOT `hyprctl keyword`. Under a Lua config Hyprland answers "unknown
        // request" to keyword, so this call did nothing at all — no shader ever
        // reached the compositor, whether picked by hand or restored at startup.
        // It failed silently because execDetached never sees the reply.
        //
        // The live transport is the `eval` request carrying Lua, the same one
        // the monitor settings use. `hl.config` is how the Lua config itself
        // writes decoration options (see hypr/lua/hyprland/general.lua).
        //
        // An empty string clears the shader; the old [[EMPTY]] sentinel belongs
        // to the keyword API and is a literal filename to this one.
        const esc = String(path).replace(/\\/g, "\\\\").replace(/"/g, '\\"');
        Quickshell.execDetached(["hyprctl", "eval",
            `hl.config({ decoration = { screen_shader = "${esc}" } })`]);
    }
    property bool everPushed: false

    Process {
        id: writer
        onExited: (code) => {
            if (code !== 0) return;
            // force: same path, new contents — Hyprland only re-reads the file
            // when the keyword is set again.
            root.applied = "";
            root.push(root.appShaderPath);
        }
    }

    // Called by DisplaySettings when it changes the global (no-profile) shader.
    function setBase(path, force) {
        root.baseShader = path;
        if (force === true && root.governing.length === 0) {
            root.applied = "";   // contents changed under an unchanged path
        }
        // Persisted, so the choice survives a shell restart. It was held only in
        // memory before: save() wrote enabled/livePreview/profiles and nothing
        // else, so every reload came back with no shader selected and there was
        // nothing for startup to restore.
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
                // Restore the chosen shader and put it back on screen. Without
                // this the picker showed "none" after every restart even though
                // one had been selected, because the choice was never written.
                // reapply() rather than a bare assignment: baseShader alone only
                // changes what SHOULD be applied, it does not push it.
                if (typeof d.baseShader === "string" && d.baseShader.length > 0) {
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
























