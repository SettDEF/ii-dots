// One tooltip for the whole dock: tiles publish what to show, the dock's
// popup renders it.
//
// A tooltip inside the dock window is clipped — the surface is only as tall
// as the dock and a tile has ~10px of headroom. One popup owned by the dock
// beats one window per tile.
pragma Singleton

import QtQuick
import Quickshell

Singleton {
    id: root
    property Item target: null
    property string text: ""

    function show(item, label) {
        if (!item || !label || label.length === 0) return;
        root.target = item;
        root.text = label;
    }
    function hide(item) {
        if (root.target === item) {
            root.target = null;
            root.text = "";
        }
    }
}
