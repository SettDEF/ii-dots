pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Hyprland

/**
 * Old-style Hyprland dispatch strings → the Lua API of Hyprland 0.56+.
 *
 * With a Lua config, `hyprctl dispatch` evaluates its argument AS LUA:
 * `dispatch workspace 3` is read as `hl.dispatch(workspace 3)`, which is a
 * syntax error. Every dispatch in this shell was written in the old syntax, so
 * all of them silently stopped working — clicking a workspace, dragging a
 * window between workspaces, closing a window from the bar.
 *
 * Rather than rewrite ~50 call sites in a dialect that may keep moving, they
 * all go through here and this is the single place that knows the mapping.
 */
Singleton {
    id: root

    /// Accepts an old-style dispatch string ("workspace 3", "closewindow
    /// address:0x…") and issues the equivalent Lua dispatcher.
    function run(cmd) {
        const lua = root.toLua(String(cmd).trim());
        if (lua.length === 0)
            return;
        Hyprland.dispatch(lua);
    }

    /// Exposed for callers that need the expression itself (e.g. to embed in
    /// a shell command). Returns "" when the input can't be translated.
    /// Set a config value, the `hyprctl keyword` replacement.
    ///
    /// Under a Lua config the compositor answers every `keyword` request with
    /// a bare "unknown request" — and hyprctl still exits 0, so callers that
    /// shelled out to it looked like they worked while nothing happened. The
    /// Lua form is a NESTED table, so "a:b:c" becomes { a = { b = { c = v } } }.
    ///
    /// Numbers and booleans pass through bare; anything else is quoted, since
    /// a bare string is a Lua identifier and would be nil.
    function config(key, value) {
        const parts = String(key).split(":").filter(p => p.length > 0);
        if (parts.length === 0) return;

        const isNum = typeof value === "number"
            || (typeof value === "string" && /^-?[0-9]+(\.[0-9]+)?$/.test(value));
        const isBool = typeof value === "boolean"
            || value === "true" || value === "false";
        const lit = (isNum || isBool)
            ? String(value)
            : `'${String(value).replace(/\\/g, "\\\\").replace(/'/g, "\\'")}'`;

        let inner = lit;
        for (let i = parts.length - 1; i >= 0; i--)
            inner = `{ ${parts[i]} = ${inner} }`;
        Hyprland.dispatch(`eval hl.config(${inner})`);
    }

    function toLua(cmd) {
        // Many dispatches carry a window selector after a comma:
        //   "movetoworkspacesilent 3, address:0x55…"
        // Split it off first so the verb parser never sees it.
        let target = "";
        const comma = cmd.lastIndexOf(",");
        if (comma > 0) {
            const tail = cmd.slice(comma + 1).trim();
            if (/^(address|class|title|pid|initialclass|initialtitle|floating|tiled):/i.test(tail)) {
                target = tail;
                cmd = cmd.slice(0, comma).trim();
            }
        }
        const win = target.length > 0
            ? ', window = "' + target.replace(/\\/g, "\\\\").replace(/"/g, '\\"') + '"'
            : "";

        const sp = cmd.indexOf(" ");
        const verb = (sp < 0 ? cmd : cmd.slice(0, sp)).toLowerCase();
        const arg = sp < 0 ? "" : cmd.slice(sp + 1).trim();
        const q = s => '"' + String(s).replace(/\\/g, "\\\\").replace(/"/g, '\\"') + '"';
        // Workspace/window selectors stay strings; plain numbers stay numbers,
        // because hl.focus distinguishes them.
        const val = s => /^-?\d+$/.test(s) ? s : q(s);

        switch (verb) {
        case "workspace":
            return `hl.dsp.focus({ workspace = ${val(arg)} })`;
        case "movetoworkspace":
            return `hl.dsp.window.move({ workspace = ${val(arg)}${win} })`;
        case "movetoworkspacesilent":
            return `hl.dsp.window.move({ workspace = ${val(arg)}, follow = false${win} })`;
        case "movefocus":
            return `hl.dsp.focus({ direction = ${q(arg)} })`;
        case "focuswindow":
            return `hl.dsp.focus({ window = ${q(arg)} })`;
        case "focusmonitor":
            return `hl.dsp.focus({ monitor = ${val(arg)} })`;
        case "closewindow":
            // "activewindow" means the focused one, which is close()'s default.
            if (arg === "" || arg === "activewindow")
                return win.length > 0 ? `hl.dsp.window.close({ ${win.slice(2)} })` : "hl.dsp.window.close()";
            return `hl.dsp.window.close({ window = ${q(arg)} })`;
        case "killactive":
            return "hl.dsp.window.close()";
        case "togglefloating":
            return `hl.dsp.window.float({ action = "toggle"${win} })`;
        case "pin":
            return win.length > 0 ? `hl.dsp.window.pin({ ${win.slice(2)} })` : "hl.dsp.window.pin()";
        case "fullscreen":
            return `hl.dsp.window.fullscreen({ mode = ${arg.trim() === "1" ? '"maximized"' : '"fullscreen"'} })`;
        case "fullscreenstate": {
            const p = arg.split(/\s+/);
            return `hl.dsp.window.fullscreen_state({ internal = ${p[0] || 0}, client = ${p[1] || 0} })`;
        }
        case "togglespecialworkspace":
            return arg.length > 0
                ? `hl.dsp.workspace.toggle_special(${q(arg)})`
                : "hl.dsp.workspace.toggle_special()";
        case "renameworkspace": {
            const i = arg.indexOf(" ");
            return `hl.dsp.workspace.rename({ id = ${arg.slice(0, i)}, name = ${q(arg.slice(i + 1))} })`;
        }
        case "moveworkspacetomonitor": {
            const p = arg.split(/\s+/);
            return `hl.dsp.workspace.move({ workspace = ${val(p[0])}, monitor = ${q(p.slice(1).join(" "))} })`;
        }
        case "movewindowpixel": {
            // "exact 100 200" is absolute; a bare "100 200" is relative.
            //
            // x and y reach Lua through tableOptNum, so they must be NUMBERS.
            // These used to be emitted quoted, and a quoted "10%" satisfies no
            // branch of hl.window.move — the call fell through to the end and
            // was rejected outright as "unrecognized arguments", so dragging a
            // floating window in the overview never moved it.
            //
            // No percentage form to fall back on: the Lua dispatcher has none,
            // so percentages must be resolved to pixels by the caller. Reject
            // them here rather than let parseFloat("10%") === 10 quietly park
            // the window ten pixels from the origin.
            const parts = arg.trim().split(/\s+/);
            const exact = parts[0] === "exact";
            const xy = exact ? parts.slice(1) : parts;
            const numeric = /^-?[0-9]+(\.[0-9]+)?$/;
            if (!numeric.test(xy[0] ?? "") || !numeric.test(xy[1] ?? "")) {
                console.warn("[HyprDispatch] movewindowpixel needs numeric x/y, got:", arg);
                return "";
            }
            return `hl.dsp.window.move({ x = ${xy[0]}, y = ${xy[1]}, `
                 + `relative = ${exact ? "false" : "true"}${win} })`;
        }
        case "movecursor": {
            const p = arg.split(/\s+/);
            return `hl.dsp.cursor.move({ x = ${p[0]}, y = ${p[1]} })`;
        }
        case "exec":
            return `hl.dsp.exec_cmd(${q(arg)})`;
        case "global":
            return `hl.dsp.global(${q(arg)})`;
        case "submap":
            return `hl.dsp.submap(${q(arg === "global" ? "reset" : arg)})`;
        case "event":
            return `hl.dsp.event(${q(arg)})`;
        case "cyclenext":
            return arg.length > 0 ? `hl.dsp.window.cycle_next(${q(arg)})` : "hl.dsp.window.cycle_next()";
        case "bringactivetotop":
            return "hl.dsp.window.bring_to_top()";
        case "layoutmsg":
            return `hl.dsp.layout(${q(arg)})`;
        case "keyword":
            // Runtime keywords are gone under a Lua config — Hyprland answers
            // "unknown request". Report instead of failing silently.
            console.warn("[HyprDispatch] `keyword` is not settable at runtime with a Lua config:", arg);
            return "";
        case "reload":
            return "";   // handled by the caller via `hyprctl reload`
        default:
            console.warn("[HyprDispatch] no Lua mapping for:", cmd);
            return "";
        }
    }

    function _pixelArgs(arg) {
        const p = arg.split(/\s+/);
        return `x = ${p[0] || 0}, y = ${p[1] || 0}`;
    }
}
