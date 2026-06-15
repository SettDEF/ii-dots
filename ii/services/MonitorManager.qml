pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

/**
 * Thin wrapper around `hyprctl monitors -j` plus enable/disable/mirror
 * helpers. Powered by HyprlandData for the live list — we reuse the
 * existing poll instead of running a second `hyprctl monitors -j`.
 *
 * `monitors` shape (from hyprctl):
 *   { name, description, make, model, serial, width, height,
 *     refreshRate, x, y, scale, transform, focused, dpmsStatus,
 *     vrr, activelyTearing, disabled, mirrorOf, ... }
 *
 * Internal/external detection is a heuristic on the connector name —
 * laptop panels expose eDP-* or LVDS-* / DSI-* connectors.
 */
Singleton {
    id: root

    // Raw monitor records — bound to HyprlandData.monitors so refreshes
    // there propagate here automatically.
    readonly property var monitors: HyprlandData.monitors

    // Decorated list with `kind` ("internal" / "external") and `enabled`.
    readonly property var friendly: (monitors ?? []).map(m => ({
        name: m.name,
        description: m.description ?? "",
        kind: root.isInternalName(m.name) ? "internal" : "external",
        width: m.width ?? 0,
        height: m.height ?? 0,
        refreshRate: m.refreshRate ?? 0,
        scale: m.scale ?? 1,
        focused: m.focused ?? false,
        dpms: m.dpmsStatus ?? true,
        mirrorOf: m.mirrorOf ?? "",
        disabled: (m.disabled ?? false) === true,
        raw: m,
    }))

    readonly property var internalMonitors: friendly.filter(m => m.kind === "internal")
    readonly property var externalMonitors: friendly.filter(m => m.kind === "external")

    // True when any external panel is currently active.
    readonly property bool anyExternalActive:
        externalMonitors.some(m => !m.disabled)

    function isInternalName(name) {
        if (!name) return false
        const n = String(name).toLowerCase()
        return n.startsWith("edp") || n.startsWith("lvds") || n.startsWith("dsi")
    }

    function refresh() { HyprlandData.updateMonitors() }

    // ── Mutations via `hyprctl keyword monitor ...` ─────────────────────
    function _runKeyword(arg) {
        keywordProc.command = ["hyprctl", "keyword", "monitor", arg]
        keywordProc.running = true
    }

    function enable(name) {
        _runKeyword(`${name},preferred,auto,1`)
        Qt.callLater(refresh)
    }

    function disable(name) {
        _runKeyword(`${name},disable`)
        Qt.callLater(refresh)
    }

    function toggleEnabled(m) {
        if (!m) return
        if (m.disabled) enable(m.name)
        else disable(m.name)
    }

    /** Mirror `name` onto `targetName`. Pass empty target to stop mirroring. */
    function setMirror(name, targetName) {
        if (targetName && targetName.length > 0)
            _runKeyword(`${name},preferred,auto,1,mirror,${targetName}`)
        else
            _runKeyword(`${name},preferred,auto,1`)
        Qt.callLater(refresh)
    }

    // ── Preset arrangements (Windows "Project" equivalents) ─────────────
    // Each preset is best-effort and silently no-ops branches that don't
    // apply (e.g. mirror on a single-monitor setup).

    // Safety: refuse any preset that would leave zero enabled monitors —
    // the user would lose all visual output and have no way to recover
    // without dropping to a TTY. Returns true if it's safe to proceed.
    function _wouldBlackout(keepInternal, keepExternal) {
        const i = internalMonitors.length
        const e = externalMonitors.length
        if (keepInternal && i > 0) return false
        if (keepExternal && e > 0) return false
        return true
    }

    /** Internal panel(s) on, all externals off. */
    function presetInternalOnly() {
        if (_wouldBlackout(true, false)) return  // no internal panel detected
        internalMonitors.forEach(m => enable(m.name))
        externalMonitors.forEach(m => disable(m.name))
    }

    /** External panel(s) on, internal off. Useful for docking. */
    function presetExternalOnly() {
        if (_wouldBlackout(false, true)) return  // no external connected
        externalMonitors.forEach(m => enable(m.name))
        internalMonitors.forEach(m => disable(m.name))
    }

    /** All panels on, no mirroring (Hyprland will arrange them). */
    function presetExtend() {
        internalMonitors.forEach(m => enable(m.name))
        externalMonitors.forEach(m => setMirror(m.name, ""))
    }

    /** All externals mirror the first internal panel. */
    function presetMirror() {
        const target = internalMonitors[0]?.name
        if (!target) return
        enable(target)
        externalMonitors.forEach(m => setMirror(m.name, target))
    }

    /** Last-resort recovery: enable every connected monitor at preferred. */
    function enableAll() {
        _runKeyword(",preferred,auto,1")
        Qt.callLater(refresh)
    }

    // Heuristic: which preset does the current state look like?
    readonly property string activePreset: {
        const internalOn = internalMonitors.some(m => !m.disabled)
        const externalOn = externalMonitors.some(m => !m.disabled)
        const allMirror  = externalMonitors.length > 0
                        && externalMonitors.every(m => m.mirrorOf && m.mirrorOf.length > 0)
        if (internalOn && !externalOn) return "internal"
        if (!internalOn && externalOn) return "external"
        if (internalOn &&  externalOn && allMirror) return "mirror"
        if (internalOn &&  externalOn) return "extend"
        return "unknown"
    }

    Process {
        id: keywordProc
    }
}
