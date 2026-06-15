pragma Singleton

import QtQuick
import Quickshell

/**
 * Tracks whether the most recent pointer input came from a mouse, a touch
 * screen, or a stylus. Widgets bind to `isTouch` / `isPen` to surface
 * touch-friendly affordances only while the user is actually using touch
 * input — so mouse UX stays clean.
 *
 * Fed by the `InputModeProbe` component, which is dropped into always-
 * visible surfaces (the bar) and emits per-pointer-event device hints.
 */
Singleton {
    id: root

    // "mouse" | "touch" | "pen"
    property string mode: "mouse"

    readonly property bool isTouch: mode === "touch"
    readonly property bool isPen:   mode === "pen"
    readonly property bool isMouse: mode === "mouse"

    /**
     * Update mode from a Qt pointer device. Accepts either the device
     * object (with `.type`) or a numeric Qt enum value.
     */
    function reportDevice(device) {
        if (device === null || device === undefined) return
        const t = (typeof device === "object") ? device.type : device
        if (t === PointerDevice.TouchScreen) {
            _setMode("touch")
        } else if (t === PointerDevice.Stylus || t === PointerDevice.Eraser) {
            _setMode("pen")
        } else if (t === PointerDevice.Mouse || t === PointerDevice.TouchPad) {
            _setMode("mouse")
        }
    }

    function _setMode(m) {
        if (mode !== m) mode = m
    }
}
