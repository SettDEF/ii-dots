pragma Singleton
pragma ComponentBehavior: Bound

import qs.modules.common
import qs.modules.common.functions
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland

/**
 * Keyboard-layout awareness for the keybind cheatsheet.
 *
 *  - Detects the layout Hyprland currently has active (live, via the
 *    `activelayout` event) and the list configured in `input:kb_layout`.
 *  - Lets the user override that pick manually (`manualLayout`).
 *  - Resolves `code:NN` keybinds to real key labels by compiling the
 *    effective layout's XKB keymap at runtime (scripts/hyprland/get_keymap.py),
 *    so the data is always accurate instead of a baked-in table.
 *
 * Usage:  KeyboardLayout.resolveKey("code:24")  ->  "Q" / "A" / ...
 */
Singleton {
    id: root

    readonly property string keymapScript: FileUtils.trimFileProtocol(`${Directories.scriptPath}/hyprland/get_keymap.py`)

    // Short codes from input:kb_layout, e.g. ["us", "de"]. Aligned variants.
    property var availableLayouts: ["us"]
    property var availableVariants: [""]

    // What Hyprland reports active right now.
    property string detectedName: ""                       // "English (US)"
    property string detectedLayout: "us"                    // resolved short code

    // Manual override; "" = follow auto-detection.
    property string manualLayout: ""
    readonly property bool isAuto: manualLayout === ""
    readonly property string effectiveLayout: isAuto ? detectedLayout : manualLayout

    // Hyprland keycode -> display label, for the effective layout.
    property var codeToKey: ({})
    property bool ready: false

    // ── auto-detection: human keymap name -> short code ───────────────
    readonly property var _nameToCode: ({
        "english (us)": "us", "english (uk)": "gb", "english (gb)": "gb",
        "german": "de", "french": "fr", "spanish": "es", "italian": "it",
        "portuguese": "pt", "russian": "ru", "polish": "pl", "swedish": "se",
        "norwegian": "no", "finnish": "fi", "danish": "dk", "dutch": "nl",
        "czech": "cz", "slovak": "sk", "hungarian": "hu", "turkish": "tr",
        "swiss": "ch", "belgian": "be", "canadian": "ca", "japanese": "jp",
        "ukrainian": "ua", "greek": "gr", "romanian": "ro", "croatian": "hr",
    })
    // Tidy a few named keysyms the keymap returns into compact labels.
    readonly property var _pretty: ({
        "ampersand": "&", "eacute": "é", "quotedbl": "\"", "apostrophe": "'",
        "parenleft": "(", "parenright": ")", "minus": "-", "egrave": "è",
        "underscore": "_", "ccedilla": "ç", "agrave": "à", "equal": "=",
        "bracketleft": "[", "bracketright": "]", "semicolon": ";", "comma": ",",
        "period": ".", "slash": "/", "backslash": "\\", "grave": "`",
        "section": "§", "ssharp": "ß", "udiaeresis": "ü", "odiaeresis": "ö",
        "adiaeresis": "ä", "plus": "+", "numbersign": "#", "less": "<",
    })

    function _resolveName(name) {
        const n = (name ?? "").toLowerCase()
        if (n === "") return root.availableLayouts[0] ?? "us"
        for (const frag in root._nameToCode)
            if (n.indexOf(frag) >= 0) return root._nameToCode[frag]
        for (const code of root.availableLayouts)
            if (n.indexOf(code) >= 0) return code
        return root.availableLayouts[0] ?? "us"
    }

    // ── public API ────────────────────────────────────────────────────
    function setManualLayout(code) { root.manualLayout = code ?? "" }

    // Cycle the badge: Auto -> each configured layout -> Auto.
    function cycleLayout() {
        const opts = [""].concat(root.availableLayouts)
        const i = Math.max(0, opts.indexOf(root.manualLayout))
        root.manualLayout = opts[(i + 1) % opts.length]
    }

    // Turn a raw keybind key into a layout-correct display label.
    function resolveKey(raw) {
        if (typeof raw !== "string") return raw
        const m = raw.match(/^code:(\d+)$/)
        if (!m) return raw
        const label = root.codeToKey[m[1]]
        return (label && label.length) ? label : raw
    }

    // ── keymap loading ─────────────────────────────────────────────────
    function _variantFor(code) {
        const i = root.availableLayouts.indexOf(code)
        return (i >= 0 && i < root.availableVariants.length) ? root.availableVariants[i] : ""
    }
    function reloadKeymap() {
        keymapProc.running = false
        keymapProc.command = [root.keymapScript,
            "--layout", root.effectiveLayout,
            "--variant", root._variantFor(root.effectiveLayout)]
        keymapProc.running = true
    }
    onEffectiveLayoutChanged: reloadKeymap()

    Process {
        id: keymapProc
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const j = JSON.parse(text.trim())
                    if (j.ok && j.codeToKey) {
                        const m = ({})
                        for (const c in j.codeToKey) {
                            let v = j.codeToKey[c]
                            if (root._pretty[v] !== undefined) v = root._pretty[v]
                            else if (v.length === 1) v = v.toUpperCase()   // q -> Q
                            m[c] = v
                        }
                        root.codeToKey = m
                    }
                } catch (e) {
                    console.error("[KeyboardLayout] keymap parse failed:", e)
                }
                root.ready = true
            }
        }
    }

    // ── All installed XKB layouts (for the picker popup) ──────────────
    // Flat list of every (layout, variant) combo. Used by KeyboardLayoutPicker.
    //
    // Reads evdev.xml + evdev.extras.xml via `iris`, not evdev.lst via the
    // old python script: the XML carries the extras layouts and ISO-639 codes
    // the .lst has not (753 entries vs 598), and it returns in ~4ms not ~36ms.
    // Absolute path because a Process does not inherit the login PATH.
    property var allLayouts: []
    readonly property string allLayoutsScript: FileUtils.trimFileProtocol(`${Directories.home}/.local/bin/iris`)
    Process {
        id: allLayoutsProc
        running: true
        command: [root.allLayoutsScript, "layouts", "--json"]
        stdout: StdioCollector {
            onStreamFinished: {
                try { root.allLayouts = JSON.parse(text) }
                catch (e) { console.error("[KeyboardLayout] allLayouts parse:", e) }
            }
        }
    }

    // ── Persisting a layout list to the Hyprland config ──────────────────
    //
    // This USED to write only `hyprland/shellOverrides/main.conf` and then
    // `hyprctl reload`. Since the Lua migration that file is dead: the live
    // config is `hyprland.lua`, which does
    //     require("lua.hyprland.shellOverrides.main")
    // i.e. it reads `lua/hyprland/shellOverrides/main.lua`. Only the retired
    // `hyprland.conf` ever sourced the .conf. So every pick wrote a file
    // nothing read, reloaded, and switched to an index that was never added —
    // all steps "succeeding" while the layout never changed. (The .conf on
    // disk still said `us,at` while Hyprland was running plain `us`.)
    //
    // Both files are written so the two configs can't drift apart again if
    // the .conf one is ever restored; the .lua is the one that takes effect.
    // `hl.config` types: kb_layout/kb_variant are STRINGS — a wrongly typed
    // field is silently ignored while the request still answers `ok`.
    //
    // Callers must pass strings already validated by `xkbcli compile-keymap`.
    function _persistCmd(layoutStr, variantStr) {
        const luaPath  = "~/.config/hypr/lua/hyprland/shellOverrides/main.lua"
        const confPath = "~/.config/hypr/hyprland/shellOverrides/main.conf"
        return (
            `echo -e '-- Written by quickshell (KeyboardLayout.qml). Edits are overwritten.\\n`
            + `hl.config({\\n    input = {\\n`
            + `        kb_layout = "${layoutStr}",\\n`
            + `        kb_variant = "${variantStr}",\\n`
            + `    },\\n})' > ${luaPath} && `
            + `echo -e 'input {\\n    kb_layout = ${layoutStr}\\n    kb_variant = ${variantStr}\\n}' > ${confPath} && `
            // Apply live through the `eval` request rather than `hyprctl
            // reload`: reload re-runs the whole config (re-applying monitors,
            // shaders, device rules), which is a lot of collateral for a
            // keyboard change. `hyprctl keyword` is NOT an option here — it
            // answers `unknown request` on the Lua config.
            + `hyprctl eval 'hl.config({ input = { kb_layout = "${layoutStr}", kb_variant = "${variantStr}" } })' >/dev/null`
        )
    }

    // Switch Hyprland to (layoutCode, variantCode). If the combo isn't in
    // input:kb_layout/kb_variant yet, it is appended and persisted first.
    function setLayout(layoutCode, variantCode) {
        if (!layoutCode) return
        const v = variantCode || ""
        // Pad current variants list to layouts length so positional indexes line up.
        let layouts = root.availableLayouts.slice()
        let variants = root.availableVariants.slice()
        while (variants.length < layouts.length) variants.push("")
        let idx = -1
        for (let i = 0; i < layouts.length; i++) {
            if (layouts[i] === layoutCode && (variants[i] || "") === v) { idx = i; break }
        }
        let cmd
        if (idx < 0) {
            layouts.push(layoutCode); variants.push(v); idx = layouts.length - 1
            const layoutStr = layouts.join(",")
            const variantStr = variants.join(",")
            cmd =
                `if xkbcli compile-keymap --layout='${layoutStr}' `
                + `--variant='${variantStr}' >/dev/null 2>&1; then `
                +   root._persistCmd(layoutStr, variantStr) + ` && `
                +   `hyprctl switchxkblayout all ${idx} >/dev/null; `
                + `else `
                +   `notify-send -u critical -a 'Keyboard layout' `
                +   `'Layout not supported by XKB' `
                +   `'${layoutStr} · the new layout was not added'; `
                + `fi`
        } else {
            cmd = `hyprctl switchxkblayout all ${idx} >/dev/null`
        }
        applyKbProc.running = false
        applyKbProc.command = ["bash", "-c", cmd]
        applyKbProc.running = true
        // Re-read configured layouts after switching so chips refresh.
        Qt.callLater(() => optProc.running = true)
    }
    Process { id: applyKbProc }

    // Remove the layout at `index` from kb_layout / kb_variant.
    // Refuses to remove the last remaining layout.
    function removeLayout(index) {
        if (index < 0 || index >= root.availableLayouts.length) return
        if (root.availableLayouts.length <= 1) {
            Quickshell.execDetached([
                "notify-send", "-u", "low", "-a", "Keyboard layout",
                "Can't remove the only layout"
            ])
            return
        }
        let layouts = root.availableLayouts.slice()
        let variants = root.availableVariants.slice()
        while (variants.length < layouts.length) variants.push("")
        layouts.splice(index, 1)
        variants.splice(index, 1)
        const layoutStr = layouts.join(",")
        const variantStr = variants.join(",")
        const cmd =
            `if xkbcli compile-keymap --layout='${layoutStr}' `
            + `--variant='${variantStr}' >/dev/null 2>&1; then `
            +   root._persistCmd(layoutStr, variantStr) + `; `
            + `else `
            +   `notify-send -u critical -a 'Keyboard layout' `
            +   `'Removing layout failed XKB validation'; `
            + `fi`
        applyKbProc.running = false
        applyKbProc.command = ["bash", "-c", cmd]
        applyKbProc.running = true
        Qt.callLater(() => optProc.running = true)
    }

    // ── Hyprland queries ───────────────────────────────────────────────
    Process {
        id: optProc                              // configured layouts/variants
        command: ["bash", "-c",
            "hyprctl getoption input:kb_layout -j; echo '<SEP>'; hyprctl getoption input:kb_variant -j"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const parts = text.split("<SEP>")
                    const lay = (JSON.parse(parts[0]).str ?? "us")
                    const vari = (JSON.parse(parts[1] ?? "{}").str ?? "")
                    const layouts = lay.split(",").map(s => s.trim()).filter(s => s.length)
                    root.availableLayouts = layouts.length ? layouts : ["us"]
                    // Hyprland uses the literal token "[[EMPTY]]" to represent
                    // an empty variant slot — normalise it to "" so chip
                    // comparisons against picker entries work.
                    root.availableVariants = vari.split(",").map(s => {
                        const t = s.trim()
                        return t === "[[EMPTY]]" ? "" : t
                    })
                } catch (e) {
                    root.availableLayouts = ["us"]
                    root.availableVariants = [""]
                }
                devicesProc.running = true
            }
        }
    }
    Process {
        id: devicesProc                          // currently active keymap name
        command: ["hyprctl", "devices", "-j"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const d = JSON.parse(text.trim())
                    const kbs = d.keyboards ?? []
                    const kb = kbs.find(k => k.main) ?? kbs[0]
                    if (kb && kb.active_keymap) {
                        root.detectedName = kb.active_keymap
                        root.detectedLayout = root._resolveName(kb.active_keymap)
                    }
                } catch (e) {}
                root.reloadKeymap()              // covers the no-change case
            }
        }
    }

    Connections {
        target: Hyprland
        function onRawEvent(event) {
            if (event.name === "activelayout") {
                const data = event.data ?? ""
                const name = data.substring(data.indexOf(",") + 1)
                root.detectedName = name
                root.detectedLayout = root._resolveName(name)
            } else if (event.name === "configreloaded") {
                optProc.running = true           // kb_layout may have changed
            }
        }
    }

    Component.onCompleted: optProc.running = true
}
