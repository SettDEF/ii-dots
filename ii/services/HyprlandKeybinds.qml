pragma Singleton
pragma ComponentBehavior: Bound

import qs.modules.common
import qs.modules.common.functions
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland

/**
 * The keybinds behind the cheatsheet (Super+/).
 *
 * Read from `hyprctl binds -j` — what is ACTUALLY bound at this moment —
 * rather than from a config file. The file was the original source and it was
 * the wrong one for three reasons: it had to be written a second time by hand
 * next to the real binds and drifted the moment anyone forgot; its parser is a
 * Python script with a venv shebang, so a missing $ILLOGICAL_IMPULSE_VIRTUAL_ENV
 * showed an EMPTY cheatsheet with nothing to explain it; and it does not follow
 * `source =`, so binds in any included file were invisible.
 *
 * The catch, and the reason the file is still here as a fallback: on a Lua
 * config every bind reports `dispatcher: "__lua"` with an opaque callback id
 * for `arg`, so the live data knows which KEYS are bound but not what they do.
 * The `description` field is the only human-readable thing left. So:
 *
 *   hl.bind("SUPER + A", hl.dsp.global("quickshell:sidebarLeftToggle"),
 *           { description = "Shell/Left sidebar" })
 *
 * Text before the first "/" is the section, the rest is the label. No slash
 * means the bind lands in a general section; no description at all means the
 * bind is plumbing and is left out, which is exactly what keeps the ~68
 * transparent Super-interrupt binds off the cheatsheet without a blocklist.
 *
 * A config whose binds carry no descriptions would get an almost empty
 * cheatsheet, which would be a regression for anyone upgrading. So the two
 * sources are COMPARED and the richer one wins: measured on a config with
 * descriptions on only 23 of 530 binds, the live path would have replaced a
 * full file-derived list with 23 unsectioned entries. Whichever source knows
 * about more binds is the one that gets shown.
 */
Singleton {
    id: root

    /// Floor for the live path, so a config with two annotated binds does not
    /// beat an absent file on a technicality.
    property int minLiveBinds: 8
    /// Section for binds whose description carries no "Section/" prefix.
    property string defaultSectionName: "Keybinds"

    property string keybindParserPath: FileUtils.trimFileProtocol(`${Directories.scriptPath}/hyprland/get_keybinds.py`)
    property string defaultKeybindConfigPath: FileUtils.trimFileProtocol(`${Directories.config}/hypr/hyprland/keybinds.conf`)
    property string userKeybindConfigPath: FileUtils.trimFileProtocol(`${Directories.config}/hypr/custom/keybinds.conf`)

    property var defaultKeybinds: ({ children: [] })
    property var userKeybinds: ({ children: [] })
    property var liveKeybinds: ({ children: [] })

    readonly property int liveBindCount: {
        let n = 0;
        for (const s of (liveKeybinds.children ?? [])) n += root._countDeep(s);
        return n;
    }
    readonly property var fileKeybinds: ({
        children: [
            ...(defaultKeybinds.children ?? []),
            ...(userKeybinds.children ?? []),
        ]
    })
    readonly property int fileBindCount: {
        let n = 0;
        for (const s of (fileKeybinds.children ?? [])) n += root._countDeep(s);
        return n;
    }

    function _countDeep(section) {
        let n = (section.keybinds ?? []).length;
        for (const c of (section.children ?? [])) n += root._countDeep(c);
        return n;
    }

    // The richer source wins. An annotated config beats its own stale file;
    // an unannotated one keeps the file it has always had.
    readonly property bool usingLiveBinds: root.liveBindCount >= root.minLiveBinds
        && root.liveBindCount >= root.fileBindCount

    property var keybinds: root.usingLiveBinds ? root.liveKeybinds : root.fileKeybinds

    function refresh() {
        bindProbe.running = false;
        bindProbe.running = true;
        getDefaultKeybinds.running = true;
        getUserKeybinds.running = true;
    }

    Connections {
        target: Hyprland
        function onRawEvent(event) {
            if (event.name == "configreloaded") root.refresh();
        }
    }

    Process {
        id: bindProbe
        running: true
        command: ["hyprctl", "binds", "-j"]
        stdout: StdioCollector {
            onStreamFinished: {
                let arr;
                try { arr = JSON.parse(text || "[]"); } catch (e) { return; }

                // Hyprland reports the modifier set as a bitmask. Ordered as
                // they are conventionally written, not by bit value.
                const MODS = [[64, "Super"], [4, "Ctrl"], [8, "Alt"], [1, "Shift"]];
                const sections = ({});
                const order = [];
                const seen = ({});

                for (const b of arr) {
                    const desc = String(b.description ?? "").trim();
                    // No description => plumbing. This is what keeps the
                    // transparent Super-interrupt binds out without naming them.
                    if (desc.length === 0) continue;

                    const slash = desc.indexOf("/");
                    const sectionName = slash > 0 ? desc.slice(0, slash).trim()
                                                  : root.defaultSectionName;
                    const label = slash > 0 ? desc.slice(slash + 1).trim() : desc;

                    const mods = [];
                    for (const [bit, name] of MODS)
                        if (b.modmask & bit) mods.push(name);
                    // Super_L and Super_R are the same key to a reader, so
                    // they collapse to one row rather than two identical ones.
                    let key = String(b.key || b.keycode || "?");
                    if (key === "Super_L" || key === "Super_R") key = "Super";

                    // A bind repeated across several keys should appear once.
                    const dedupe = mods.join("+") + "|" + key + "|" + desc;
                    if (seen[dedupe]) continue;
                    seen[dedupe] = true;

                    if (!sections[sectionName]) {
                        sections[sectionName] = { name: sectionName, keybinds: [], children: [] };
                        order.push(sectionName);
                    }
                    sections[sectionName].keybinds.push({
                        mods: mods,
                        key: key,
                        // Kept for shape compatibility with the file parser;
                        // "__lua" is not worth showing anyone.
                        dispatcher: String(b.dispatcher ?? ""),
                        params: String(b.arg ?? ""),
                        comment: label
                    });
                }

                // The cheatsheet renders TWO levels: each top-level child is
                // a COLUMN, and that column's children are the sections that
                // actually hold binds. A flat list of sections renders as
                // nothing at all, silently — the outer Repeater finds them and
                // the inner one finds no children.
                //
                // So pack the sections into columns, greedily, keeping them
                // near equal in height rather than letting one column carry
                // everything.
                const built = order.map(n => sections[n]);
                const targetColumns = Math.max(1, Math.min(3, built.length));
                const perColumn = Math.max(1, Math.ceil(
                    built.reduce((n, s) => n + s.keybinds.length + 2, 0) / targetColumns));

                // Break AFTER a section fills the column, not before adding
                // one. Testing first means a section larger than the target
                // takes a column of its own AND pushes the next one into a
                // fresh column, which turned five sections into four ragged
                // columns instead of three even ones.
                const columns = [];
                let current = null;
                let used = 0;
                for (const sec of built) {
                    if (current === null) {
                        current = { name: "", keybinds: [], children: [] };
                        columns.push(current);
                        used = 0;
                    }
                    current.children.push(sec);
                    used += sec.keybinds.length + 2;    // +2 for the heading
                    if (used >= perColumn) current = null;
                }

                root.liveKeybinds = { children: columns };
            }
        }
    }

    // ── Fallback: the old file parse ────────────────────────────────────
    // Still run, so that a config without bind descriptions keeps working.
    Process {
        id: getDefaultKeybinds
        running: true
        command: [root.keybindParserPath, "--path", root.defaultKeybindConfigPath]
        stdout: SplitParser {
            onRead: data => {
                try { root.defaultKeybinds = JSON.parse(data) }
                catch (e) { console.error("[HyprlandKeybinds] default keybinds:", e) }
            }
        }
    }

    Process {
        id: getUserKeybinds
        running: true
        command: [root.keybindParserPath, "--path", root.userKeybindConfigPath]
        stdout: SplitParser {
            onRead: data => {
                try { root.userKeybinds = JSON.parse(data) }
                catch (e) { console.error("[HyprlandKeybinds] user keybinds:", e) }
            }
        }
    }
}
