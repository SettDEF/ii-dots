pragma Singleton

// Screen rects of the draggable background widgets.
//
// The desktop-icons layer sits above the background layer and takes input
// across its whole surface, so a press meant for a widget never reaches it.
// The icons window subtracts these rects from its input mask.
import QtQuick
import Quickshell

Singleton {
    id: root

    property var rects: ({})

    function set(key, screenName, x, y, w, h) {
        if (!key || !screenName)
            return;
        const next = Object.assign({}, root.rects);
        next[key] = { screen: screenName, x: x, y: y, w: w, h: h };
        root.rects = next;
    }

    function clear(key) {
        if (!root.rects[key])
            return;
        const next = Object.assign({}, root.rects);
        delete next[key];
        root.rects = next;
    }

    function forScreen(screenName) {
        return Object.keys(root.rects)
            .map(k => root.rects[k])
            .filter(r => r.screen === screenName);
    }
}
