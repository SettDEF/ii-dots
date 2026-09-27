pragma Singleton
pragma ComponentBehavior: Bound

// Searchable index behind the settings search box.
//
// Settings rows are parsed from the page SOURCE rather than by letting each
// row register itself: settings.qml loads exactly one page at a time through
// a single Loader, so rows on pages you have not visited would never register
// and would be invisible to search. Instantiating all 8 pages up front to
// force registration is worse — pages own Processes and file scans, and
// creating them off-screen would fire those side effects for no reason.
//
// On top of the settings rows the index also carries effects, shaders,
// runnable IPC actions and keybinds, so one box answers "where is that
// setting", "what is that effect called" and "which key does that".
//
// A row the parser misses simply doesn't appear in search — it degrades
// quietly rather than breaking the page.

import qs.modules.common
import qs.modules.common.functions
import QtQuick
import Quickshell
import Quickshell.Io
import Qt.labs.folderlistmodel
import QtQml.Models

Singleton {
    id: root

    // [{ file, section, title, desc, kind }] — `file` is a page file name, or
    // "@effect" / "@shader" / "@action" / "@keybind" for the other sources.
    property var entries: []
    property bool ready: false

    readonly property string settingsDir:
        Quickshell.env("HOME") + "/.config/quickshell/ii/modules/settings"
    readonly property string packDir: Quickshell.env("HOME") + "/.config/hypr/shaderpacks"
    readonly property string shaderDir: Quickshell.env("HOME") + "/.config/hypr/shaders"

    // file name → the page entry settings.qml uses. Set by settings.qml so the
    // index doesn't have to hardcode the page list twice.
    property var pageForFile: ({})

    // Leaf widgets the user can actually act on. ConfigRow is a LAYOUT that
    // wraps these, so it is deliberately absent — treating it as a row
    // swallowed the real controls nested inside it.
    readonly property var widgetKinds: [
        "ConfigSwitch", "ConfigSpinBox", "ConfigSelectionArray",
        "ConfigSlider", "MaterialTextField", "MaterialTextArea",
        "ConfigColorPicker", "StyledComboBox", "SegmentedButtons",
        "RippleButtonWithIcon"
    ]

    property var perFile: ({})        // page file → parsed rows
    property var effectRows: ({})     // effect path → entry
    property var shaderRows: []
    property var actionRows: []
    property var keybindRows: []

    function publish() {
        const out = [];
        for (const f in root.perFile) {
            const rows = root.perFile[f];
            for (let i = 0; i < rows.length; ++i) out.push(rows[i]);
        }
        // Effects, shaders, actions and keybinds sit alongside the settings
        // rows, so "balatro" or "screenshot" finds them without you knowing
        // which panel owns them.
        for (const k in root.effectRows) out.push(root.effectRows[k]);
        for (let i = 0; i < root.shaderRows.length; ++i) out.push(root.shaderRows[i]);
        for (let i = 0; i < root.actionRows.length; ++i) out.push(root.actionRows[i]);
        for (let i = 0; i < root.keybindRows.length; ++i) out.push(root.keybindRows[i]);
        root.entries = out;
        root.ready = out.length > 0;
    }

    Timer {
        id: publishDebounce
        interval: 90
        onTriggered: root.publish()
    }

    function noteFile(name, rows) {
        const next = Object.assign({}, root.perFile);
        next[name] = rows;
        root.perFile = next;
        publishDebounce.restart();
    }

    function noteEffectRow(path, row) {
        const next = Object.assign({}, root.effectRows);
        if (row === null) delete next[path];
        else next[path] = row;
        root.effectRows = next;
        publishDebounce.restart();
    }

    // FolderListModel lists a directory ONCE — it does not watch for files
    // being added or removed. Clearing `folder` and setting it back forces a
    // re-read, and because the per-pack models live inside this one's
    // delegates, rebuilding the top level re-reads every pack too.
    function refresh() {
        ipcProbe.running = true;
        bindProbe.running = true;
        pageFiles.folder = "";
        packDirs.folder = "";
        fragFiles.folder = "";
        Qt.callLater(() => {
            pageFiles.folder = "file://" + root.settingsDir;
            packDirs.folder = "file://" + root.packDir;
            fragFiles.folder = "file://" + root.shaderDir;
        });
    }

    // Brace-depth walk over a page's source. Sections and rows are both found
    // by depth rather than by regexing whole blocks, which keeps nested
    // widgets (a ConfigSpinBox inside a ConfigRow) attached to the right
    // section and stops a tooltip body from being mistaken for a row title.
    function parsePage(fileName, src) {
        const widgetRe = new RegExp("^(" + root.widgetKinds.join("|") + ")\\s*\\{");
        const titleRe = /^(?:text|title):\s*(?:Translation\.tr\()?"([^"]+)"/;
        const sectionRe = /^ContentSection\s*\{/;
        const labelRe = /^StyledText\s*\{/;
        const maxLabel = 44;

        const lines = String(src).split("\n");
        const out = [];
        let depth = 0;
        let secDepth = -1;
        let section = "";
        const stack = [];

        for (let i = 0; i < lines.length; ++i) {
            const line = lines[i];
            const s = line.trim();

            if (sectionRe.test(s)) { secDepth = depth; section = ""; }
            if (secDepth >= 0 && depth === secDepth + 1 && section.length === 0) {
                const m = titleRe.exec(s);
                if (m) {
                    section = m[1];
                    // A heading is findable in its own right. `file` matters:
                    // without it pageIndexOf returns -1 and the result is inert
                    // — found, ranked first, and dead on click.
                    out.push({ file: fileName, section: section, title: section,
                               desc: "", kind: "section" });
                }
            }

            const wm = widgetRe.exec(s);
            if (wm) stack.push({ depth: depth, rec: { section: section, title: "",
                                                      desc: "", kind: wm[1] } });

            // A short StyledText is the label for the control beside it — the
            // pattern "Time zone" + StyledComboBox. The control carries no text
            // of its own, so without this the row is reachable by nothing.
            // Length-capped, or the explanatory paragraphs become results too.
            if (labelRe.test(s)) stack.push({ depth: depth, label: true,
                rec: { section: section, title: "", desc: "", kind: "label" } });

            if (stack.length > 0) {
                const m = titleRe.exec(s);
                if (m) {
                    const top = stack[stack.length - 1];
                    if (top.rec.title.length === 0 && depth === top.depth + 1)
                        top.rec.title = m[1];
                    else if (top.rec.desc.length === 0 && depth > top.depth + 1)
                        top.rec.desc = m[1];      // StyledToolTip body
                }
            }

            // Count braces AFTER inspecting the line, so a widget's opening
            // brace is not counted as being inside itself.
            for (let c = 0; c < line.length; ++c) {
                if (line[c] === "{") depth++;
                else if (line[c] === "}") depth--;
            }

            while (stack.length > 0 && depth <= stack[stack.length - 1].depth) {
                const done = stack.pop();
                const t = done.rec.title;
                if (t.length > 0 && !(done.label && t.length > maxLabel)) {
                    done.rec.file = fileName;
                    out.push(done.rec);
                }
            }
            if (secDepth >= 0 && depth <= secDepth) secDepth = -1;
        }
        return out;
    }

    // Ranked search. Title matches beat section matches beat description
    // matches, and a prefix match beats a mid-word one, so typing "vol" puts
    // "Volume limit" above a row that merely mentions volume in its tooltip.
    // Two keys per entry, because one cannot do both jobs. The title alone
    // ranks properly — "scrollbar" should find "Scroll bars", not every row
    // inside that section. The combined one catches a query whose words are
    // split across fields: "keyboard layout" is the heading "Keyboard" plus the
    // row "Session layout", and matching field-by-field sees neither.
    //
    // Each is doubled with its spaces removed, which is what lets "scrollbar"
    // reach "Scroll bars" at all.
    function _sq(t) { return t + " " + t.replace(/\s+/g, ""); }

    readonly property var haystacks: {
        const out = [];
        for (let i = 0; i < root.entries.length; ++i) {
            const e = root.entries[i];
            const title = e.title ?? "";
            const all = [title, e.section ?? "", e.desc ?? "",
                         String(e.file ?? "").replace(/Config\.qml$|\.qml$/, "")]
                        .filter(x => x.length > 0).join(" ");
            out.push({
                entry: e,
                titleKey: Fuzzy.prepare(root._sq(title)),
                allKey: Fuzzy.prepare(root._sq(all))
            });
        }
        return out;
    }

    function search(query, limit) {
        const q = String(query ?? "").trim();
        if (q.length === 0) return [];

        // fuzzysort, the matcher the launcher already uses: subsequence
        // matching, so a query need not be contiguous and a typo costs rank
        // rather than every result. The 250 penalty is what keeps a section
        // match below a title match without hiding it.
        const hits = Fuzzy.go(q, root.haystacks, {
            all: false,
            keys: ["titleKey", "allKey"],
            scoreFn: a => Math.max(a[0] ? a[0].score : -9999,
                                   a[1] ? a[1].score - 250 : -9999)
        });
        const out = [];
        for (let i = 0; i < hits.length && out.length < (limit ?? 12); ++i)
            out.push(hits[i].obj.entry);
        return out;
    }

    function pageIndexOf(entry) {
        const p = root.pageForFile[entry.file];
        return p === undefined ? -1 : p;
    }

    // ── Runnable IPC actions ────────────────────────────────────────────
    Process {
        id: ipcProbe
        command: ["bash", "-c", "qs -c ii ipc show 2>/dev/null"]
        running: true
        stdout: StdioCollector {
            onStreamFinished: {
                const out = [];
                const lines = String(text).split("\n");
                let target = "";
                for (let i = 0; i < lines.length; ++i) {
                    const t = /^target\s+(\S+)/.exec(lines[i]);
                    if (t) { target = t[1]; continue; }
                    const f = /^\s+function\s+(\w+)\(/.exec(lines[i]);
                    if (f && target.length > 0) {
                        out.push({ file: "@action", section: target,
                                   title: target + " " + f[1],
                                   desc: "Run this command",
                                   target: target, func: f[1] });
                    }
                }
                root.actionRows = out;
                publishDebounce.restart();
            }
        }
    }

    // ── Keybinds ────────────────────────────────────────────────────────
    Process {
        id: bindProbe
        command: ["hyprctl", "binds", "-j"]
        running: true
        stdout: StdioCollector {
            onStreamFinished: {
                let arr;
                try { arr = JSON.parse(text || "[]"); } catch (e) { return; }
                // Hyprland reports the modifier set as a bitmask.
                const MODS = [[64, "Super"], [8, "Alt"], [4, "Ctrl"], [1, "Shift"]];
                const seen = ({});
                const out = [];
                for (let i = 0; i < arr.length; ++i) {
                    const b = arr[i];
                    // Only ~23 of 344 binds carry a description. The rest are
                    // still worth finding — by what they RUN — so fall back to
                    // the dispatcher argument.
                    let label = String(b.description || "");
                    if (label.length === 0) {
                        const arg = String(b.arg || "").trim();
                        if (arg.length === 0) continue;
                        label = arg.length > 46 ? arg.slice(0, 46) + "…" : arg;
                    }
                    let mods = "";
                    for (let m = 0; m < MODS.length; ++m)
                        if (b.modmask & MODS[m][0]) mods += MODS[m][1] + "+";
                    const combo = mods + (b.key || b.keycode || "?");
                    const key = combo + "|" + label;
                    if (seen[key]) continue;
                    seen[key] = true;
                    out.push({ file: "@keybind", section: combo, title: label,
                               desc: (b.dispatcher || "") + " " + (b.arg || "") });
                }
                root.keybindRows = out;
                publishDebounce.restart();
            }
        }
    }

    // ── Effects, scanned read-only ──────────────────────────────────────
    // Deliberately NOT via AppDisplay: that singleton owns
    // decoration:screen_shader, and instantiating it inside the settings
    // process would give two processes conflicting opinions about which
    // shader is live.
    FolderListModel {
        id: packDirs
        folder: "file://" + root.packDir
        showFiles: false
        showDirs: true
        showDotAndDotDot: false
    }

    Instantiator {
        model: packDirs
        delegate: QtObject {
            id: packDirItem
            required property string filePath

            property FolderListModel files: FolderListModel {
                folder: "file://" + packDirItem.filePath
                nameFilters: ["*.json"]
                showDirs: false
                showDotAndDotDot: false
            }

            property Instantiator entries: Instantiator {
                model: packDirItem.files
                delegate: QtObject {
                    id: effFile
                    required property string filePath
                    required property string fileName

                    property FileView view: FileView {
                        path: "file://" + effFile.filePath
                        watchChanges: true
                        onFileChanged: reload()
                        onLoaded: {
                            let j;
                            try { j = JSON.parse(view.text() || "{}"); } catch (e) { return; }
                            if (!j.kind) return;
                            root.noteEffectRow(effFile.filePath, {
                                file: "@effect",
                                section: String(packDirItem.filePath).split("/").pop(),
                                title: j.name ?? effFile.fileName.replace(/\.json$/, ""),
                                desc: j.desc ?? "",
                                kind: j.kind
                            });
                        }
                        onLoadFailed: root.noteEffectRow(effFile.filePath, null)
                    }
                }
            }
        }
    }

    // ── Whole-screen shaders ────────────────────────────────────────────
    FolderListModel {
        id: fragFiles
        folder: "file://" + root.shaderDir
        nameFilters: ["*.frag", "*.glsl"]
        showDirs: false
        showDotAndDotDot: false
        onCountChanged: {
            const out = [];
            for (let i = 0; i < count; ++i) {
                const n = get(i, "fileName");
                out.push({ file: "@shader", section: "Screen shaders",
                           title: String(n).replace(/\.(frag|glsl)$/, ""),
                           desc: "Whole-screen shader", kind: "shader" });
            }
            root.shaderRows = out;
            publishDebounce.restart();
        }
    }

    // ── Settings pages ──────────────────────────────────────────────────
    FolderListModel {
        id: pageFiles
        folder: "file://" + root.settingsDir
        nameFilters: ["*.qml"]
        showDirs: false
        showDotAndDotDot: false
    }

    Instantiator {
        model: pageFiles
        delegate: QtObject {
            id: pageItem
            required property string filePath
            required property string fileName

            property FileView view: FileView {
                // Explicit file:// — Qt.resolvedUrl resolves an absolute path
                // against the QML base URL, yielding qs:/home/... which
                // FileView cannot read.
                path: "file://" + pageItem.filePath
                watchChanges: true
                onFileChanged: reload()
                onLoaded: root.noteFile(pageItem.fileName,
                                        root.parsePage(pageItem.fileName, view.text() || ""))
                onLoadFailed: root.noteFile(pageItem.fileName, [])
            }
        }
    }
}

