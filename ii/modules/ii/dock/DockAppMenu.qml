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
import qs.modules.common.functions
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
    readonly property string _shareBinary: String(root.volRow?.node?.properties?.["application.process.binary"] ?? "")
    readonly property bool sharedToMic: MicShare.enabled && root._shareBinary !== ""
        && MicShare.sharedApps.indexOf(root._shareBinary) >= 0

    // The app's recording streams (Discord in a call, a tab using the mic),
    // matched like the playback row: same pid, or same app key.
    readonly property var micNodes: {
        const pids = root.toplevels.map(t => root._winData(t)?.pid).filter(p => p > 0);
        const key = root.volRow?.key ?? AppVolumes.appKey(root.appId);
        return (Audio.inputAppNodes ?? []).filter(n => {
            const np = parseInt(n?.properties?.["application.process.id"] ?? -1, 10);
            return (np > 0 && pids.indexOf(np) >= 0)
                || (key.length > 0 && AppVolumes.keyForNode(n) === key);
        });
    }
    /// Only bound nodes: a write to an untracked one is dropped with an error.
    function _micAudios() {
        return root.micNodes.filter(n => n?.ready && n.audio).map(n => n.audio);
    }
    function _micLevel(auds) {
        return auds.length > 0 ? Math.max(...auds.map(a => a.volume ?? 0)) : 0;
    }

    // node.audio stays empty without a tracker, and a write to an untracked
    // node is silently discarded. Tracking is held for a moment after the menu
    // closes: a handler can fire on the way out, and losing the tracker before
    // the write lands is exactly how the volume presets used to do nothing.
    // node.properties — where the pid lives — is empty without a tracker, so
    // the match above needs ALL app nodes tracked, not just the matched one.
    // Only while the menu is open: there are two or three of them.
    PwObjectTracker {
        objects: root.visible ? [...(Audio.outputAppNodes ?? []), ...(Audio.inputAppNodes ?? [])] : []
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
        objects: root._holdTrack ? [...(root.volRow?.nodes ?? []), ...root.micNodes] : []
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
    /// Discord's voice controls, with Discord's own names for them.
    function _discordVoiceItems(v) {
        const c = v.can ?? {};
        const cmd = (a, val) => DiscordVoice.command(a, val);
        const items = [];
        if (c.mute !== false) items.push({
            icon: v.mute ? "mic_off" : "mic", iconColor: v.mute ? Appearance.m3colors.m3error : undefined,
            label: v.mute ? Translation.tr("Unmute") : Translation.tr("Mute"),
            onTriggered: () => cmd("toggleMute")
        });
        if (c.deaf !== false) items.push({
            icon: v.deaf ? "headset_off" : "headphones", iconColor: v.deaf ? Appearance.m3colors.m3error : undefined,
            label: v.deaf ? Translation.tr("Undeafen") : Translation.tr("Deafen"),
            onTriggered: () => cmd("toggleDeaf")
        });

        // Input mode: talk whenever you speak, or only while a key is held.
        if (c.mode !== false && v.mode) {
            const ptt = v.mode === "PUSH_TO_TALK";
            const modeItems = [{
                icon: root._check(!ptt), iconColor: root._tick(!ptt),
                label: Translation.tr("Voice Activity"),
                onTriggered: () => cmd("mode", "VOICE_ACTIVITY")
            }, {
                icon: root._check(ptt), iconColor: root._tick(ptt),
                label: Translation.tr("Push to Talk (hold a key)"),
                onTriggered: () => cmd("mode", "PUSH_TO_TALK")
            }];
            if (!ptt && v.autoThreshold !== null) {
                modeItems.push({ separator: true }, {
                    icon: root._box(v.autoThreshold), iconColor: root._tick(v.autoThreshold),
                    label: Translation.tr("Automatically determine input sensitivity"),
                    onTriggered: () => cmd("autoThreshold", !v.autoThreshold)
                });
                if (!v.autoThreshold && v.threshold !== null)
                    modeItems.push({
                        // Discord's threshold runs -100 dB (everything) .. 0 dB (only shouting)
                        slider: true, icon: "graphic_eq",
                        value: Math.max(0, Math.min(1, (v.threshold + 100) / 100)),
                        valueText: x => `${Math.round(x * 100 - 100)} dB`,
                        onMoved: x => cmd("threshold", Math.round(x * 100 - 100))
                    });
            }
            items.push({
                icon: ptt ? "keyboard" : "graphic_eq",
                label: ptt ? Translation.tr("Input mode: Push to Talk") : Translation.tr("Input mode: Voice Activity"),
                submenu: modeItems
            });
        }

        // Voice processing — Discord's switches, under Discord's names.
        const proc = [];
        if (c.krisp && v.noiseCancellation !== null) proc.push({
            icon: root._box(v.noiseCancellation), iconColor: root._tick(v.noiseCancellation),
            label: Translation.tr("Noise suppression (Krisp)"),
            onTriggered: () => cmd("noiseCancellation", !v.noiseCancellation)
        });
        if (c.noise && v.noiseSuppression !== null) proc.push({
            icon: root._box(v.noiseSuppression), iconColor: root._tick(v.noiseSuppression),
            label: Translation.tr("Noise suppression (standard)"),
            onTriggered: () => cmd("noiseSuppression", !v.noiseSuppression)
        });
        if (c.echo && v.echoCancellation !== null) proc.push({
            icon: root._box(v.echoCancellation), iconColor: root._tick(v.echoCancellation),
            label: Translation.tr("Echo cancellation"),
            onTriggered: () => cmd("echoCancellation", !v.echoCancellation)
        });
        if (c.agc && v.automaticGainControl !== null) proc.push({
            icon: root._box(v.automaticGainControl), iconColor: root._tick(v.automaticGainControl),
            label: Translation.tr("Automatic gain control"),
            onTriggered: () => cmd("automaticGainControl", !v.automaticGainControl)
        });
        if (proc.length) items.push({ icon: "tune", label: Translation.tr("Voice processing"), submenu: proc });

        // Levels and devices
        const lv = [];
        if (c.volume && v.inputVolume !== null) lv.push({
            slider: true, icon: "mic", value: Math.min(1, v.inputVolume / 100),
            valueText: x => `${Math.round(x * 100)}%`,
            onMoved: x => cmd("inputVolume", Math.round(x * 100))
        });
        if (c.volume && v.outputVolume !== null) lv.push({
            // Discord lets output go to 200 %
            slider: true, icon: "volume_up", value: Math.min(1, v.outputVolume / 200),
            valueText: x => `${Math.round(x * 200)}%`,
            onMoved: x => cmd("outputVolume", Math.round(x * 200))
        });
        if (c.device && (v.inputDevices ?? []).length > 1) lv.push({ separator: true }, {
            icon: "settings_voice", label: Translation.tr("Input device"),
            submenu: v.inputDevices.map(d => ({
                icon: root._check(d.id === v.inputDevice), iconColor: root._tick(d.id === v.inputDevice),
                label: d.name, onTriggered: () => cmd("inputDevice", d.id)
            }))
        });
        if (c.device && (v.outputDevices ?? []).length > 1) lv.push({
            icon: "speaker", label: Translation.tr("Output device"),
            submenu: v.outputDevices.map(d => ({
                icon: root._check(d.id === v.outputDevice), iconColor: root._tick(d.id === v.outputDevice),
                label: d.name, onTriggered: () => cmd("outputDevice", d.id)
            }))
        });
        if (lv.length) items.push({ icon: "equalizer", label: Translation.tr("Volume & devices"), submenu: lv });
        return items;
    }

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
            // special:minimized is the minimize workspace (hypr custom/scripts/minimize.sh).
            const minimized = d?.workspace?.name === "special:minimized";
            out.push(minimized ? {
                icon: "open_in_full", label: Translation.tr("Restore"),
                onTriggered: () => {
                    const here = HyprlandData.activeWorkspace?.id;
                    if (here !== undefined) HyprDispatch.run(`movetoworkspace ${here}, address:${addr}`);
                    HyprDispatch.run(`focuswindow address:${addr}`);
                }
            } : {
                icon: "minimize", label: Translation.tr("Minimize"),
                onTriggered: () => HyprDispatch.run(`movetoworkspacesilent special:minimized, address:${addr}`)
            });
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

    // How loud the mic reaches THIS app, and muting it for this app only - the
    // system mic and every other app are untouched.
    function _micItems() {
        const auds = root._micAudios();
        if (auds.length === 0) return [];
        const muted = auds.every(a => a.muted);
        const set = v => { for (const a of root._micAudios()) a.volume = v; };
        const out = [{
            icon: muted ? "mic_off" : "mic",
            iconColor: root._tick(muted),
            label: muted ? Translation.tr("Unmute for this app") : Translation.tr("Mute for this app"),
            onTriggered: () => { for (const a of root._micAudios()) a.muted = !muted; }
        }, { separator: true }, {
            slider: true,
            icon: "mic",
            value: Math.min(1, root._micLevel(auds)),
            onMoved: v => set(v)
        }, { separator: true }];
        const cur = Math.round(root._micLevel(auds) * 100);
        for (const pct of [100, 75, 50, 25])
            out.push({
                icon: root._check(cur === pct), iconColor: root._tick(cur === pct),
                label: `${pct}%`,
                onTriggered: () => set(pct / 100)
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

        // Left/right. A stereo stream only; the slider's middle is centre, and
        // the three presets are there because centre is the one you come back to.
        if (AppVolumes.canBalance(root.volRow)) {
            const bal = AppVolumes.balanceFor(root.volRow);
            const side = Math.abs(bal) < 0.05 ? 0 : (bal < 0 ? -1 : 1);
            out.push({ separator: true }, {
                slider: true,
                icon: "swap_horiz",
                value: (bal + 1) / 2,
                valueText: v => {
                    const b = v * 2 - 1;
                    if (Math.abs(b) < 0.05) return Translation.tr("Mid");
                    return (b < 0 ? "L " : "R ") + Math.round(Math.abs(b) * 100);
                },
                onMoved: v => AppVolumes.setBalance(root.volRow, v * 2 - 1)
            });
            for (const [label, target, dir] of [
                    [Translation.tr("Left"), -1, -1],
                    [Translation.tr("Centre"), 0, 0],
                    [Translation.tr("Right"), 1, 1]])
                out.push({
                    icon: root._check(side === dir), iconColor: root._tick(side === dir),
                    label: label,
                    onTriggered: () => AppVolumes.setBalance(root.volRow, target)
                });
        }

        // Play this app into the call (MicShare). Only for a playing app: the
        // share follows its process binary, which only a live stream reports.
        const bin = root._shareBinary;
        if (root.volLive && bin) {
            const shared = root.sharedToMic;
            out.push({ separator: true }, {
                icon: "podcasts",
                iconColor: root._tick(shared),
                label: shared ? Translation.tr("Playing into your mic") : Translation.tr("Play into mic"),
                onTriggered: () => {
                    // First use creates the virtual mic; the mic panel says
                    // how to pick it in Discord, which nothing can do for you.
                    if (!MicShare.enabled) { MicShare.setEnabled(true); GlobalStates.micOpen = true }
                    MicShare.setShared(bin, !shared);
                }
            });
        }

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

        // Discord's own voice settings, through the IIVoiceOverlay plugin —
        // the same switches as its Voice & Video page, saved the same way.
        if (/discord/i.test(root.appId)) {
            const v = DiscordVoice.settings;
            if (v) {
                out.push(...root._discordVoiceItems(v), { separator: true });
            } else if (tl.length > 0) {
                out.push({
                    icon: "extension_off", label: Translation.tr("Voice controls: restart Discord"),
                    onTriggered: () => {}
                }, { separator: true });
            }
        }

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

        // Browser downloads in progress (Downloads watches the .part files).
        if (/zen|firefox|tela/i.test(root.appId) && Downloads.count > 0)
            out.push({
                icon: "download",
                label: Translation.tr("Downloading %1 — %2/s").arg(Downloads.count)
                    .arg(StringUtils.formatBytes(Downloads.totalSpeed)),
                submenu: [
                    ...Downloads.active.map(d => ({
                        icon: "draft",
                        label: `${d.name} · ${StringUtils.formatBytes(d.size)}`
                            + (d.speed > 0 ? ` · ${StringUtils.formatBytes(d.speed)}/s` : ""),
                        onTriggered: () => Quickshell.execDetached(["xdg-open", d.path.slice(0, d.path.lastIndexOf("/"))])
                    })),
                    { separator: true },
                    {
                        icon: "folder_open", label: Translation.tr("Open Downloads folder"),
                        onTriggered: () => Quickshell.execDetached(["xdg-open", Downloads.dirs[0]])
                    }
                ]
            });

        // The YouTube Music presence the BetterDiscord plugin sets.
        if (/discord/i.test(root.appId))
            out.push({
                icon: "music_note", label: Translation.tr("Presence settings…"),
                onTriggered: () => { GlobalStates.discordPresenceOpen = true; }
            });

        // Clears the dock badge: the app's notifications in the history.
        const unread = AppBadges.countFor(root.appId);
        if (unread > 0)
            out.push({
                icon: "notifications_off",
                label: Translation.tr("Clear notifications (%1)").arg(unread),
                onTriggered: () => AppBadges.clearFor(root.appId)
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

        const mics = root._micAudios();
        if (mics.length > 0) {
            const micMuted = mics.every(a => a.muted);
            out.push({
                icon: micMuted ? "mic_off" : "mic",
                label: micMuted ? Translation.tr("Microphone — muted")
                    : Translation.tr("Microphone — %1%").arg(Math.round(root._micLevel(mics) * 100)),
                submenu: root._micItems()
            });
        }

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
