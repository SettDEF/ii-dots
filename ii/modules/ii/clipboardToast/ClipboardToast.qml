pragma ComponentBehavior: Bound
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland

/**
 * Copy confirmation: a card at the bottom right of the FOCUSED monitor.
 *
 * The window only exists while the card is up — it used to be one window per
 * monitor, all showing and animating the same toast at once. The look lives
 * in ClipboardCard (pure UI); this file is the clipboard → card wiring and
 * the show/hide lifecycle.
 *
 * Hovering the card pauses the auto-hide; Edit loads the FULL clipboard text
 * (ClipboardWatch only keeps a 200-character, single-line preview).
 */
Scope {
    id: root

    property bool shown: false
    property bool editing: false
    property var screen: null

    // What the card shows, captured per copy.
    readonly property string kind: ClipboardWatch.isImage ? "image"
        : ClipboardWatch.filePath.length > 0 ? "file"
        : ClipboardWatch.url.length > 0 ? "link" : "text"
    readonly property string fileExt: {
        const n = ClipboardWatch.filePath.split("/").pop();
        return n.includes(".") ? n.split(".").pop().toLowerCase() : "";
    }
    readonly property bool fileIsPicture: ["png","jpg","jpeg","webp","gif","bmp","svg"].includes(fileExt)
    readonly property bool fileIsVideo: ["mp4","mkv","mov","webm","avi","m4v"].includes(fileExt)
    property bool fileIsDir: false
    property string frame: ""
    readonly property string imageSource: kind === "image" ? ClipboardWatch.imagePath
        : kind !== "file" ? ""
        : fileIsPicture ? "file://" + ClipboardWatch.filePath
        : frame.length > 0 ? "file://" + frame : ""

    function hide() { if (shown) linger.restart(); shown = false; editing = false; keys = false; pinned = false; }
    /// pinned from the card: no timer closes it
    property bool pinned: false
    // a click on the toast gives it the keyboard: Esc closes, Enter runs the main button
    property bool keys: false
    // Keeps the window alive while the card fades out.
    Timer { id: linger; interval: 260 }

    Connections {
        target: ClipboardWatch
        function onRevisionChanged() {
            if (!(Config.options?.clipboardToast?.enable ?? true)) return;
            if (!root.shown)
                root.screen = Quickshell.screens.find(s => s.name === Hyprland.focusedMonitor?.name) ?? Quickshell.screens[0];
            root.editing = false;
            if (root.shown) root.bumps++;   // a new copy while it shows: a small bump, not a re-entry
            root.shown = true;
            hideTimer.restart();
        }
        function onFilePathChanged() { root.inspectFile(); }
    }

    Timer {
        id: hideTimer
        interval: root.editing || root.keys ? 30000 : 4000
        onTriggered: if (!root.pinned) root.hide()
        // the bar at the card's foot runs down with it, and stands full while it is held (hover)
        onRunningChanged: if (running) { countdown.stop(); root.left = 1; countdown.start(); } else { countdown.stop(); root.left = 1; }
    }
    property real left: 1
    property int bumps: 0
    NumberAnimation { id: countdown; target: root; property: "left"; from: 1; to: 0; duration: hideTimer.interval }

    // ── file details: folder or not, and a still for videos ──
    Process {
        id: probe
        readonly property string out: (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/quickshell-clip/file-frame.png"
        stdout: StdioCollector {
            onStreamFinished: {
                const r = text.trim();
                root.fileIsDir = r === "dir";
                if (r === "frame") root.frame = probe.out + "?v=" + ClipboardWatch.revision;
            }
        }
    }
    function inspectFile() {
        fileIsDir = false;
        frame = "";
        if (ClipboardWatch.filePath.length === 0) return;
        probe.running = false;
        probe.command = ["bash", "-c",
            'if [ -d "$1" ]; then echo dir; ' +
            'elif [ "$3" = 1 ]; then mkdir -p "$(dirname "$2")"; ' +
            '  timeout 4 ffmpeg -v error -y -ss 1 -i "$1" -frames:v 1 -vf "scale=640:-2" "$2" </dev/null ' +
            '  || timeout 4 ffmpeg -v error -y -i "$1" -frames:v 1 -vf "scale=640:-2" "$2" </dev/null; ' +
            '  [ -s "$2" ] && echo frame; fi',
            "_", ClipboardWatch.filePath, probe.out, fileIsVideo ? "1" : "0"];
        probe.running = true;
    }

    // Edit works on the whole clipboard, not the preview.
    Process {
        id: fullText
        command: ["wl-paste", "-n", "-t", "text"]
        stdout: StdioCollector {
            onStreamFinished: {
                if (loader.item) loader.item.card.setEditText(text.length > 0 ? text : ClipboardWatch.preview);
            }
        }
    }

    LazyLoader {
        id: loader
        // Kept alive through the fade-out, then dropped.
        active: root.shown || linger.running

        PanelWindow {
            id: win
            property alias card: card
            screen: root.screen

            WlrLayershell.namespace: "quickshell:clipboardToast"
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: root.editing || root.keys ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None
            exclusionMode: ExclusionMode.Ignore
            color: "transparent"

            anchors { right: true; bottom: true }
            margins { right: 14; bottom: 14 }
            // Fixed size: a layer surface resized per animation frame stutters.
            // Only the card's opacity / position animate.
            implicitWidth: card.implicitWidth + 40
            implicitHeight: 420

            mask: Region { item: card }

            StyledRectangularShadow {
                target: card
                opacity: card.opacity
            }

            ClipboardCard {
                id: card
                anchors { right: parent.right; bottom: parent.bottom; rightMargin: 10; bottomMargin: 10 }

                kind: root.kind
                text: root.kind === "link" ? ClipboardWatch.url : ClipboardWatch.preview
                imageSource: root.imageSource
                filePath: ClipboardWatch.filePath
                fileIsDir: root.fileIsDir
                fileIsVideo: root.fileIsVideo
                devices: KdeConnectService.reachableDevices
                editing: root.editing

                // Enter: springs up from the corner (a touch of overshoot). Leave: slips right, quicker.
                opacity: root.shown ? 1 : 0
                transform: [
                    Scale {
                        id: grow
                        origin.x: card.width; origin.y: card.height
                        xScale: root.shown ? 1 : 0.9; yScale: xScale
                        Behavior on xScale { NumberAnimation { duration: root.shown ? 420 : 200; easing.type: root.shown ? Easing.OutBack : Easing.InCubic; easing.overshoot: 1.6 } }
                    },
                    Translate {
                        id: slide
                        x: root.shown ? 0 : 56
                        y: root.shown ? 0 : 14
                        Behavior on x { NumberAnimation { duration: root.shown ? 380 : 210; easing.type: root.shown ? Easing.OutQuint : Easing.InCubic } }
                        Behavior on y { NumberAnimation { duration: root.shown ? 380 : 210; easing.type: Easing.OutQuint } }
                    },
                    Scale { id: bump; origin.x: card.width; origin.y: card.height; xScale: 1; yScale: xScale }
                ]
                Behavior on opacity {
                    NumberAnimation { duration: root.shown ? 220 : 190; easing.type: root.shown ? Easing.OutCubic : Easing.InCubic }
                }
                Component.onCompleted: {
                    opacity = 0; slide.x = 56; slide.y = 14; grow.xScale = 0.9;
                    Qt.callLater(() => {
                        opacity = Qt.binding(() => root.shown ? 1 : 0);
                        slide.x = Qt.binding(() => root.shown ? 0 : 56);
                        slide.y = Qt.binding(() => root.shown ? 0 : 14);
                        grow.xScale = Qt.binding(() => root.shown ? 1 : 0.9);
                    });
                }
                // the card lives in a per-screen delegate: it watches the counter rather than being called
                property int bumpSeen: root.bumps
                onBumpSeenChanged: pulse.restart()
                SequentialAnimation {
                    id: pulse
                    NumberAnimation { target: bump; property: "xScale"; to: 1.035; duration: 110; easing.type: Easing.OutCubic }
                    NumberAnimation { target: bump; property: "xScale"; to: 1; duration: 320; easing.type: Easing.OutBack; easing.overshoot: 2 }
                }

                // any press on the card (a chip too: a PointHandler only watches) takes the keyboard
                PointHandler {
                    acceptedButtons: Qt.AllButtons
                    onActiveChanged: if (active && !root.editing) { root.keys = true; hideTimer.restart(); keyGrab.restart() }
                }
                // the layer gets focus a moment after asking; try until the card has it
                Timer {
                    id: keyGrab
                    interval: 40; repeat: true
                    property int tries: 0
                    onRunningChanged: tries = 0
                    onTriggered: { card.forceActiveFocus(); if (card.activeFocus || ++tries > 12) stop() }
                }
                // it had the keyboard and lost it (a click elsewhere, another window): gone
                readonly property bool winActive: Window.active
                onWinActiveChanged: if (!winActive && root.keys && !root.editing) root.hide()
                Keys.onPressed: (e) => {
                    if (root.editing) return
                    if (e.key === Qt.Key_Escape) { root.hide(); e.accepted = true }
                    else if (e.key === Qt.Key_Return || e.key === Qt.Key_Enter) {
                        if (root.kind === "image") card.saveRequested()
                        else if (root.kind === "link" || root.kind === "file") card.openRequested()
                        else card.shareRequested()
                        e.accepted = true
                    }
                }

                HoverHandler {
                    id: hover
                    onHoveredChanged: {
                        if (hovered) hideTimer.stop();
                        else if (root.shown) hideTimer.restart();
                    }
                }

                onCloseRequested: root.hide()
                pinned: root.pinned
                onPinToggled: { root.pinned = !root.pinned; if (root.pinned) hideTimer.stop(); else hideTimer.restart(); }
                // an image is copied out first: the clipboard's file is replaced by the next copy
                onShareRequested: {
                    const share = Quickshell.env("HOME") + "/.scripts/apps/share/share";
                    if (root.kind === "image")
                        Quickshell.execDetached(["bash", "-c", 'd="${XDG_RUNTIME_DIR:-/tmp}/share"; mkdir -p "$d"; f="$d/clip-$(date +%s%N).png"; cp "$1" "$f" && exec "$2" "$f"', "_", ClipboardWatch.imagePath.split("?")[0], share]);
                    else Quickshell.execDetached([share, root.kind === "file" ? ClipboardWatch.filePath : root.kind === "link" ? ClipboardWatch.url : ClipboardWatch.preview]);
                    root.hide();
                }
                onOpenRequested: {
                    Quickshell.execDetached(["xdg-open", root.kind === "link" ? ClipboardWatch.url : ClipboardWatch.filePath]);
                    root.hide();
                }
                onFolderRequested: {
                    // Directory items: open it; files: open the folder they are in.
                    Quickshell.execDetached(["bash", "-c", '[ -d "$1" ] && exec xdg-open "$1"; exec xdg-open "$(dirname "$1")"',
                                             "_", ClipboardWatch.filePath]);
                    root.hide();
                }
                // a copy first: the clipboard's file is replaced by the next copy
                onMarkupRequested: {
                    Quickshell.execDetached(["bash", "-c",
                        'd="${XDG_RUNTIME_DIR:-/tmp}/quickshell-clip"; mkdir -p "$d"; f="$d/markup-$(date +%s%N).png"; cp "$1" "$f" && qs -c ii ipc call screenshotEditor open "$f"',
                        "_", ClipboardWatch.imagePath.split("?")[0]]);
                    root.hide();
                }
                onSaveRequested: {
                    // Timestamped so repeated copies do not overwrite.
                    Quickshell.execDetached(["bash", "-c",
                        'mkdir -p ~/Pictures/Clipboard && cp "$1" ~/Pictures/Clipboard/clip-$(date +%Y%m%d-%H%M%S).png',
                        "_", ClipboardWatch.imagePath.split("?")[0]]);
                    root.hide();
                }
                onSendRequested: (id) => {
                    if (root.kind === "image") KdeConnectService.share(id, ClipboardWatch.imagePath.split("?")[0]);
                    else if (root.kind === "file") KdeConnectService.share(id, ClipboardWatch.filePath);
                    else KdeConnectService.shareText(id, root.kind === "link" ? ClipboardWatch.url : ClipboardWatch.preview);
                    root.hide();
                }
                onEditRequested: {
                    root.editing = true;
                    hideTimer.restart();
                    card.setEditText(ClipboardWatch.preview);
                    fullText.running = true;
                }
                onEditCommitted: (t) => {
                    Quickshell.execDetached(["wl-copy", "--", t]);
                    root.editing = false;
                    hideTimer.restart();
                }
                onEditCancelled: {
                    root.editing = false;
                    hideTimer.restart();
                }
            }
        }
    }
}
