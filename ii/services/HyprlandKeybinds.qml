pragma Singleton
pragma ComponentBehavior: Bound

import qs.modules.common
import qs.modules.common.functions
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland

/**
 * The keybinds behind the cheatsheet (Super+/), from `hyprctl binds -j`.
 *
 * On a Lua config every bind reports dispatcher "__lua" with an opaque arg, so
 * the live data knows which KEYS are bound but not what they do. `description`
 * is all that is left, read as "Section/Label"; no description means plumbing
 * and is dropped, which keeps the Super-interrupt binds out without a blocklist.
 *
 * The old conf-file parse stays as a fallback and the RICHER source wins —
 * an unannotated config would otherwise lose most of its cheatsheet.
 */
Singleton {
    id: root

    /// Floor, so two annotated binds do not beat an absent file.
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

    // The richer source wins.
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

                // Bitmask. Ordered as written, not by bit value.
                const MODS = [[64, "Super"], [4, "Ctrl"], [8, "Alt"], [1, "Shift"]];
                const sections = ({});
                const order = [];
                const seen = ({});

                for (const b of arr) {
                    const desc = String(b.description ?? "").trim();
                    // No description => plumbing.
                    if (desc.length === 0) continue;

                    const slash = desc.indexOf("/");
                    const sectionName = slash > 0 ? desc.slice(0, slash).trim()
                                                  : root.defaultSectionName;
                    const label = slash > 0 ? desc.slice(slash + 1).trim() : desc;

                    const mods = [];
                    for (const [bit, name] of MODS)
                        if (b.modmask & bit) mods.push(name);
                    // One key to a reader.
                    let key = String(b.key || b.keycode || "?");
                    if (key === "Super_L" || key === "Super_R") key = "Super";

                    // A bind on several keys appears once.
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
                        // Shape compatibility only; "__lua" is not worth showing.
                        dispatcher: String(b.dispatcher ?? ""),
                        params: String(b.arg ?? ""),
                        comment: label
                    });
                }

                // Flat: the cheatsheet repacks into columns itself.
                root.liveKeybinds = { children: order.map(n => sections[n]) };
            }
        }
    }

    // Fallback, for configs whose binds carry no descriptions.
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
