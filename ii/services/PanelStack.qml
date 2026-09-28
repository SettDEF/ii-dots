pragma Singleton
pragma ComponentBehavior: Bound

// Lays the top-right panels out SIDE BY SIDE instead of on top of each other.
//
// They used to be mutually exclusive by accident: each registered with
// GlobalFocusGrab, so opening one dismissed the last. Removing that grab (a
// settings panel is not a context menu — clicking the thing you are
// configuring should not close it) means several can be open at once, and they
// all anchor to the same corner.
//
// A panel's horizontal offset is the total width of the OPEN panels ordered
// before it. Order comes from a fixed list rather than open-order, so the
// layout does not reshuffle as you toggle things: a panel closing should slide
// the others across, not rearrange them.

import QtQuick
import Quickshell
import qs.services

Singleton {
    id: root

    // Right-to-left placement order. Anything unlisted goes last.
    readonly property var order: [
        "display", "walltune", "wallEffect", "kinetix", "audio", "mic", "deviceTools", "torrents", "iris", "statsHudSettings", "rogPower"
    ]

    readonly property int gap: 8

    // id -> width, for open panels only.
    property var widths: ({})

    function register(id, w) {
        if (!id || w <= 0) return;
        if (root.widths[id] === w) return;     // no-op keeps bindings quiet
        const isNew = root.widths[id] === undefined;
        const next = Object.assign({}, root.widths);
        next[id] = w;
        root.widths = next;
        if (isNew) root.enforceCapacity(id);
    }

    function unregister(id) {
        if (root.widths[id] === undefined) return;
        const next = Object.assign({}, root.widths);
        delete next[id];
        root.widths = next;
    }

    function rank(id) {
        const i = root.order.indexOf(id);
        return i < 0 ? root.order.length : i;
    }

    // How far left this panel must sit: everything ranked before it that is
    // currently open.
    function offsetFor(id) {
        const mine = root.rank(id);
        let off = 0;
        for (const other in root.widths) {
            if (other === id) continue;
            const r = root.rank(other);
            // Ties (both unlisted) break on name so the result is stable
            // rather than dependent on object iteration order.
            if (r < mine || (r === mine && other < id))
                off += root.widths[other] + root.gap;
        }
        return off;
    }

    readonly property int openCount: Object.keys(root.widths).length

    // ── Capacity ────────────────────────────────────────────────────────
    // Side-by-side only works while there is side to be beside. A panel slot is
    // 408 logical px, so on this laptop (1600 logical wide) THREE fit — the fourth was
    // landing at x=-108, off the left edge, and the fifth and sixth piled up
    // behind it. That is the overlap: not panels drawn on top of each other by
    // design, but the stack silently running out of room.
    //
    // So opening a fourth closes the oldest, the way a stack of cards works.
    // Nothing ever overlaps and nothing is ever off-screen.
    readonly property int screenWidth: {
        const ms = HyprlandData.monitors ?? [];
        if (ms.length === 0) return 1920;
        const m = ms[0];
        return Math.round(m.width / (m.scale || 1));
    }
    readonly property int slotWidth: 400 + root.gap
    readonly property int capacity:
        Math.max(1, Math.floor((root.screenWidth - 16) / root.slotWidth))

    // Emitted with the id of a panel that must close to make room. GlobalStates
    // owns the open-state booleans, so it does the closing.
    signal evict(string id)

    // Insertion order is preserved by the object rebuild in register(), so the
    // first key is the panel that has been open longest.
    function oldestOpen(excluding) {
        for (const k in root.widths)
            if (k !== excluding) return k;
        return "";
    }

    function enforceCapacity(justOpened) {
        if (root.openCount <= root.capacity) return;
        const victim = root.oldestOpen(justOpened);
        if (victim.length > 0) {
            console.log("[PanelStack] at capacity", root.capacity,
                        "— closing", victim, "to make room for", justOpened);
            root.evict(victim);
        }
    }
}


