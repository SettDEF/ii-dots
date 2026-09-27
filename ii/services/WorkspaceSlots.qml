pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Hyprland
import qs.modules.common

/**
 * Which workspaces a bar should show, and what is in them.
 *
 * Extracted so the horizontal and vertical bars cannot disagree about it. The
 * derivation is not obvious and is easy to get subtly wrong a second time:
 *
 * The bar shows the standard 1-10 group, anchored to the group containing the
 * LOWEST existing workspace, plus any workspace outside that group that
 * actually exists. That last part is why a workspace like 61 on another
 * monitor stays reachable from either bar, instead of dragging 1-3 out of view
 * whenever focus follows the mouse across monitors.
 */
Singleton {
    id: root

    readonly property int workspacesPerGroup: 10

    readonly property int focusedWsId: Hyprland.focusedWorkspace?.id ?? 1

    readonly property int _anchorWsId: {
        let lo = -1;
        const v = Hyprland.workspaces.values;
        for (let i = 0; i < v.length; i++) {
            const id = v[i]?.id ?? 0;
            if (id > 0 && (lo < 0 || id < lo)) lo = id;
        }
        return lo > 0 ? lo : 1;
    }
    readonly property int currentGroup: Math.floor((root._anchorWsId - 1) / root.workspacesPerGroup)
    readonly property int groupStart: root.currentGroup * root.workspacesPerGroup + 1

    /// Sorted ids the bar should render a slot for.
    readonly property var slotWsIds: {
        const ids = [];
        for (let i = 0; i < root.workspacesPerGroup; i++) ids.push(root.groupStart + i);
        const v = Hyprland.workspaces.values;
        for (let i = 0; i < v.length; i++) {
            const id = v[i]?.id ?? 0;
            if (id > 0 && (id < root.groupStart || id >= root.groupStart + root.workspacesPerGroup))
                ids.push(id);
        }
        ids.sort((a, b) => a - b);
        return ids;
    }
    readonly property int slotCount: root.slotWsIds.length

    /// Index of the focused workspace within slotWsIds, or -1.
    readonly property int activeIndex: root.slotWsIds.indexOf(root.focusedWsId)

    function existsAt(index) {
        const id = root.slotWsIds[index];
        return id === undefined ? false
            : Hyprland.workspaces.values.some(w => w.id === id);
    }
    function idAt(index) { return root.slotWsIds[index] ?? -1 }

    readonly property var romanTable: ["I","II","III","IV","V","VI","VII","VIII","IX","X"]

    /// What a slot should be labelled, by the same rules the horizontal bar
    /// uses: an explicit workspace name wins, then the user's own nerd-font
    /// glyph list, then roman numerals, then the plain id.
    ///
    /// Derived from the workspace ID, never from the index: out-of-group slots
    /// are appended after the group, so index+1 named them wrong — workspace 61
    /// showed up as "VII".
    function labelAt(index) {
        const id = root.idAt(index);
        if (id < 0) return "";
        const ws = Hyprland.workspaces.values.find(w => w.id === id);
        const name = ws?.name ?? "";
        if (name && name !== String(id)) return name;

        const w = Config.options.bar.workspaces;
        const off = id - root.groupStart;
        const inGroup = off >= 0 && off < root.workspacesPerGroup;
        if (w.useNerdFont && inGroup && (w.numberMap?.length ?? 0) > off)
            return w.numberMap[off];
        if (w.romanNumerals && inGroup)
            return root.romanTable[off] ?? String(id);
        return String(id);
    }

    function focusIndex(index) {
        const id = root.idAt(index);
        if (id > 0) Hyprland.dispatch(`workspace ${id}`);
    }
}
