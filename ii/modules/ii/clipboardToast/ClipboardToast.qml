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

    function hide() { if (shown) linger.restart(); shown = false; editing = false; }
    // Keeps the window alive while the card fades out.
    Timer { id: linger; interval: 260 }

    Connections {
        target: ClipboardWatch
        function onRevisionChanged() {
            if (!(Config.options?.clipboardToast?.enable ?? true)) return;
            if (!root.shown)
                root.screen = Quickshell.screens.find(s => s.name === Hyprland.focusedMonitor?.name) ?? Quickshell.screens[0];
            root.editing = false;
            root.shown = true;
            hideTimer.restart();
        }
        function onFilePathChanged() { root.inspectFile(); }
    }

    Timer {
        id: hideTimer
        interval: root.editing ? 30000 : 4000
        onTriggered: root.hide()
    }

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
            WlrLayershell.keyboardFocus: root.editing ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None
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

                // Enter: rise and fade in. Leave: slide right and fade.
                opacity: root.shown ? 1 : 0
                transform: Translate {
                    id: slide
                    x: root.shown ? 0 : 24
                    Behavior on x { NumberAnimation { duration: 260; easing.type: Easing.OutCubic } }
                }
                Behavior on opacity {
                    NumberAnimation { duration: root.shown ? 160 : 200; easing.type: Easing.OutCubic }
                }
                Component.onCompleted: { opacity = 0; slide.x = 24; Qt.callLater(() => { opacity = Qt.binding(() => root.shown ? 1 : 0); slide.x = Qt.binding(() => root.shown ? 0 : 24); }); }

                HoverHandler {
                    id: hover
                    onHoveredChanged: {
                        if (hovered) hideTimer.stop();
                        else if (root.shown) hideTimer.restart();
                    }
                }

                onCloseRequested: root.hide()
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
