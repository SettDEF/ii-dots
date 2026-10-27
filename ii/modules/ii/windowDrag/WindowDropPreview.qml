// While a tiled window is dragged (Super+mouse): where it will land, by the workspace's layout.
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland

Scope {
    id: root

    // Hyprland sends windowDrag on the press and the release of its own drag bind (GlobalStates)
    readonly property bool active: GlobalStates.windowDragging && (Config.options.windowDrag?.preview ?? true)

    // the windows when the drag began, and the one being dragged (null: a floating one, no preview)
    property var clients: []
    property var dragged: null
    property point cursor: Qt.point(0, 0)
    // { rect: [x, y, w, h] in global layout coordinates, label, icon }, or null
    readonly property var drop: root.dragged ? root.dropAt(root.cursor) : null

    // The windows as they were before the drag: Super always goes down first. (Once the drag has
    // begun, Hyprland reports the dragged tiled window as floating.)
    readonly property bool watching: (Config.options.windowDrag?.preview ?? true) && GlobalStates.superDown
    onWatchingChanged: if (watching) hypr.request("j/clients", text => {
        try { root.clients = JSON.parse(text); } catch (e) { root.clients = []; }
    })

    onActiveChanged: {
        if (active) {
            root.dragged = null;
            root.pickDragged = true;
        } else {
            root.dragged = null;
            root.pickDragged = false;
        }
    }
    // the first cursor reading after the press names the dragged window
    property bool pickDragged: false

    Timer {
        // ~30 a second while dragging; a reading still on its way is not doubled up
        interval: 33
        repeat: true
        running: root.active
        onTriggered: if (!hypr.busy) hypr.request("cursorpos", text => {
            const m = text.match(/(-?\d+),\s*(-?\d+)/);
            if (!m || !root.active) return;
            root.cursor = Qt.point(parseInt(m[1]), parseInt(m[2]));
            if (root.pickDragged) {
                root.pickDragged = false;
                const w = root.windowAt(root.cursor, true);
                root.dragged = w && !w.floating ? w : null;
            }
        })
    }

    function inside(w, p) {
        return p.x >= w.at[0] && p.x < w.at[0] + w.size[0] && p.y >= w.at[1] && p.y < w.at[1] + w.size[1];
    }

    // the window under a point on a shown workspace (floating ones first, as they sit on top)
    function windowAt(p, anyKind) {
        const shown = Hyprland.monitors.values.map(m => m.activeWorkspace?.id);
        const under = root.clients.filter(w => w.mapped && !w.hidden && shown.includes(w.workspace.id) && root.inside(w, p));
        if (anyKind) return under.find(w => w.floating) ?? under[0] ?? null;
        return under.find(w => !w.floating && !w.fullscreen && w.address !== root.dragged?.address) ?? null;
    }

    function dropAt(p) {
        const t = root.windowAt(p, false);
        // over no other tiled window: dropped there, it goes back to its own place
        if (!t) {
            const d = root.dragged;
            return d ? { rect: [d.at[0], d.at[1], d.size[0], d.size[1]], icon: "undo", label: Translation.tr("Back to its place") } : null;
        }
        const [x, y] = t.at;
        const [w, h] = t.size;
        const suit = LayoutService.layoutFor(t.workspace.name);
        if (suit === "dwindle") {
            // Hyprland's dwindle splits the window under the cursor: side by side when it is
            // wider than tall, and the new half on the cursor's side
            if (w >= h) {
                const left = p.x < x + w / 2;
                return { rect: [left ? x : x + w / 2, y, w / 2, h], icon: left ? "border_left" : "border_right", label: Translation.tr("Split") };
            }
            const top = p.y < y + h / 2;
            return { rect: [x, top ? y : y + h / 2, w, h / 2], icon: top ? "border_top" : "border_bottom", label: Translation.tr("Split") };
        }
        return { rect: [x, y, w, h], icon: "swap_horiz", label: Translation.tr("Take this place") };
    }

    // One request on Hyprland's command socket at a time: no process per reading.
    Socket {
        id: hypr
        property var callback: null
        property string reply: ""
        readonly property bool busy: callback !== null
        property string pending: ""
        path: `${Quickshell.env("XDG_RUNTIME_DIR")}/hypr/${Quickshell.env("HYPRLAND_INSTANCE_SIGNATURE")}/.socket.sock`

        function request(cmd, cb) {
            if (hypr.busy) return;
            hypr.callback = cb;
            hypr.reply = "";
            hypr.pending = cmd;
            hypr.connected = true;
        }
        onConnectedChanged: {
            if (connected) {
                hypr.write(hypr.pending);
                hypr.flush();
            } else if (hypr.callback) {
                // Hyprland answers, then closes the connection
                const cb = hypr.callback;
                hypr.callback = null;
                cb(hypr.reply);
            }
        }
        parser: SplitParser {
            splitMarker: ""
            onRead: data => hypr.reply += data
        }
    }

    // The preview, on the monitor under the cursor; unmapped when there is nothing to show.
    Variants {
        model: Quickshell.screens

        PanelWindow {
            id: win
            required property ShellScreen modelData
            screen: modelData
            // the screen goes null for a moment while a monitor is unplugged
            readonly property var mon: modelData ? (Hyprland.monitors.values.find(m => m.name === modelData.name) ?? null) : null
            readonly property bool here: root.drop !== null && win.mon !== null && !!modelData
                && root.cursor.x >= win.mon.x && root.cursor.x < win.mon.x + modelData.width
                && root.cursor.y >= win.mon.y && root.cursor.y < win.mon.y + modelData.height

            visible: win.here || frame.opacity > 0
            color: "transparent"
            exclusionMode: ExclusionMode.Ignore
            WlrLayershell.namespace: "quickshell:windowDropPreview"
            WlrLayershell.layer: WlrLayer.Overlay
            anchors { top: true; bottom: true; left: true; right: true }
            // never takes the pointer: the drag goes on underneath
            mask: Region {}

            Rectangle {
                id: frame
                readonly property var r: root.drop?.rect ?? [0, 0, 0, 0]
                readonly property real inset: 6
                x: r[0] - (win.mon?.x ?? 0) + inset
                y: r[1] - (win.mon?.y ?? 0) + inset
                width: Math.max(0, r[2] - 2 * inset)
                height: Math.max(0, r[3] - 2 * inset)
                radius: Appearance.rounding.large
                color: Qt.alpha(Appearance.colors.colPrimary, 0.16)
                border.width: 3
                border.color: Qt.alpha(Appearance.colors.colPrimary, 0.85)
                opacity: win.here ? 1 : 0

                Behavior on opacity { NumberAnimation { duration: 120 } }
                Behavior on x { enabled: frame.opacity > 0; NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }
                Behavior on y { enabled: frame.opacity > 0; NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }
                Behavior on width { enabled: frame.opacity > 0; NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }
                Behavior on height { enabled: frame.opacity > 0; NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }

                // what the drop does, in the middle
                Rectangle {
                    anchors.centerIn: parent
                    implicitWidth: chipRow.implicitWidth + 28
                    implicitHeight: chipRow.implicitHeight + 14
                    radius: Appearance.rounding.full
                    color: Appearance.colors.colPrimary
                    Row {
                        id: chipRow
                        anchors.centerIn: parent
                        spacing: 8
                        MaterialSymbol {
                            anchors.verticalCenter: parent.verticalCenter
                            text: root.drop?.icon ?? ""
                            iconSize: 20
                            color: Appearance.colors.colOnPrimary
                        }
                        StyledText {
                            anchors.verticalCenter: parent.verticalCenter
                            text: root.drop?.label ?? ""
                            font.pixelSize: Appearance.font.pixelSize.small
                            color: Appearance.colors.colOnPrimary
                        }
                    }
                }
            }
        }
    }
}
