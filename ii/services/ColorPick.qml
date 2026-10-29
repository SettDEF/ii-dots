pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import qs.modules.common
import qs.modules.common.functions

/**
 * The colour picker: hyprpicker picks a pixel (its loupe), then the ColorPicker window shows the
 * colour in every format, its contrast, its shades and the Material roles tinct makes from it.
 */
Singleton {
    id: root

    property bool open: false
    property string hex: ""
    /// tinct's roles for the colour: [{ role, light, dark }]
    property var roles: []
    readonly property var recent: Persistent.states.colorPick.recent

    function pick(): void {
        root.open = false;
        picker.running = true;
    }
    /// a pixel for someone else (the colour editor): the hex goes to cb, no picker window
    property var _into: null
    function pickInto(cb): void {
        root._into = cb;
        picker.running = true;
    }
    function remember(c: string): void {
        Persistent.states.colorPick.recent = [c].concat(Array.from(root.recent).filter(x => x !== c)).slice(0, 14);
    }
    function show(h: string): void {
        const c = root.normal(h);
        if (!c) return;
        root.hex = c;
        const r = [c].concat(Array.from(root.recent).filter(x => x !== c)).slice(0, 14);
        Persistent.states.colorPick.recent = r;
        tinctProc.running = false;
        tinctProc.running = true;
        root.open = true;
    }

    // a short pause: the bar's button closes its overlay first, which would land in the pick
    Process {
        id: picker
        command: ["bash", "-c", "sleep 0.15; hyprpicker -f hex -l"]
        stdout: StdioCollector { onStreamFinished: {
                const h = text.trim(), cb = root._into;
                root._into = null;
                if (!h.length) return;
                if (cb) { const c = root.normal(h); if (c) { root.remember(c); cb(c); } }
                else root.show(h);
            } }
    }
    Process {
        id: tinctProc
        command: [FileUtils.trimFileProtocol(`${Directories.home}/.local/bin/tinct`), "ui", "--color", root.hex, "--format", "json"]
        stdout: StdioCollector {
            onStreamFinished: {
                try { root.roles = JSON.parse(text).roles ?? []; } catch (e) { root.roles = []; }
            }
        }
    }

    // ── colour maths (sRGB, OKLab) ──
    function normal(h: string): string {
        const m = /^#?([0-9a-fA-F]{6})$/.exec(h.trim());
        return m ? "#" + m[1].toLowerCase() : "";
    }
    function rgb(h) { const v = parseInt(h.slice(1), 16); return [(v >> 16) & 255, (v >> 8) & 255, v & 255]; }
    function hexOf(r, g, b) { return "#" + [r, g, b].map(x => Math.round(Math.max(0, Math.min(255, x))).toString(16).padStart(2, "0")).join(""); }
    function lin(c) { c /= 255; return c <= 0.04045 ? c / 12.92 : Math.pow((c + 0.055) / 1.055, 2.4); }
    function gam(c) { const v = c <= 0.0031308 ? 12.92 * c : 1.055 * Math.pow(c, 1 / 2.4) - 0.055; return v * 255; }
    function oklab(h) {
        const [r, g, b] = rgb(h).map(lin);
        const l = Math.cbrt(0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b);
        const m = Math.cbrt(0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b);
        const s = Math.cbrt(0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b);
        return [0.2104542553 * l + 0.7936177850 * m - 0.0040720468 * s,
                1.9779984951 * l - 2.4285922050 * m + 0.4505937099 * s,
                0.0259040371 * l + 0.7827717662 * m - 0.8086757660 * s];
    }
    /// OKLCH → sRGB, chroma lowered until it fits the gamut
    function fromOklch(L, C, H) {
        for (let c = C; c >= 0; c -= 0.005) {
            const a = c * Math.cos(H), b = c * Math.sin(H);
            const l = Math.pow(L + 0.3963377774 * a + 0.2158037573 * b, 3);
            const m = Math.pow(L - 0.1055613458 * a - 0.0638541728 * b, 3);
            const s = Math.pow(L - 0.0894841775 * a - 1.2914855480 * b, 3);
            const rl = 4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s;
            const gl = -1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s;
            const bl = -0.0041960863 * l - 0.7034186147 * m + 1.7076147010 * s;
            if ([rl, gl, bl].every(v => v >= -0.0005 && v <= 1.0005)) return hexOf(gam(rl), gam(gl), gam(bl));
        }
        return hexOf(gam(L), gam(L), gam(L));
    }
    function lch(h) { const [L, a, b] = oklab(h); return [L, Math.hypot(a, b), Math.atan2(b, a)]; }
    function hsl(h) {
        const [r, g, b] = rgb(h).map(x => x / 255);
        const mx = Math.max(r, g, b), mn = Math.min(r, g, b), l = (mx + mn) / 2, d = mx - mn;
        if (d === 0) return [0, 0, l];
        const s = d / (1 - Math.abs(2 * l - 1));
        const hh = mx === r ? ((g - b) / d) % 6 : mx === g ? (b - r) / d + 2 : (r - g) / d + 4;
        return [(hh * 60 + 360) % 360, s, l];
    }
    function luminance(h) { const [r, g, b] = rgb(h).map(lin); return 0.2126 * r + 0.7152 * g + 0.0722 * b; }
    function contrast(a, b) { const x = luminance(a), y = luminance(b); return (Math.max(x, y) + 0.05) / (Math.min(x, y) + 0.05); }

    /// The ways to write it: [{ name, text }]
    function formats(h) {
        if (!h) return [];
        const [r, g, b] = rgb(h), [hh, s, l] = hsl(h), [L, C, H] = lch(h);
        return [
            { name: "HEX", text: h.toUpperCase() },
            { name: "RGB", text: `rgb(${r}, ${g}, ${b})` },
            { name: "HSL", text: `hsl(${Math.round(hh)}, ${Math.round(s * 100)}%, ${Math.round(l * 100)}%)` },
            { name: "OKLCH", text: `oklch(${(L * 100).toFixed(1)}% ${C.toFixed(3)} ${Math.round((H * 180 / Math.PI + 360) % 360)})` },
        ];
    }
    /// Lightness steps of the same hue and chroma, light to dark (the picked one marked by the nearest step)
    function shades(h) {
        if (!h) return [];
        const [, C, H] = lch(h);
        return [0.97, 0.9, 0.8, 0.7, 0.6, 0.5, 0.4, 0.3, 0.22, 0.15].map(L => root.fromOklch(L, C, H));
    }
    function copy(text) {
        Quickshell.clipboardText = text;
    }

    IpcHandler {
        target: "colorPick"
        function pick(): void { root.pick(); }
        /// `qs ipc call colorPick color 3a6ea5`: the window for a colour, no pick
        function color(hex: string): void { root.show(hex); }
        function close(): void { root.open = false; }
    }
}
