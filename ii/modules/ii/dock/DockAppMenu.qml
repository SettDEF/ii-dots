// Right-click menu for a dock app.
//
// The rows are PopupMenuPanel — the same panel every other context menu in
// this shell draws — so this looks like the rest of them. What it does NOT
// use is PopupContextMenu, the usual wrapper: that one draws in the root item
// of its own window and clamps the panel inside it, and the dock's surface is
// 75px tall. Instead this is a PopupWindow covering the space above the dock,
// and the panel clamps itself inside that.
//
// Everything here comes from services that already exist: AppVolumes for
// per-app level, AppAudioFocus for audio-follows-focus, DesktopEntries for the
// app's own shortcuts, HyprlandData + HyprDispatch for per-window state and
// actions, TaskbarApps for the pin.
pragma ComponentBehavior: Bound
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Services.Pipewire

PopupWindow {
    id: root

    property Item anchorItem: null
    property var appEntry: null
    property int panelWidth: 226
    color: "transparent"

    readonly property string appId: root.appEntry?.appId ?? ""
    readonly property var toplevels: root.appEntry?.toplevels ?? []
    readonly property var desktopEntry: root.appId.length > 0
        ? DesktopEntries.heuristicLookup(root.appId) : null
    readonly property bool pinned: root.appId.length > 0 && TaskbarApps.isPinned(root.appId)
    readonly property var entryActions: root.desktopEntry?.actions ?? []

    // AppVolumes lists every open app, so a silent one still gets a row — its
    // level is remembered and applied once it opens a stream.
    readonly property var volRow: {
        // PID first. The name-derived key cannot join a Steam or Proton game
        // to its stream: the window is class `steam_app_default` while the
        // stream is named after the game, so per-app volume silently did
        // nothing for every game. The pid is the same on both sides.
        const pids = root.toplevels.map(t => root._winData(t)?.pid).filter(p => p > 0);
        if (pids.length > 0) {
            for (const r of (AppVolumes.rows ?? [])) {
                const np = parseInt(r.node?.properties?.["application.process.id"] ?? -1, 10);
                if (np > 0 && pids.indexOf(np) >= 0) return r;
            }
        }
        const key = AppVolumes.appKey(root.appId);
        if (key.length === 0) return null;
        return (AppVolumes.rows ?? []).find(r => r.key === key) ?? null;
    }
    readonly property bool volLive: root.volRow?.live ?? false

    // node.audio stays empty without a tracker, and a write to an untracked
    // node is silently discarded. Tracking is held for a moment after the menu
    // closes: a handler can fire on the way out, and losing the tracker before
    // the write lands is exactly how the volume presets used to do nothing.
    // node.properties — where the pid lives — is empty without a tracker, so
    // the match above needs ALL app nodes tracked, not just the matched one.
    // Only while the menu is open: there are two or three of them.
    PwObjectTracker {
        objects: root.visible ? (Audio.outputAppNodes ?? []) : []
    }

    property bool _holdTrack: false
    onVisibleChanged: {
        if (root.visible) { root._holdTrack = true; trackHold.stop(); }
        else trackHold.restart();
    }
    Timer {
        id: trackHold
        interval: 1500
        onTriggered: root._holdTrack = false
    }
    PwObjectTracker {
        objects: (root._holdTrack && root.volRow?.node) ? [root.volRow.node] : []
    }

    function openFor(entry, item) {
        if (!entry || !item) return;
        root.appEntry = entry;
        root.anchorItem = item;
        root.visible = true;
    }
    function close() { root.visible = false }

    // ── Helpers ──────────────────────────────────────────────────────────
    readonly property color _on: Appearance.colors.colPrimary
    // A radio for "one of these", a checkbox for an independent toggle.
    function _check(on) { return on ? "radio_button_checked" : "radio_button_unchecked" }
    function _box(on) { return on ? "check_box" : "check_box_outline_blank" }
    function _tick(on) { return on ? root._on : undefined }

    // HyprlandToplevel is an attached property on the Wayland toplevel; it is
    // the only link from one to a Hyprland address, and the address is what
    // every per-window dispatch needs.
    function _addr(toplevel) {
        const a = toplevel?.HyprlandToplevel?.address;
        return a ? `0x${a}` : "";
    }
    function _winData(toplevel) {
        const a = root._addr(toplevel);
        return a.length > 0 ? (HyprlandData.windowByAddress[a] ?? null) : null;
    }

    // ── Sub-menus ────────────────────────────────────────────────────────
    function _workspaceItems(addr, curId) {
        return (HyprlandData.workspaces ?? [])
            .filter(w => w.id > 0)
            .sort((a, b) => a.id - b.id)
            .map(w => ({
                icon: root._check(w.id === curId),
                iconColor: root._tick(w.id === curId),
                label: (w.name && w.name !== String(w.id))
                    ? `${w.id} · ${w.name}` : Translation.tr("Workspace %1").arg(w.id),
                onTriggered: () => HyprDispatch.run(`movetoworkspacesilent ${w.id}, address:${addr}`)
            }));
    }

    function _windowItems(t) {
        const addr = root._addr(t);
        const d = root._winData(t);
        const sel = addr.length > 0 ? `, address:${addr}` : "";
        const out = [{
            icon: "ads_click", label: Translation.tr("Focus"),
            onTriggered: () => t?.activate()
        }];

        if (addr.length > 0) {
            out.push({
                icon: "move_down", label: Translation.tr("Move to workspace"),
                submenu: root._workspaceItems(addr, d?.workspace?.id ?? -1)
            }, { separator: true }, {
                icon: root._box(d?.floating === true), iconColor: root._tick(d?.floating === true),
                label: Translation.tr("Floating"),
                onTriggered: () => HyprDispatch.run(`togglefloating${sel}`)
            }, {
                icon: root._box(d?.pinned === true), iconColor: root._tick(d?.pinned === true),
                label: Translation.tr("Always on top"),
                onTriggered: () => HyprDispatch.run(`pin${sel}`)
            }, {
                // No window selector in the Lua fullscreen dispatcher, so
                // focus it first and act on the focused window.
                icon: "fullscreen", label: Translation.tr("Fullscreen"),
                onTriggered: () => {
                    HyprDispatch.run(`focuswindow address:${addr}`);
                    HyprDispatch.run("fullscreen 0");
                }
            });
        }

        out.push({ separator: true }, {
            icon: "title", label: Translation.tr("Copy title"),
            onTriggered: () => { Quickshell.clipboardText = t?.title ?? ""; }
        }, {
            icon: "close", danger: true, label: Translation.tr("Close"),
            onTriggered: () => t?.close()
        });
        return out;
    }

    function _volumeItems() {
        if (!root.volRow) return [];
        const out = [];
        if (root.volLive) {
            const muted = AppVolumes.mutedFor(root.volRow);
            out.push({
                icon: muted ? "volume_off" : "volume_up",
                iconColor: root._tick(muted),
                label: muted ? Translation.tr("Unmute") : Translation.tr("Mute"),
                onTriggered: () => AppVolumes.toggleMute(root.volRow)
            }, { separator: true });
        }
        // Slider AND presets. The slider is the range; the presets are the
        // two or three levels anyone actually reuses, reachable in one click
        // without a drag. Dragging also keeps the menu — and therefore the
        // PwObjectTracker this write depends on — open for the gesture.
        out.push({
            slider: true,
            icon: "volume_up",
            value: AppVolumes.volumeFor(root.volRow),
            onMoved: v => AppVolumes.setVolume(root.volRow, v)
        }, { separator: true });

        const cur = Math.round(AppVolumes.volumeFor(root.volRow) * 100);
        for (const pct of [100, 75, 50, 25, 0])
            out.push({
                icon: root._check(cur === pct), iconColor: root._tick(cur === pct),
                label: `${pct}%`,
                onTriggered: () => AppVolumes.setVolume(root.volRow, pct / 100)
            });

        // An app with no stream open has nothing to be loud with. The level
        // is still worth setting — it is applied the moment the app starts
        // playing — but without saying so, a slider that changes nothing
        // audible reads as broken. Which is exactly how it was reported.
        if (!root.volLive)
            out.push({ separator: true }, {
                icon: "schedule",
                label: Translation.tr("Not playing — saved for next time")
            });
        return out;
    }

    // ── Model ────────────────────────────────────────────────────────────
    // Only while open: AppVolumes.rows and HyprlandData both churn, and
    // rebuilding this for a menu nobody is looking at is pure waste.
    readonly property var menuModel: {
        if (!root.visible) return [];
        const out = [];
        const tl = root.toplevels;

        if (tl.length > 0)
            out.push({
                icon: "web_asset",
                label: tl.length > 1 ? Translation.tr("Windows (%1)").arg(tl.length)
                                     : Translation.tr("Window"),
                submenu: tl.map(t => {
                    const wsId = root._winData(t)?.workspace?.id;
                    const active = t?.activated === true;
                    return {
                        icon: active ? "radio_button_checked" : "web_asset",
                        iconColor: root._tick(active),
                        // Workspace first: a long title elides from the right.
                        label: (wsId !== undefined && wsId !== null)
                            ? `${wsId} · ${t?.title ?? ""}` : (t?.title ?? ""),
                        submenu: root._windowItems(t)
                    };
                })
            });

        if (root.entryActions.length > 0)
            out.push({
                icon: "bolt", label: Translation.tr("Shortcuts"),
                submenu: root.entryActions.map(a => ({
                    icon: "bolt", label: a?.name ?? "",
                    onTriggered: () => a?.execute()
                }))
            });

        if (root.volRow)
            out.push({
                icon: AppVolumes.mutedFor(root.volRow) ? "volume_off" : "volume_up",
                label: Translation.tr("Volume — %1%")
                    .arg(Math.round(AppVolumes.volumeFor(root.volRow) * 100)),
                submenu: root._volumeItems()
            });

        if (root.volLive) {
            const mode = AppAudioFocus.getMode(root.volRow.node);
            out.push({
                icon: AppAudioFocus.modeIcon(mode),
                label: Translation.tr("Audio: %1").arg(AppAudioFocus.modeName(mode)),
                submenu: [0, 1, 2].map(m => ({
                    icon: root._check(m === mode), iconColor: root._tick(m === mode),
                    label: AppAudioFocus.modeName(m),
                    onTriggered: () => AppAudioFocus.setMode(root.volRow.node, m)
                }))
            });
        }

        if (out.length > 0) out.push({ separator: true });

        out.push({
            icon: "open_in_new", label: Translation.tr("New window"),
            onTriggered: () => AppLaunch.launch(root.desktopEntry)
        }, {
            icon: root.pinned ? "keep_off" : "keep", iconColor: root._tick(root.pinned),
            label: root.pinned ? Translation.tr("Unpin from dock")
                               : Translation.tr("Pin to dock"),
            onTriggered: () => TaskbarApps.togglePin(root.appId)
        }, {
            icon: "tag", label: Translation.tr("Copy app ID"),
            onTriggered: () => { Quickshell.clipboardText = root.appId; }
        }, {
            icon: "tune", label: Translation.tr("Edit dock…"),
            onTriggered: () => { GlobalStates.dockEditMode = true; }
        });

        if (tl.length > 0)
            out.push({ separator: true }, {
                icon: "close", danger: true,
                label: tl.length > 1 ? Translation.tr("Close all windows")
                                     : Translation.tr("Close window"),
                onTriggered: () => { for (const t of tl) t?.close(); }
            });
        return out;
    }

    // ── Surface ──────────────────────────────────────────────────────────
    // Spans the dock's width and everything above it, so the panel has room
    // to clamp itself the way it does in every other window.
    anchor {
        window: root.anchorItem ? root.anchorItem.QsWindow.window : null
        gravity: Edges.Top | Edges.Right
        edges: Edges.Top | Edges.Left
        adjustment: PopupAdjustment.None
        rect: Qt.rect(0, 0, 1, 1)
    }

    implicitWidth: root.anchorItem?.QsWindow?.window?.width ?? 1
    implicitHeight: {
        const win = root.anchorItem?.QsWindow?.window ?? null;
        if (!win) return 400;
        return Math.max(240, ScreenFit.logicalHeight(win)
            - ScreenFit.reservedTop(win) - win.height);
    }

    // Anywhere outside the panel dismisses — the surface covers the screen
    // above the dock, so this is the outside click.
    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.AllButtons
        hoverEnabled: true
        onPressed: root.close()
        onWheel: wheel => wheel.accepted = true
    }

    Item {
        id: menuBounds
        anchors.fill: parent

        // Rebuilt on every open so the panel's entry animation runs.
        Loader {
            active: root.visible
            sourceComponent: PopupMenuPanel {
                items: root.menuModel
                bounds: menuBounds
                panelWidth: root.panelWidth
                // Centred over the button, sitting on the dock.
                originX: (root.anchorItem && root.anchorItem.QsWindow?.window)
                    ? root.anchorItem.QsWindow.mapFromItem(root.anchorItem,
                        root.anchorItem.width / 2, 0).x - root.panelWidth / 2
                    : 0
                desiredY: menuBounds.height   // clamps to the bottom
                dismissAll: () => root.close()
            }
        }
    }
}
