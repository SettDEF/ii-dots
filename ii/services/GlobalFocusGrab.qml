pragma Singleton
pragma ComponentBehavior: Bound
import qs.services
import QtQuick
import Quickshell
import Quickshell.Hyprland

/**
 * Manages a HyprlandFocusGrab that's to be shared by all windows.
 * "Persistent" is for windows that should always be included but not closed on dismiss, like bar and onscreen keyboard.
 * "Dismissable" is for stuff like sidebars
 */ 
Singleton {
    id: root

    signal dismissed()

    property list<var> persistent: []
    property list<var> dismissable: []

    function dismiss() {
        root.dismissable = [];
        root.dismissed();
    }

    Component.onCompleted: {
        console.log("[GlobalFocusGrab] Initialized");
    }

    // Release the Hyprland focus grab cleanly when Quickshell tears down
    // (every config reload). Without this, an active grab is left dangling
    // — Hyprland keeps a grab on now-destroyed windows, so keyboard and
    // click input go nowhere and you can't type until focus is forced back.
    Component.onDestruction: {
        root.dismissable = [];
        root.persistent = [];
        grab.active = false;
    }

    function addPersistent(window) {
        if (root.persistent.indexOf(window) === -1) {
            const list = [...root.persistent];
            list.push(window);
            root.persistent = list;
        }
    }

    function removePersistent(window) {
        var index = root.persistent.indexOf(window);
        if (index !== -1) {
            const list = [...root.persistent];
            list.splice(index, 1);
            root.persistent = list;
        }
    }

    function addDismissable(window) {
        if (root.dismissable.indexOf(window) === -1) {
            const list = [...root.dismissable];
            list.push(window);
            root.dismissable = list;
        }
    }

    function removeDismissable(window) {
        var index = root.dismissable.indexOf(window);
        if (index !== -1) {
            const list = [...root.dismissable];
            list.splice(index, 1);
            root.dismissable = list;
        }
    }

    // ── Give focus back to a fullscreen window after the grab ends ───────
    // XWayland games turn X11's XGrabPointer into a Wayland pointer
    // constraint. Taking a focus grab (any quickshell panel opening) breaks
    // that constraint, and the game only re-acquires it when it regains
    // focus — otherwise the in-game cursor stays dead until you switch
    // workspaces. So: remember what was focused before we grab, and hand
    // focus back when the last panel closes.
    //
    // This used to be gated on the window being *fullscreen*, to avoid fighting
    // a click that deliberately moved focus elsewhere. That gate was both too
    // narrow and aimed at the wrong thing: a borderless/"fullscreen windowed"
    // game reports fullscreen 0, so the address was never even recorded and the
    // repair silently never ran.
    //
    // The thing actually worth distinguishing is not the window's geometry but
    // HOW the panel closed. Esc or a keybind is a pure dismissal with no new
    // focus target, so restoring is right. A click outside picked a window on
    // purpose, so restoring would undo the user's choice — `grabCleared` marks
    // that case and skips it.
    property string restoreAddress: ""
    // Set only for the duration of a click-outside dismissal.
    property bool grabCleared: false
    property bool restoreNeedsCursor: false
    // Workspace that was active when the grab began. Used to notice a switch
    // made *while* a panel is open — e.g. Hyprland's own workspace keybinds,
    // which bypass every panel code path — and drop the restore for it.
    property int restoreWorkspace: -1

    // Call BEFORE closing a panel in order to navigate somewhere — switch
    // workspace, focus another window. For the same-tick case (a click that
    // closes the overview and dispatches in one go) this must be explicit:
    // HyprlandData still holds the pre-navigation state, so nothing else here
    // could detect it, and the restore below would drag focus straight back.
    function cancelRestore() {
        root.restoreAddress = "";
    }

    // The keybind case is different: the panel stays open and the workspace
    // genuinely changes with time to spare before it closes. Watch for that
    // and cancel the pending restore as soon as it happens.
    Connections {
        target: HyprlandData
        function onActiveWorkspaceChanged() {
            if (root.dismissable.length === 0) return;
            if (root.restoreAddress.length === 0) return;
            const id = HyprlandData.activeWorkspace?.id ?? -1;
            if (root.restoreWorkspace >= 0 && id >= 0 && id !== root.restoreWorkspace) {
                console.log("[FocusGrab] workspace changed while open",
                            root.restoreWorkspace, "→", id, "— cancelling restore");
                root.restoreAddress = "";
            }
        }
    }

    onDismissableChanged: {
        if (root.dismissable.length > 0) {
            if (root.restoreAddress.length === 0) {
                const activeWsId = HyprlandData.activeWorkspace?.id ?? -1;
                const lastFocused = (HyprlandData.windowList ?? []).find(x => x.focusHistoryID === 0);
                // focusHistoryID 0 is the last-focused window GLOBALLY: on an
                // empty workspace it still points at the one we just left, and
                // restoring to it drags the compositor back there.
                const w = (lastFocused && lastFocused.workspace?.id === activeWsId) ? lastFocused : null;
                root.restoreAddress = w ? (w.address ?? "") : "";
                // Only clients that can hold a pointer constraint need the
                // cursor jiggle below; for an ordinary window refocusing alone
                // is enough, and a synthetic mouse move would be intrusive.
                root.restoreNeedsCursor = !!(w && (w.xwayland || w.fullscreen > 0));
                root.restoreWorkspace = activeWsId;
                console.log("[FocusGrab] grab ON — focused was:",
                            w ? (w.class + " fs=" + w.fullscreen + " xwl=" + w.xwayland
                                 + " " + w.address) : "none",
                            "| will restore:", root.restoreAddress || "(nothing)",
                            "| cursor kick:", root.restoreNeedsCursor);
            }
        } else if (root.grabCleared) {
            console.log("[FocusGrab] grab OFF — dismissed by click, leaving focus alone");
            root.restoreAddress = "";
        } else if (root.restoreAddress.length > 0) {
            const addr = root.restoreAddress;
            root.restoreAddress = "";
            console.log("[FocusGrab] grab OFF — restoring focus to", addr);
            // callLater: let Hyprland finish releasing the grab first.
            Qt.callLater(() => {
                HyprDispatch.run(`focuswindow address:${addr}`);
                // Focus alone doesn't make an XWayland game re-acquire its
                // pointer constraint, so also drop the cursor onto the window:
                // the pointer-enter is what prompts the client to re-lock.
                const w = (HyprlandData.windowList ?? []).find(x => x.address === addr);
                if (root.restoreNeedsCursor && w && w.at && w.size) {
                    const cx = Math.round(w.at[0] + w.size[0] / 2);
                    const cy = Math.round(w.at[1] + w.size[1] / 2);
                    HyprDispatch.run(`movecursor ${cx} ${cy}`);
                    // …then a REAL input event. `movecursor` is a
                    // compositor-side teleport: the pointer ends up inside the
                    // window, but the client never sees motion, so an XWayland
                    // game does not re-arm the pointer constraint that the
                    // focus grab broke. ydotool injects through uinput, which
                    // Hyprland processes as genuine movement — enter + motion
                    // — and that is what the client reacts to.
                    //
                    // +2/-2 nets to zero, so aim does not drift.
                    Quickshell.execDetached(["bash", "-c",
                        "command -v ydotool >/dev/null || exit 0; "
                        + "export YDOTOOL_SOCKET=${YDOTOOL_SOCKET:-/run/user/$(id -u)/.ydotool_socket}; "
                        + "sleep 0.12; ydotool mousemove -- 2 0; sleep 0.03; ydotool mousemove -- -2 0"]);
                }
            });
        } else {
            console.log("[FocusGrab] grab OFF — nothing to restore");
        }
    }

    HyprlandFocusGrab {
        id: grab
        windows: [...root.persistent, ...root.dismissable]
        active: root.dismissable.length > 0
        onCleared: () => {
            // dismiss() clears `dismissable`, which runs onDismissableChanged
            // synchronously — so the flag is read before it is put back.
            root.grabCleared = true;
            root.dismiss();
            root.grabCleared = false;
        }
    }

}

