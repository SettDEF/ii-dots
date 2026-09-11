import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
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
    // Hover-revealed, not click-toggled: these are the same weight of control
    // as the resource chips they sit beside, and a click you then have to undo
    // with another click is too much ceremony for three buttons.
    //
    // Held by a short timer rather than raw hover, so crossing the gap between
    // the pill and the first chip does not close the row under the pointer.
    // The open rebind menu counts as wanting it too, otherwise choosing a
    // replacement would dismiss the very row being edited.
    property bool actionsOpen: false
    readonly property bool actionsWanted:
        holeHov.hovered || chipsHov.hovered || slotMenu.visible
    onActionsWantedChanged: {
        if (root.actionsWanted) {
            actionsHide.stop();
            root.actionsOpen = true;
        } else {
            actionsHide.restart();
        }
    }
    Timer {
        id: actionsHide
        interval: 220
        onTriggered: root.actionsOpen = false
    }

    // Is there an application on this monitor's workspace at all? Deliberately
    // NOT `hasActive`: that goes false whenever focus moves to a shell surface,
    // which would make the leading icon flicker away mid-interaction. This only
    // flips on an actually empty workspace, which is when the bare dot shows.
    readonly property bool hasWindow: !!biggestWindow

    readonly property real titleHeight:    30

    // ── Resource warning ─────────────────────────────────────────────────
    // The CPU/RAM/swap readout is noise most of the time, so by default it
    // only appears once something is close to critical. Mode comes from
    // Config.options.bar.resources.showInWindowPill:
    //   0 = never   1 = only when near critical   2 = always
    // Optional-chained: this binding evaluates before Config's FileView has
    // populated `options`, and an undefined there would trip an int assign.
    readonly property int resourcesMode: Config.options?.bar?.resources?.showInWindowPill ?? 1
    readonly property real criticalAt: Config.options?.bar?.resources?.criticalThreshold ?? 85

    // Per-resource rather than one all-or-nothing flag: in the near-critical
    // mode only the resource actually in trouble appears, so the row names
    // the problem instead of making you read three numbers to find the one
    // that moved. Mode 2 shows all three regardless.
    function resourceShown(pct) {
        return root.resourcesMode === 2
            || (root.resourcesMode === 1 && pct * 100 >= root.criticalAt)
    }


    // ── Per-app quick actions ────────────────────────────────────────────
    // Three slots, not the whole catalogue. Nine unlabelled glyphs was a wall
    // to read every time, and most of them are wrong for any given app anyway.
    // So WHICH three is per application — the action worth reaching for on a
    // browser is not the one worth reaching for on a terminal — and a
    // right-click on a chip swaps it, putting the choice where it is noticed
    // instead of in a settings page nobody opens.
    readonly property int slotCount: 3
    readonly property var defaultSlotIds: ["screenshot", "fullscreen", "close"]

    // Keyed on appId/class so a choice follows the application rather than one
    // window of it. Empty when nothing is focused, which is when the row is
    // hidden anyway.
    readonly property string appKey: root.cleanLabel(root.hasActive
        ? (root.activeWindow?.appId ?? "")
        : (root.biggestWindow?.class ?? ""))

    // Parsed out of the persisted string on every read rather than cached, so
    // the binding re-evaluates when the map is rewritten — that is what
    // repaints the chips the instant a slot is reassigned.
    readonly property var slotIds: {
        const key = root.appKey;
        if (key.length === 0)
            return root.defaultSlotIds;
        let map = {};
        // A hand-edited (or half-written) states.json must not blank the row.
        try {
            map = JSON.parse(Persistent.states?.bar?.windowActionMap ?? "{}") ?? {};
        } catch (e) {
            map = {};
        }
        const saved = map[key];
        return (Array.isArray(saved) && saved.length === root.slotCount)
            ? saved : root.defaultSlotIds;
    }

    function actionById(id) {
        return root.actionCatalog.find(a => a.id === id) ?? null;
    }

    function assignSlot(index, id) {
        const key = root.appKey;
        if (key.length === 0)
            return;
        let map = {};
        try {
            map = JSON.parse(Persistent.states.bar.windowActionMap ?? "{}") ?? {};
        } catch (e) {
            map = {};
        }
        const next = root.slotIds.slice();
        next[index] = id;
        map[key] = next;
        // Assigning the whole string is what notifies: JsonAdapter watches the
        // property itself, not the object graph a parsed copy would live in.
        Persistent.states.bar.windowActionMap = JSON.stringify(map);
    }

    // Some apps prefix their window title with an invisible formatting
    // character. Zen Browser leads every title with U+180E (MONGOLIAN VOWEL
    // SEPARATOR): zero-width by spec, but the bar's font has no glyph for it,
    // so Qt draws a tofu box before the text.
    //
    // Only genuinely meaningless invisibles are stripped — U+180E, U+200B
    // (zero-width space), U+FEFF (BOM). Deliberately NOT stripped: U+200C and
    // U+200D. ZWNJ/ZWJ carry meaning in Indic and Arabic script and glue emoji
    // sequences together, so dropping them would corrupt real titles.
    function cleanLabel(s) {
        return (s ?? "").replace(/[\u180E\u200B\uFEFF]/g, "").trim()
    }

    implicitWidth: hole.implicitWidth + 2

    // No GlobalFocusGrab dismisser any more. It existed because the row was
    // click-toggled and so could be left open with the pointer elsewhere;
    // hover-driven, moving away is already the dismissal.

    // ── The title pill ───────────────────────────────────────────────────
    // Title row only. It used to hold the action row too and grow downward to
    // reveal it; the actions are their own chips below now, so this is a
    // fixed-height pill whose only animated dimension is width.
    Rectangle {
        id: hole
        // Pinned by its TOP (the row's vertical centre, offset up by half the
        // title height) rather than centred, so the title sits at a stable
        // height regardless of what is anchored beneath it.
        anchors.top: parent.verticalCenter
        anchors.topMargin: -root.titleHeight / 2
        // Left-aligned, not centered. This used to be horizontalCenter, which
        // floated the pill in the middle of the (wide, fillWidth) left section
        // and left a gap between it and the AI button. Now that the button
        // lives in the pill's leading slot, the pill has to start at the left
        // edge or the icon drifts inward with it.
        anchors.left: parent.left

        // Cap raised from 360 to keep the title roughly the room it had before
        // the AI icon moved into the leading slot and took ~18px more than the
        // bare dot did.
        implicitWidth: Math.min(holeRow.implicitWidth + 22, 380)
        // Animate width changes (different apps have different title lengths)
        // so the pill grows/shrinks smoothly when the focused window changes.
        Behavior on implicitWidth {
            NumberAnimation { duration: 280; easing.type: Easing.InOutCubic }
        }
        // Constant shape. The pill used to grow downward and un-round itself
        // into a 14px box to hold the action row; now that the actions are
        // their own chips on the bar, it stays a pill and never deforms.
        implicitHeight: root.titleHeight
        radius: height / 2

        color: Qt.darker(Appearance.colors.colLayer0Base, 1.18)
        border.width: 1
        border.color: Qt.alpha("black", 0.35)
        clip: true

        // Hovering the pill is what reveals the action chips — see
        // `actionsWanted`. No TapHandler: it used to toggle the row open, and
        // with hover doing that job a click on the title now does nothing
        // rather than fighting the pointer that is already there.
        HoverHandler { id: holeHov }

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
                // Tighter on the left than the right: the leading slot's icon
                // carries its own 4px of button padding, so 12 here read as a
                // 16px gap once it stopped being a bare 6px dot.
                anchors.leftMargin: 8
                anchors.rightMargin: 12
                spacing: 8

                // ── Leading slot: status dot ⇄ AI button ─────────────────
                // On an empty workspace this is just the small status dot.
                // Once an application is on screen the dot fades out and the
                // AI icon spins up in its place, growing from the dot's size
                // to full — the two share a center so it reads as one object
                // unfolding rather than two widgets swapping.
                Item {
                    id: leadSlot
                    Layout.alignment: Qt.AlignVCenter
                    readonly property bool sparkShown: root.hasWindow && sidebarButton.enabledByPolicy
                    readonly property real dotSize: 6

                    implicitWidth: sparkShown ? sidebarButton.implicitWidth : dotSize
                    implicitHeight: Math.max(dotSize, sidebarButton.implicitHeight)
                    Behavior on implicitWidth {
                        NumberAnimation { duration: 300; easing.type: Easing.OutCubic }
                    }

                    // Title-change pulse lives on the slot, not on the dot, so
                    // it still reads once the icon has taken the dot's place.
                    // Child scales compose with this one.
                    SequentialAnimation on scale {
                        id: pulse
                        running: false
                        NumberAnimation { from: 1; to: 1.6; duration: 140; easing.type: Easing.OutCubic }
                        NumberAnimation { from: 1.6; to: 1; duration: 220; easing.type: Easing.OutCubic }
                    }

                    Rectangle {
                        anchors.centerIn: parent
                        implicitWidth: leadSlot.dotSize
                        implicitHeight: leadSlot.dotSize
                        radius: leadSlot.dotSize / 2
                        color: root.hasActive
                            ? Appearance.m3colors.m3primary
                            : Appearance.colors.colSubtext
                        opacity: leadSlot.sparkShown ? 0 : 1
                        visible: opacity > 0
                        Behavior on opacity {
                            NumberAnimation { duration: 140; easing.type: Easing.OutCubic }
                        }
                    }

                    LeftSidebarButton {
                        id: sidebarButton
                        anchors.centerIn: parent
                        iconSize: 16
                        buttonPadding: 4
                        // Ripple/hover tints are wrong inside the dark pill —
                        // the icon is the whole affordance here.
                        colBackground: "transparent"
                        colBackgroundHover: Qt.alpha("white", 0.10)
                        colBackgroundToggled: Qt.alpha(Appearance.m3colors.m3primary, 0.22)
                        colBackgroundToggledHover: Qt.alpha(Appearance.m3colors.m3primary, 0.32)

                        visible: opacity > 0 && enabledByPolicy
                        opacity: leadSlot.sparkShown ? 1 : 0
                        // Grow out of the dot: 6px dot → full button size.
                        scale: leadSlot.sparkShown
                            ? 1
                            : leadSlot.dotSize / Math.max(1, implicitWidth)
                        rotation: leadSlot.sparkShown ? 0 : -180

                        Behavior on opacity {
                            NumberAnimation { duration: 220; easing.type: Easing.OutCubic }
                        }
                        Behavior on scale {
                            NumberAnimation { duration: 420; easing.type: Easing.OutBack; easing.overshoot: 1.4 }
                        }
                        Behavior on rotation {
                            NumberAnimation { duration: 480; easing.type: Easing.OutCubic }
                        }
                    }
                }

                StyledText {
                    id: appText
                    Layout.fillHeight: true
                    Layout.alignment: Qt.AlignVCenter
                    visible: !!text
                    text: root.cleanLabel(root.hasActive
                        ? (root.activeWindow?.appId ?? "")
                        : ((root.biggestWindow?.class) ?? Translation.tr("Desktop")))
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
                    text: root.cleanLabel(root.hasActive
                        ? (root.activeWindow?.title ?? "")
                        : ((root.biggestWindow?.title) ?? `${Translation.tr("Workspace")} ${monitor?.activeWorkspace?.id ?? 1}`))
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

    }

    // ── Window actions, as chips on the bar ──────────────────────────────
    // These used to sit inside the pill: it grew downward into a 14px box and
    // drew them on its own dark fill, so nine unlabelled glyphs read as one
    // slab of menu rather than as buttons. Out here each action is its own
    // chip in the same vocabulary as every other bar control, the pill keeps
    // its shape, and there is finally room for a tooltip to say what each one
    // does — they were pure guesswork before.
    //
    // Left-aligned with the pill so the row starts where the title starts.
    Row {
        id: actionChips
        anchors.left: hole.right
        anchors.leftMargin: 10
        // Same vertical centre as the pill's title row, so the chips sit ON the
        // bar line rather than hanging below it.
        anchors.verticalCenter: parent.verticalCenter
        spacing: 6

        // Width, not just opacity: the resource row anchors to this one's right
        // edge, so collapsing to zero is what lets it slide back against the
        // pill when the chips are away. clip keeps the chips from spilling out
        // of the collapsed box mid-animation.
        clip: true
        width: root.actionsOpen ? implicitWidth : 0
        Behavior on width {
            NumberAnimation { duration: 200; easing.type: Easing.OutCubic }
        }

        // Keeps the row up while the pointer is on the chips themselves —
        // without this, leaving the pill would close the row before you could
        // reach what it just offered you.
        HoverHandler { id: chipsHov }

        Repeater {
            // A fixed count, NOT `slotIds` itself. That binding rebuilds its
            // array on every evaluation and depends on `biggestWindow`, which
            // HyprlandData refreshes constantly — handing it to the Repeater as
            // a model meant a new array identity each refresh, so all three
            // delegates were destroyed and recreated in a loop. The chips never
            // finished appearing, and StyledToolTip logged a destroy error per
            // teardown. Indexing into it instead keeps three delegates alive for
            // the life of the row and merely re-binds their contents.
            model: root.slotCount

            delegate: Rectangle {
                id: chip
                required property int index
                // An ID no longer in the catalogue (a states.json from an older
                // build) resolves to null, and the chip hides rather than
                // throwing on every binding that touches it.
                readonly property var act: root.actionById(root.slotIds[chip.index])
                readonly property bool danger: chip.act?.danger === true

                visible: chip.act !== null && opacity > 0
                implicitWidth: 28
                implicitHeight: 28
                radius: Appearance.rounding.full

                // The *Base roles, not colLayer2/colLayer2Hover. Those two are
                // solveOverlayColor()'d and so carry the content alpha, which
                // is right for a chip inside a panel but not for one of these:
                // they hang BELOW the bar strip, on bare wallpaper, where that
                // alpha washed them out to almost nothing over a light image.
                // colLayer2Base is the opaque shade the alpha resolves to, and
                // the hover mix is the same formula colLayer2Hover uses, minus
                // the film.
                color: chipHov.hovered
                    ? (chip.danger
                        ? ColorUtils.mix(Appearance.colors.colLayer2Base,
                                         Appearance.m3colors.m3error, 0.78)
                        : ColorUtils.mix(Appearance.colors.colLayer2Base,
                                         Appearance.colors.colOnLayer2, 0.90))
                    : Appearance.colors.colLayer2Base
                Behavior on color { ColorAnimation { duration: 140 } }

                // Staggered by index so the row unrolls as one gesture rather
                // than three chips flicking on together. Closing runs the pause
                // at 0 — a menu that dawdles on the way out feels broken.
                opacity: root.actionsOpen ? 1 : 0
                scale: root.actionsOpen ? 1 : 0.55
                Behavior on opacity {
                    SequentialAnimation {
                        PauseAnimation { duration: root.actionsOpen ? chip.index * 32 : 0 }
                        NumberAnimation { duration: 150; easing.type: Easing.OutCubic }
                    }
                }
                Behavior on scale {
                    SequentialAnimation {
                        PauseAnimation { duration: root.actionsOpen ? chip.index * 32 : 0 }
                        NumberAnimation { duration: 260; easing.type: Easing.OutBack; easing.overshoot: 2.2 }
                    }
                }

                HoverHandler { id: chipHov }
                TapHandler {
                    acceptedButtons: Qt.LeftButton
                    onTapped: {
                        chip.act?.action();
                        if (!chip.act?.keepOpen) root.actionsOpen = false;
                    }
                }
                // Right-click rebinds the slot. Deliberately NOT a long-press
                // as well: these chips sit under the pointer during ordinary
                // use and a hold that silently reassigns them would be a trap.
                TapHandler {
                    acceptedButtons: Qt.RightButton
                    onTapped: eventPoint => {
                        const p = root.mapFromItem(chip, eventPoint.position.x, eventPoint.position.y);
                        slotMenu.catalog = root.actionCatalog;
                        slotMenu.takenIds = root.slotIds;
                        slotMenu.openAt(chip.index, p.x, p.y);
                    }
                }

                MaterialSymbol {
                    anchors.centerIn: parent
                    text: chip.act?.icon ?? ""
                    iconSize: 16
                    color: chip.danger
                        ? Appearance.m3colors.m3error
                        : Appearance.colors.colOnLayer2
                }

                // Driven explicitly off the chip's own HoverHandler. Left to
                // itself the tooltip grows a probe on its parent, and a plain
                // Rectangle has no `hovered` for it to find.
                StyledToolTip {
                    text: chip.act?.label ?? ""
                    extraVisibleCondition: false
                    alternativeVisibleCondition: chipHov.hovered
                }
            }
        }
    }

    // Rebind target for the chips' right-click. Mounted here, on root, so the
    // menu outlives the chip that opened it — parented to the chip it would be
    // destroyed by its own dismissal animation mid-click.
    WindowActionMenu {
        id: slotMenu
        anchorItem: root
        onPicked: (slot, id) => root.assignSlot(slot, id)
    }

    // ── Resource warning, on the bar beside the pill ─────────────────────
    // A sibling of `hole` rather than a child, so it sits on the bar itself
    // instead of inside the dark pill: this reports on the machine, not on
    // the focused window, and the two shouldn't read as one object.
    //
    // Anchored to the pill's right edge, so it tracks the pill as that
    // animates its width to fit each new window title.
    Row {
        // Anchored past the action chips rather than to the pill, so the two
        // rows never overlap when a resource goes critical while the chips are
        // open. The chips collapse to zero width when closed, which puts this
        // straight back against the pill.
        anchors.left: actionChips.right
        anchors.leftMargin: root.actionsOpen ? 10 : 0
        Behavior on anchors.leftMargin {
            NumberAnimation { duration: 200; easing.type: Easing.OutCubic }
        }
        anchors.verticalCenter: parent.verticalCenter
        spacing: 6

        // Each cell hides itself by animating its own width to zero, so the
        // row closes up as things recover rather than leaving gaps behind.
        Resource {
            iconName: "memory"
            percentage: ResourceUsage.memoryUsedPercentage
            warningThreshold: Config.options?.bar?.resources?.memoryWarningThreshold ?? 95
            shown: root.resourceShown(percentage)
        }

        Resource {
            iconName: "swap_horiz"
            percentage: ResourceUsage.swapUsedPercentage
            warningThreshold: Config.options?.bar?.resources?.swapWarningThreshold ?? 85
            shown: root.resourceShown(percentage)
        }

        Resource {
            iconName: "planner_review"
            percentage: ResourceUsage.cpuUsage
            warningThreshold: Config.options?.bar?.resources?.cpuWarningThreshold ?? 90
            shown: root.resourceShown(percentage)
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

    readonly property var actionCatalog: [
        // Cursor toggle, sitting next to the camera so the mode is visible
        // before you fire rather than buried in settings. keepOpen so you can
        // flip it and shoot without the panel closing under you.
        { id: "cursor", icon: Config.options.screenSnip.includeCursor ? "mouse" : "block",
          label: Config.options.screenSnip.includeCursor ? Translation.tr("Cursor: shown") : Translation.tr("Cursor: hidden"),
          keepOpen: true, action: () => {
            Config.options.screenSnip.includeCursor = !Config.options.screenSnip.includeCursor
            root.notify("Screenshot",
                Config.options.screenSnip.includeCursor ? "Cursor will be included" : "Cursor will be hidden",
                "input-mouse")
        }},

        // 📷 Screenshot — grimblast already shows its own --notify toast.
        // For the fallback paths we push our own.
        { id: "screenshot", icon: "photo_camera", label: Translation.tr("Screenshot window"), keepOpen: false, action: () => {
            const cur = Config.options.screenSnip.includeCursor
            root.runCmd(
                "set -e; mkdir -p ~/Pictures/Screenshots; " +
                "out=~/Pictures/Screenshots/$(date +%Y-%m-%d_%H-%M-%S).png; " +
                "if command -v grimblast >/dev/null; then " +
                "  grimblast " + (cur ? "-c " : "") + "--notify copysave active \"$out\"; " +
                "elif command -v hyprshot >/dev/null; then " +
                // hyprshot exposes no cursor flag (-z is freeze), so this
                // fallback always shoots without one.
                "  hyprshot -m active -o ~/Pictures/Screenshots && " +
                "  notify-send -a Quickshell -i camera-photo \"Screenshot saved\" \"$out\"; " +
                "else " +
                "  geom=$(hyprctl -j activewindow | python3 -c 'import json,sys;w=json.load(sys.stdin);print(\"%d,%d %dx%d\" % (w[\"at\"][0],w[\"at\"][1],w[\"size\"][0],w[\"size\"][1]))'); " +
                "  grim " + (cur ? "-c " : "") + "-g \"$geom\" \"$out\" && wl-copy < \"$out\" && " +
                "  notify-send -a Quickshell -i camera-photo \"Screenshot saved\" \"$out\"; " +
                "fi"
            )
        }},

        // 💬 Copy title
        { id: "copyTitle", icon: "title", label: Translation.tr("Copy title"), keepOpen: false, action: () => {
            const t = root.activeWindow?.title ?? root.biggestWindow?.title ?? ""
            Quickshell.clipboardText = t
            root.notify("Title copied", t, "edit-copy")
        }},

        // 🏷 Copy class / appId
        { id: "copyClass", icon: "tag", label: Translation.tr("Copy app ID"), keepOpen: false, action: () => {
            const c = root.activeWindow?.appId ?? root.biggestWindow?.class ?? ""
            Quickshell.clipboardText = c
            root.notify("App ID copied", c, "edit-copy")
        }},

        // 🔇 Mute / unmute the focused app's sink-inputs. The shell snippet
        // toggles the mute and reports back via notify-send.
        { id: "mute", icon: "volume_off", label: Translation.tr("Mute this app"), keepOpen: true, action: () => {
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
        { id: "pin", icon: "push_pin", label: Translation.tr("Pin"), keepOpen: true,  action: () => {
            HyprDispatch.run("pin")
            root.notify("Pin toggled", root.activeWindow?.title ?? "", "view-pin")
        }},

        // ⛶ Toggle fullscreen
        { id: "fullscreen", icon: "fullscreen", label: Translation.tr("Fullscreen"), keepOpen: true,  action: () => {
            HyprDispatch.run("fullscreen 1")
            root.notify("Fullscreen toggled", root.activeWindow?.title ?? "", "view-fullscreen")
        }},

        // ✋ Toggle floating
        { id: "float", icon: "drag_pan", label: Translation.tr("Toggle floating"), keepOpen: true,  action: () => {
            HyprDispatch.run("togglefloating")
            root.notify("Float toggled", root.activeWindow?.title ?? "", "object-flip-horizontal")
        }},

        // ✕ Close
        { id: "close", icon: "close", label: Translation.tr("Close window"), danger: true, keepOpen: false, action: () => {
            const t = root.activeWindow?.title ?? ""
            HyprDispatch.run("closewindow activewindow")
            root.notify("Closing window", t, "window-close")
        }},
    ]
}
