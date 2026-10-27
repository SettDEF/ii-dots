// Super+right-drag on a workspace with a Lua layout (AwesomeWM's fair and corner suits): Hyprland
// has no resize hook for Lua layouts and undoes its own resize, so the drag moves the layout's
// split (mwfact) instead, live while the button is held.
import qs
import qs.modules.common
import QtQuick
import Quickshell
import Quickshell.Io

Scope {
    id: root

    readonly property bool active: GlobalStates.windowResizing
    // set when the drag began on a Lua-layout workspace
    property bool following: false
    property string suit: ""
    property real start: 0.5
    property real sent: 0.5
    property real width: 1
    property real x0: NaN

    FileView {
        id: stateFile
        path: `${Quickshell.env("HOME")}/.cache/hypr-awesome.json`
        blockLoading: true
    }

    onActiveChanged: {
        root.following = false;
        root.x0 = NaN;
        if (!active)
            return;
        hypr.request("j/activeworkspace", text => {
            let ws;
            try { ws = JSON.parse(text); } catch (e) { return; }
            if (!root.active || ws.tiledLayout !== "lua:awesomewm")
                return;
            stateFile.reload();
            let s = {};
            try { s = JSON.parse(stateFile.text())[ws.name] ?? {}; } catch (e) {}
            // fair has no split to move; corner and the rest have one
            if (!s.suit || s.suit === "fair" || s.suit === "fairh")
                return;
            root.suit = s.suit;
            root.start = s.mwfact ?? 0.5;
            root.sent = root.start;
            // a floating window resizes itself: the tiles under it keep their split (the window
            // under the pointer is the focused one, follow_mouse)
            hypr.request("j/activewindow", at => {
                let w = {};
                try { w = JSON.parse(at); } catch (e) {}
                if (!root.active || w.floating)
                    return;
                hypr.request("j/monitors", mt => {
                    try {
                        const m = JSON.parse(mt).find(x => x.focused);
                        root.width = m ? m.width / m.scale : 1600;
                    } catch (e) {}
                    root.following = root.active;
                });
            });
        });
    }

    Timer {
        // ~30 a second while the drag lasts
        interval: 33
        repeat: true
        running: root.following
        onTriggered: if (!hypr.busy) hypr.request("cursorpos", text => {
            const m = text.match(/(-?\d+),\s*(-?\d+)/);
            if (!m || !root.following) return;
            const x = parseInt(m[1]);
            if (isNaN(root.x0)) {
                root.x0 = x;
                return;
            }
            // the master on the right (cornerne, cornerse): dragging left grows it
            const right = root.suit === "cornerne" || root.suit === "cornerse";
            const dx = (x - root.x0) / Math.max(1, root.width);
            const v = Math.max(0.05, Math.min(0.95, root.start + (right ? -dx : dx)));
            // the previous command still on its way: this value goes with the next reading
            if (Math.abs(v - root.sent) < 0.005 || send.busy) return;
            root.sent = v;
            send.request(`eval package.loaded["lua.awesome_layouts"].cmd("mwfact ${v.toFixed(3)}")`, () => {});
        })
    }

    component HyprSocket: Socket {
        id: sock
        property var callback: null
        property string reply: ""
        readonly property bool busy: callback !== null
        property string pending: ""
        path: `${Quickshell.env("XDG_RUNTIME_DIR")}/hypr/${Quickshell.env("HYPRLAND_INSTANCE_SIGNATURE")}/.socket.sock`

        function request(cmd, cb) {
            if (sock.busy) return;
            sock.callback = cb;
            sock.reply = "";
            sock.pending = cmd;
            sock.connected = true;
        }
        onConnectedChanged: {
            if (connected) {
                sock.write(sock.pending);
                sock.flush();
            } else if (sock.callback) {
                // Hyprland answers, then closes the connection
                const cb = sock.callback;
                sock.callback = null;
                cb(sock.reply);
            }
        }
        parser: SplitParser {
            splitMarker: ""
            onRead: data => sock.reply += data
        }
    }

    // readings and commands on separate connections, so a slow command never skips a reading
    HyprSocket { id: hypr }
    HyprSocket { id: send }
}
