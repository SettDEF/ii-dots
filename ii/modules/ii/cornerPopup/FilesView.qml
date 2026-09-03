pragma ComponentBehavior: Bound
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io

// Folder browser for the corner popup.
//
// Unfiltered on purpose: DirectoryIcon resolves artwork for any MIME type, so
// every format shows up with the right icon instead of being hidden the way
// the wallpaper picker's image/video nameFilters hide it.
//
// Listing uses `find`, not FolderListModel, for the same reason DesktopIcons
// does: FolderListModel stat()s every entry to decide isDir, and a symlink
// into an absent automount (~/Music here) blocks that stat for the full autofs
// timeout — inside Qt, where it cannot be capped. `find` without -L never
// dereferences, so an unavailable mount cannot stall the shell.
ColumnLayout {
    id: root

    readonly property int tileHeight: 92
    readonly property int headerHeight: 48
    readonly property int contentHeight: headerHeight + tileHeight * 2 + 14

    function _tidyPath(p) {
        const s = FileUtils.trimFileProtocol(String(p)).replace(/\/+$/, "");
        return s.length > 0 ? s : "/";
    }

    property string currentDir: root._tidyPath(Directories.home)
    property var entries: []
    property var history: [root._tidyPath(Directories.home)]
    property int historyIndex: 0

    spacing: 4

    function navigateTo(path) {
        const p = root._tidyPath(path);
        if (p === root.currentDir) return;
        root.history = root.history.slice(0, root.historyIndex + 1).concat([p]);
        root.historyIndex = root.history.length - 1;
        root.currentDir = p;
    }
    function navigateBack() {
        if (root.historyIndex <= 0) return;
        root.historyIndex -= 1;
        root.currentDir = root.history[root.historyIndex];
    }
    function navigateUp() {
        const up = root.currentDir.replace(/\/[^/]*$/, "");
        root.navigateTo(up.length > 0 ? up : "/");
    }

    onCurrentDirChanged: root.refresh()
    // Directory the in-flight listing was launched for, so a slow result for
    // the previous folder cannot land on top of the current one.
    property string pendingDir: ""
    function refresh() {
        root.pendingDir = root.currentDir;
        listProc.running = false;
        // false→true in one tick is coalesced into "no change" and the process
        // never restarts — which is why opening a folder kept the old listing.
        Qt.callLater(() => listProc.running = true);
    }

    Process {
        id: listProc
        // No -L: the link itself is reported (%y == "l") and never followed.
        command: ["timeout", "2", "find", root.pendingDir,
                  "-maxdepth", "1", "-mindepth", "1",
                  "-printf", "%y\\t%f\\n"]
        stdout: StdioCollector {
            onStreamFinished: {
                if (root.pendingDir !== root.currentDir)
                    return;   // stale result for a folder we already left
                const list = [];
                for (const line of text.split("\n")) {
                    if (line.length === 0) continue;
                    const tab = line.indexOf("\t");
                    if (tab < 0) continue;
                    const type = line.slice(0, tab);
                    const name = line.slice(tab + 1);
                    if (name.startsWith(".")) continue;
                    const path = root.pendingDir === "/"
                        ? "/" + name : root.pendingDir + "/" + name;
                    list.push({
                        fileName: name,
                        filePath: path,
                        fileUrl: "file://" + path,
                        fileIsDir: type === "d",
                        isSymlink: type === "l"
                    });
                }
                list.sort((a, b) => {
                    if (a.fileIsDir !== b.fileIsDir) return a.fileIsDir ? -1 : 1;
                    return a.fileName.localeCompare(b.fileName, undefined, { numeric: true });
                });
                root.entries = list;
                if (list.some(e => e.isSymlink)) {
                    linkProc.running = false;
                    Qt.callLater(() => linkProc.running = true);
                }
            }
        }
    }

    // Best-effort: promote symlinks that really point at directories. -xtype
    // DOES dereference, so it is capped and non-essential — on timeout the
    // listing above stands and links simply stay classified as files.
    Process {
        id: linkProc
        command: ["timeout", "2", "find", root.pendingDir,
                  "-maxdepth", "1", "-mindepth", "1", "-type", "l", "-xtype", "d",
                  "-printf", "%f\\n"]
        stdout: StdioCollector {
            onStreamFinished: {
                if (root.pendingDir !== root.currentDir) return;
                if (text.trim().length === 0) return;
                const dirs = ({});
                for (const line of text.split("\n"))
                    if (line.length > 0) dirs[line] = true;
                const next = root.entries.map(e =>
                    (e.isSymlink && dirs[e.fileName])
                        ? Object.assign({}, e, { fileIsDir: true }) : e);
                next.sort((a, b) => {
                    if (a.fileIsDir !== b.fileIsDir) return a.fileIsDir ? -1 : 1;
                    return a.fileName.localeCompare(b.fileName, undefined, { numeric: true });
                });
                root.entries = next;
            }
        }
    }

    function openEntry(entry) {
        if (entry.fileIsDir) {
            root.navigateTo(entry.filePath);
            return;
        }
        Quickshell.execDetached(["xdg-open", entry.filePath]);
    }

    readonly property var imageExtensions: ["png", "jpg", "jpeg", "webp", "bmp", "gif", "avif", "jxl"]
    function _isImage(name) {
        const dot = String(name).lastIndexOf(".");
        return dot > 0 && root.imageExtensions.includes(name.slice(dot + 1).toLowerCase());
    }

    PopupContextMenu { id: ctx }

    function menuForEntry(entry) {
        const items = [{
            icon: entry.fileIsDir ? "folder_open" : "open_in_new",
            label: entry.fileIsDir ? Translation.tr("Open") : Translation.tr("Open with default app"),
            onTriggered: () => root.openEntry(entry)
        }];
        if (!entry.fileIsDir && root._isImage(entry.fileName))
            items.push({
                icon: "wallpaper",
                label: Translation.tr("Set as wallpaper"),
                onTriggered: () => Wallpapers.select(entry.filePath)
            });
        items.push({
            icon: "content_copy",
            label: Translation.tr("Copy path"),
            onTriggered: () => Quickshell.clipboardText = entry.filePath
        });
        items.push({
            icon: "folder",
            label: Translation.tr("Show in file manager"),
            onTriggered: () => Quickshell.execDetached(["xdg-open",
                entry.fileIsDir ? entry.filePath : root.currentDir])
        });
        return items;
    }

    function menuForFolder() {
        return [{
            icon: "refresh",
            label: Translation.tr("Refresh"),
            onTriggered: () => root.refresh()
        }, {
            icon: "arrow_upward",
            label: Translation.tr("Go up"),
            onTriggered: () => root.navigateUp()
        }, {
            icon: "wallpaper",
            label: Translation.tr("Open in wallpaper picker"),
            onTriggered: () => root.openInWallpaperPicker()
        }, {
            icon: "content_copy",
            label: Translation.tr("Copy folder path"),
            onTriggered: () => Quickshell.clipboardText = root.currentDir
        }];
    }

    // Hands the current folder to the wallpaper picker rather than duplicating
    // its grid — same service, same navigation history.
    function openInWallpaperPicker() {
        Wallpapers.setDirectory(root.currentDir);
        GlobalStates.wallpaperSelectorOpen = true;
    }

    component IconBtn: Rectangle {
        id: btn
        property string sym: ""
        property string tip: ""
        signal activated()
        implicitWidth: 28
        implicitHeight: 28
        radius: height / 2
        color: btnHov.hovered ? Appearance.colors.colLayer1Hover : "transparent"
        Behavior on color { ColorAnimation { duration: 120 } }
        HoverHandler { id: btnHov }
        TapHandler { onTapped: btn.activated() }
        MaterialSymbol {
            anchors.centerIn: parent
            text: btn.sym
            iconSize: 18
            color: Appearance.colors.colOnLayer0
        }
        StyledToolTip {
            extraVisibleCondition: false
            alternativeVisibleCondition: btnHov.hovered
            text: btn.tip
        }
    }

    // Fixed height: AddressBreadcrumb is a ListView with no implicit height of
    // its own, so letting it fill stretched the header and left the buttons
    // floating in the middle of it.
    RowLayout {
        Layout.fillWidth: true
        Layout.leftMargin: 6
        Layout.rightMargin: 6
        Layout.topMargin: 2
        Layout.preferredHeight: root.headerHeight
        Layout.maximumHeight: root.headerHeight
        spacing: 2

        IconBtn {
            Layout.alignment: Qt.AlignVCenter
            sym: "arrow_back"
            tip: Translation.tr("Back")
            onActivated: root.navigateBack()
        }
        IconBtn {
            Layout.alignment: Qt.AlignVCenter
            sym: "arrow_upward"
            tip: Translation.tr("Up")
            onActivated: root.navigateUp()
        }

        AddressBreadcrumb {
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignVCenter
            Layout.preferredHeight: root.headerHeight - 8
            directory: root.currentDir
            onNavigateToDirectory: path => root.navigateTo(path)
        }

        IconBtn {
            Layout.alignment: Qt.AlignVCenter
            sym: "wallpaper"
            tip: Translation.tr("Open in wallpaper picker")
            onActivated: root.openInWallpaperPicker()
        }
    }

    GridView {
        id: grid
        Layout.fillWidth: true
        Layout.fillHeight: true
        Layout.leftMargin: 6
        Layout.rightMargin: 6
        Layout.bottomMargin: 6
        Layout.topMargin: 2
        clip: true
        cellWidth: Math.floor(width / 3)
        cellHeight: root.tileHeight
        model: ScriptModel { values: root.entries }

        ScrollBar.vertical: StyledScrollBar {}

        // Empty-space menu. z below the tiles so a right-click on a tile gets
        // that tile's menu instead of this one.
        MouseArea {
            anchors.fill: parent
            z: -1
            acceptedButtons: Qt.RightButton
            onClicked: mouse => {
                const p = grid.mapToItem(root, mouse.x, mouse.y);
                ctx.popup(p.x, p.y, root.menuForFolder());
            }
        }

        delegate: Item {
            id: tile
            required property var modelData
            width: grid.cellWidth
            height: grid.cellHeight

            Rectangle {
                anchors.fill: parent
                anchors.margins: 3
                radius: Appearance.rounding.small
                color: tileHov.hovered
                    ? Qt.alpha(Appearance.colors.colOnLayer0, 0.08) : "transparent"
                Behavior on color { ColorAnimation { duration: 120 } }
            }

            HoverHandler { id: tileHov }
            TapHandler { onTapped: root.openEntry(tile.modelData) }
            MouseArea {
                anchors.fill: parent
                acceptedButtons: Qt.RightButton
                onClicked: mouse => {
                    const p = tile.mapToItem(root, mouse.x, mouse.y);
                    ctx.popup(p.x, p.y, root.menuForEntry(tile.modelData));
                }
            }

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 6
                spacing: 3

                DirectoryIcon {
                    Layout.alignment: Qt.AlignHCenter
                    Layout.preferredWidth: 46
                    Layout.preferredHeight: 46
                    sourceSize.width: 46
                    sourceSize.height: 46
                    fileModelData: tile.modelData
                }

                // Matches the wallpaper picker's tile label: single elided
                // line, centred, one size up from the old wrapped caption.
                StyledText {
                    Layout.fillWidth: true
                    Layout.leftMargin: 4
                    Layout.rightMargin: 4
                    horizontalAlignment: Text.AlignHCenter
                    elide: Text.ElideRight
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    text: tile.modelData.fileName
                    color: Appearance.colors.colOnLayer0
                    Behavior on color {
                        animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
                    }
                }
            }

            StyledToolTip {
                extraVisibleCondition: false
                alternativeVisibleCondition: tileHov.hovered
                text: tile.modelData.fileName
            }
        }

        PagePlaceholder {
            anchors.centerIn: parent
            icon: "folder_open"
            title: Translation.tr("Empty folder")
            shown: root.entries.length === 0
        }
    }

    Component.onCompleted: root.refresh()
}
