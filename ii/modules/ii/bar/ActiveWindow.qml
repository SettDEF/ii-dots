import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland

Item {
    id: root
    readonly property HyprlandMonitor monitor: Hyprland.monitorFor(root.QsWindow.window?.screen)
    readonly property Toplevel activeWindow: ToplevelManager.activeToplevel

    property string activeWindowAddress: `0x${activeWindow?.HyprlandToplevel?.address}`
    property bool focusingThisMonitor: HyprlandData.activeWorkspace?.monitor == monitor?.name
    property var biggestWindow: HyprlandData.biggestWindowForWorkspace(HyprlandData.monitors[root.monitor?.id]?.activeWorkspace.id)

    readonly property bool hasActive: !!(focusingThisMonitor && activeWindow?.activated && biggestWindow)
    property bool actionsOpen: false

    readonly property real titleHeight:    30
    readonly property real resourcesHeight: 38
    readonly property real actionButtonsHeight: 36
    readonly property real actionsHeight: resourcesHeight + actionButtonsHeight + 4

    implicitWidth: hole.implicitWidth + 2

    // Click-anywhere-else dismisser when actions are open
    Connections {
        target: GlobalFocusGrab
        function onDismissed() { if (root.actionsOpen) root.actionsOpen = false }
    }
    onActionsOpenChanged: {
        if (actionsOpen) GlobalFocusGrab.addDismissable(root)
        else GlobalFocusGrab.removeDismissable(root)
    }

    // ── Single pill, grows downward when expanded ────────────────────────
    // The whole shape (title row + action row) is one Rectangle so it
    // visually reads as one element opening up.
    Rectangle {
        id: hole
        // Pin the TOP of the pill to a stable position (the row's vertical
        // center, offset up by half the title height) so the title row
        // never moves while the pill grows downward when actions open.
        // Using only one anchor means just one animated dimension —
        // implicitHeight — which gives a single, perfectly smooth reveal.
        anchors.top: parent.verticalCenter
        anchors.topMargin: -root.titleHeight / 2
        anchors.horizontalCenter: parent.horizontalCenter

        implicitWidth: Math.min(holeRow.implicitWidth + 22, 360)
        // Animate width changes (different apps have different title lengths)
        // so the pill grows/shrinks smoothly when the focused window changes.
        Behavior on implicitWidth {
            NumberAnimation { duration: 280; easing.type: Easing.InOutCubic }
        }
        implicitHeight: root.titleHeight + (root.actionsOpen ? root.actionsHeight : 0)
        Behavior on implicitHeight {
            NumberAnimation { duration: 220; easing.type: Easing.OutCubic }
        }

        radius: root.actionsOpen ? 14 : (height / 2)
        Behavior on radius { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }

        color: Qt.darker(Appearance.colors.colLayer0Base, 1.18)
        border.width: 1
        border.color: Qt.alpha("black", 0.35)
        clip: true

        // Tap handlers
        HoverHandler { id: holeHov }
        TapHandler {
            acceptedButtons: Qt.LeftButton
            // Only react to taps in the title row (top portion); taps inside
            // the action row are handled by their own buttons.
            onTapped: (eventPoint) => {
                if (eventPoint.position.y <= root.titleHeight)
                    root.actionsOpen = !root.actionsOpen
            }
        }

        // ── Title row (always visible, fixed at top) ─────────────────
        Item {
            id: titleArea
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            height: root.titleHeight

            RowLayout {
                id: holeRow
                anchors.fill: parent
                anchors.leftMargin: 12
                anchors.rightMargin: 12
                spacing: 8

                Rectangle {
                    Layout.alignment: Qt.AlignVCenter
                    implicitWidth: 6; implicitHeight: 6; radius: 3
                    color: root.hasActive
                        ? Appearance.m3colors.m3primary
                        : Appearance.colors.colSubtext
                    SequentialAnimation on scale {
                        id: pulse
                        running: false
                        NumberAnimation { from: 1; to: 1.6; duration: 140; easing.type: Easing.OutCubic }
                        NumberAnimation { from: 1.6; to: 1; duration: 220; easing.type: Easing.OutCubic }
                    }
                }

                StyledText {
                    id: appText
                    Layout.fillHeight: true
                    Layout.alignment: Qt.AlignVCenter
                    visible: !!text
                    text: root.hasActive
                        ? (root.activeWindow?.appId ?? "")
                        : ((root.biggestWindow?.class) ?? Translation.tr("Desktop"))
                    font.pixelSize: Appearance.font.pixelSize.small
                    color: Appearance.colors.colSubtext
                    elide: Text.ElideRight
                    verticalAlignment: Text.AlignVCenter
                    Layout.maximumWidth: 80
                }

                Rectangle {
                    Layout.alignment: Qt.AlignVCenter
                    Layout.preferredWidth: 1
                    Layout.preferredHeight: root.titleHeight - 12
                    color: Qt.alpha(Appearance.colors.colOnLayer0, 0.28)
                    visible: appText.visible && titleText.text.length > 0
                }

                StyledText {
                    id: titleText
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    Layout.alignment: Qt.AlignVCenter
                    text: root.hasActive
                        ? (root.activeWindow?.title ?? "")
                        : ((root.biggestWindow?.title) ?? `${Translation.tr("Workspace")} ${monitor?.activeWorkspace?.id ?? 1}`)
                    font.pixelSize: Appearance.font.pixelSize.small
                    font.weight: Font.Medium
                    color: Appearance.colors.colOnLayer0
                    elide: Text.ElideRight
                    verticalAlignment: Text.AlignVCenter
                }
            }

            Connections {
                target: titleText
                function onTextChanged() { pulse.start() }
            }
        }

        // Hairline separator between title row and action row.
        // Always rendered at the same place; the parent's clip + height
        // animation reveals it smoothly as the pill grows.
        Rectangle {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.leftMargin: 8
            anchors.rightMargin: 8
            anchors.top: titleArea.bottom
            height: 1
            color: Qt.alpha("white", 0.06)
        }

        // ── Drop-down area (revealed below the title) ─────────────────
        // Top: Resources (CPU/RAM/GPU). Bottom: per-app action buttons.
        // Fixed full height so contents don't reflow during animation —
        // the parent Rectangle's `clip: true` + height animation does the
        // reveal in one continuous motion.
        Item {
            id: actionsArea
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: titleArea.bottom
            height: root.actionsHeight

            // Lazy: don't instantiate (and start polling) the Resources
            // panel until the dropdown is actually opening. Otherwise live
            // polling forces a re-render every frame inside the clipped,
            // animating parent — which is what was causing the perceived
            // lag during the height animation.
            Loader {
                id: dropResources
                anchors {
                    left: parent.left
                    right: parent.right
                    top: parent.top
                    leftMargin: 8
                    rightMargin: 8
                    topMargin: 2
                }
                height: root.resourcesHeight
                active: root.actionsOpen
                asynchronous: true
                sourceComponent: Resources {
                    alwaysShowAllResources: false
                }
            }

            RowLayout {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: dropResources.bottom
                anchors.bottom: parent.bottom
                anchors.leftMargin: 6
                anchors.rightMargin: 6
                anchors.bottomMargin: 4
                anchors.topMargin: 2
                spacing: 2

                Repeater {
                    model: root.actionButtons
                    delegate: Rectangle {
                        required property var modelData
                        Layout.alignment: Qt.AlignVCenter
                        Layout.fillWidth: true
                        implicitHeight: 26
                        radius: height / 2
                        color: actHov.hovered ? Qt.alpha("white", 0.08) : "transparent"
                        Behavior on color { ColorAnimation { duration: 120 } }

                        HoverHandler { id: actHov }
                        TapHandler {
                            onTapped: {
                                modelData.action()
                                if (!modelData.keepOpen) root.actionsOpen = false
                            }
                        }
                        MaterialSymbol {
                            anchors.centerIn: parent
                            text: modelData.icon
                            iconSize: 14
                            color: Appearance.colors.colOnLayer0
                        }
                    }
                }
            }
        }
    }

    function runCmd(line) { Quickshell.execDetached(["bash", "-c", line]) }

    // Send a desktop notification via the system notification daemon.
    // The Notifications service in qs.services receives it and shows the
    // toast in your existing notification area.
    function notify(title, body, icon) {
        const args = ["notify-send", "-a", "Quickshell", "-t", "2500"]
        if (icon) { args.push("-i"); args.push(icon) }
        args.push(title)
        if (body) args.push(body)
        Quickshell.execDetached(args)
    }

    readonly property var actionButtons: [
        // 📷 Screenshot — grimblast already shows its own --notify toast.
        // For the fallback paths we push our own.
        { icon: "photo_camera", keepOpen: false, action: () => {
            root.runCmd(
                "set -e; mkdir -p ~/Pictures/Screenshots; " +
                "out=~/Pictures/Screenshots/$(date +%Y-%m-%d_%H-%M-%S).png; " +
                "if command -v grimblast >/dev/null; then " +
                "  grimblast --notify copysave active \"$out\"; " +
                "elif command -v hyprshot >/dev/null; then " +
                "  hyprshot -m active -o ~/Pictures/Screenshots && " +
                "  notify-send -a Quickshell -i camera-photo \"Screenshot saved\" \"$out\"; " +
                "else " +
                "  geom=$(hyprctl -j activewindow | python3 -c 'import json,sys;w=json.load(sys.stdin);print(\"%d,%d %dx%d\" % (w[\"at\"][0],w[\"at\"][1],w[\"size\"][0],w[\"size\"][1]))'); " +
                "  grim -g \"$geom\" \"$out\" && wl-copy < \"$out\" && " +
                "  notify-send -a Quickshell -i camera-photo \"Screenshot saved\" \"$out\"; " +
                "fi"
            )
        }},

        // 💬 Copy title
        { icon: "title", keepOpen: false, action: () => {
            const t = root.activeWindow?.title ?? root.biggestWindow?.title ?? ""
            Quickshell.clipboardText = t
            root.notify("Title copied", t, "edit-copy")
        }},

        // 🏷 Copy class / appId
        { icon: "tag", keepOpen: false, action: () => {
            const c = root.activeWindow?.appId ?? root.biggestWindow?.class ?? ""
            Quickshell.clipboardText = c
            root.notify("App ID copied", c, "edit-copy")
        }},

        // 🔇 Mute / unmute the focused app's sink-inputs. The shell snippet
        // toggles the mute and reports back via notify-send.
        { icon: "volume_off", keepOpen: true, action: () => {
            root.runCmd(
                "pid=$(hyprctl -j activewindow | python3 -c 'import json,sys;print(json.load(sys.stdin).get(\"pid\",\"\"))'); " +
                "[ -z \"$pid\" ] && exit 0; " +
                "found=0; muted_after=0; " +
                "for s in $(pactl list sink-inputs | grep -B25 \"application.process.id = \\\"$pid\\\"\" | grep '^Sink Input #' | awk '{print $3}' | tr -d '#'); do " +
                "  found=1; pactl set-sink-input-mute $s toggle; " +
                "  state=$(pactl get-sink-input-mute $s | awk '{print $2}'); " +
                "  [ \"$state\" = \"yes\" ] && muted_after=1; " +
                "done; " +
                "if [ \"$found\" = \"1\" ]; then " +
                "  if [ \"$muted_after\" = \"1\" ]; then " +
                "    notify-send -a Quickshell -i audio-volume-muted 'Muted' \"$(hyprctl -j activewindow | python3 -c 'import json,sys;print(json.load(sys.stdin).get(\\\"title\\\",\\\"\\\"))')\"; " +
                "  else " +
                "    notify-send -a Quickshell -i audio-volume-high 'Unmuted' \"$(hyprctl -j activewindow | python3 -c 'import json,sys;print(json.load(sys.stdin).get(\\\"title\\\",\\\"\\\"))')\"; " +
                "  fi; " +
                "else " +
                "  notify-send -a Quickshell -i audio-volume-muted 'No audio' 'This window is not playing audio'; " +
                "fi"
            )
        }},

        // 📌 Pin / unpin
        { icon: "push_pin",   keepOpen: true,  action: () => {
            Hyprland.dispatch("pin")
            root.notify("Pin toggled", root.activeWindow?.title ?? "", "view-pin")
        }},

        // ⛶ Toggle fullscreen
        { icon: "fullscreen", keepOpen: true,  action: () => {
            Hyprland.dispatch("fullscreen 1")
            root.notify("Fullscreen toggled", root.activeWindow?.title ?? "", "view-fullscreen")
        }},

        // ✋ Toggle floating
        { icon: "drag_pan",   keepOpen: true,  action: () => {
            Hyprland.dispatch("togglefloating")
            root.notify("Float toggled", root.activeWindow?.title ?? "", "object-flip-horizontal")
        }},

        // ✕ Close
        { icon: "close",      keepOpen: false, action: () => {
            const t = root.activeWindow?.title ?? ""
            Hyprland.dispatch("closewindow activewindow")
            root.notify("Closing window", t, "window-close")
        }},
    ]
}
