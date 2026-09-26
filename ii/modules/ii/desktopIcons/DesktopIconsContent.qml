// KDE-style desktop icons over ~/Desktop: snap grid with drag repositioning,
// per-icon and empty-space context menus, rubberband multi-select.
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import QtQuick
import QtQuick.Layouts
import Qt.labs.folderlistmodel
import Quickshell
import Quickshell.Io

Item {
    id: root
    anchors.fill: parent

    // ── Config-driven knobs ────────────────────────────────────────────
    readonly property int cellSize: Math.max(56, Math.min(160, Config.options.desktop.icons.iconSize))
    readonly property int padding: 14
    readonly property int labelHeight: 28
    readonly property int gridStep: cellSize + 24
    // Vertical pitch must clear the label, not just the icon.
    readonly property int gridStepY: cellSize + labelHeight + 16
    // ── Reserved-edge insets ───────────────────────────────────────────
    // The layer spans the full screen, so inset icons away from the bar/dock per their config.
    readonly property bool _barOnBottom: Config.options.bar.bottom === true
    readonly property bool _barIsVertical: Config.options.bar.vertical === true
    readonly property int _gap: Math.round(Appearance.sizes.hyprlandGapsOut)
    // Top inset = max(compositor-reserved, bar-derived): only the monitor knows about foreign
    // layers (e.g. MiniMeters). reserved[1] is the top edge. Use THIS screen's monitor, not
    // monitors[0]: reservations differ per screen.
    readonly property string screenName: root.QsWindow.window?.screen?.name ?? ""
    readonly property var _mon: {
        const list = HyprlandData.monitors ?? [];
        const mine = list.find(m => m.name === root.screenName);
        return mine ?? (list.length > 0 ? list[0] : null);
    }
    readonly property int _reservedTop:
        (_mon && _mon.reserved && _mon.reserved.length > 1) ? Math.round(_mon.reserved[1]) : 0
    readonly property int _barInsetTop: (!_barIsVertical && !_barOnBottom)
        ? Math.round(Appearance.sizes.barHeight) + _gap : 0
    readonly property int insetTop: Math.max(_reservedTop, _barInsetTop) + _gap + padding
    readonly property int insetBottom: ((!_barIsVertical && _barOnBottom)
        ? Math.round(Appearance.sizes.barHeight) + _gap : 0)
        + (Config.options.dock.enable ? Math.round((Config.options.dock.height ?? 70)
                                                 + Appearance.sizes.elevationMargin
                                                 + _gap) : 0)
        + padding
    readonly property int insetLeft: (_barIsVertical && !_barOnBottom)
        ? Math.round(Appearance.sizes.verticalBarWidth) + _gap + padding : padding
    readonly property int insetRight: (_barIsVertical && _barOnBottom)
        ? Math.round(Appearance.sizes.verticalBarWidth) + _gap + padding : padding
    // True while any tile drags, so a multi-selection moves rigidly instead of animating.
    property bool anyDragging: false

    readonly property bool showHidden: Config.options.desktop.icons.showHidden
    readonly property bool useThumbs: Config.options.desktop.icons.thumbnails
    // FolderListModel.SortField: 0=Unsorted 1=Name 2=Time 3=Size 4=Type
    // sortMode is "field" or "field:desc" (avoids a new config key the schema would drop).
    readonly property string sortField: String(Config.options.desktop.icons.sortMode || "name").split(":")[0]
    readonly property bool sortDesc: String(Config.options.desktop.icons.sortMode || "").endsWith(":desc")
    readonly property int sortFieldIdx: {
        switch (root.sortField) {
            case "mtime": return 2
            case "size":  return 3
            case "type":  return 4
            default:      return 1
        }
    }
    // Third-level menu: direction for one field.
    function _orderMenu(field) {
        return [
            { icon: "arrow_upward",   label: qsTr("Ascending"),
              onTriggered: () => Config.options.desktop.icons.sortMode = field },
            { icon: "arrow_downward", label: qsTr("Descending"),
              onTriggered: () => Config.options.desktop.icons.sortMode = field + ":desc" },
        ]
    }

    // ── Persisted icon positions ───────────────────────────────────────
    // { filename → { x, y } } so dragging is sticky across sessions.
    // Config is read once at startup; re-reading on change raced with our own saves.
    property var iconPositions: ({})
    function _loadPositions() {
        try { iconPositions = JSON.parse(Config.options.desktop.icons.positions || "{}") }
        catch (e) { iconPositions = {} }
    }
    function _savePositions() {
        Config.options.desktop.icons.positions = JSON.stringify(iconPositions)
    }
    Component.onCompleted: _loadPositions()
    // Sort changes don't change the file count, so wake the layout timer explicitly.
    onSortFieldIdxChanged: persistLayoutTimer.restart()

    // Listing via `find`, NOT FolderListModel: its stat() of symlinks into an absent automount
    // (/mnt/nuke9100) blocks for the autofs timeout, inside Qt, and stalled the whole shell.
    QtObject {
        id: dirModel
        readonly property string folder: (Quickshell.env("HOME") || "/home/caesar") + "/Desktop"
        property var entries: []
        readonly property int count: dirModel.entries.length
        property bool ready: false

        /// Symlink name -> true if it points at a directory. Kept across refreshes so
        /// links don't flash as files, then folders, on every poll.
        property var linkDirs: ({})

        /// Signature of the last published listing; an unchanged one isn't republished.
        property string lastKey: ""
        function get(index, role) {
            const e = dirModel.entries[index];
            return e === undefined ? undefined : e[role];
        }
        function refresh() {
            listProc.running = false;
            listProc.running = true;
        }
    }

    Process {
        id: listProc
        command: ["timeout", "2", "find", dirModel.folder,
                  "-maxdepth", "1", "-mindepth", "1",
                  "-printf", "%y\\t%s\\t%T@\\t%f\\n"]
        stdout: StdioCollector {
            onStreamFinished: {
                // Unchanged → publish nothing; reassigning rebuilds every delegate and reloads icons.
                const key = text + "\u0000" + root.sortFieldIdx + "\u0000" + root.showHidden;
                if (key === dirModel.lastKey && dirModel.ready) return;
                dirModel.lastKey = key;

                const list = [];
                for (const line of text.split("\n")) {
                    if (line.length === 0) continue;
                    const parts = line.split("\t");
                    if (parts.length < 4) continue;
                    const name = parts.slice(3).join("\t");   // a name may contain a tab
                    if (!root.showHidden && name.startsWith(".")) continue;
                    const dot = name.lastIndexOf(".");
                    list.push({
                        fileName: name,
                        filePath: dirModel.folder + "/" + name,
                        fileUrl: "file://" + dirModel.folder + "/" + name,
                        // Remembered verdict applied here so a symlinked folder never shows as a file.
                        fileIsDir: parts[0] === "d"
                                   || (parts[0] === "l" && dirModel.linkDirs[name] === true),
                        isSymlink: parts[0] === "l",
                        fileSize: parseInt(parts[1]) || 0,
                        fileModified: parseFloat(parts[2]) || 0,
                        suffix: dot > 0 ? name.slice(dot + 1).toLowerCase() : ""
                    });
                }
                // 1 Name · 2 Time · 3 Size · 4 Type, matching the old sortField.
                list.sort((a, b) => {
                    if (a.fileIsDir !== b.fileIsDir) return a.fileIsDir ? -1 : 1;
                    let r = 0;
                    if (root.sortFieldIdx === 2) r = a.fileModified - b.fileModified;
                    else if (root.sortFieldIdx === 3) r = a.fileSize - b.fileSize;
                    else if (root.sortFieldIdx === 4) r = a.suffix.localeCompare(b.suffix);
                    if (r === 0) r = a.fileName.localeCompare(b.fileName, undefined, { numeric: true });
                    return r;
                });
                dirModel.entries = list;
                dirModel.ready = true;
                // Ask about symlinks with no verdict yet (the listing never dereferences).
                if (list.some(e => e.isSymlink && dirModel.linkDirs[e.fileName] === undefined)) {
                    linkProc.running = false;
                    Qt.callLater(() => linkProc.running = true);
                }
            }
        }
    }

    // Promote symlinks that point at directories. NOT `find -xtype d`: dereferencing into a
    // dead autofs mount parks the process in D state (immune to `timeout`) for 600s.
    // The helper reads targets without following them.
    Process {
        id: linkProc
        command: ["bash", Quickshell.shellPath("scripts/fs/dir-symlinks.sh"), dirModel.folder]
        stdout: StdioCollector {
            onStreamFinished: {
                const dirs = ({});
                for (const line of text.split("\n"))
                    if (line.length > 0) dirs[line] = true;

                // Record a verdict for EVERY symlink; an unrecorded "no" would re-run this forever.
                const next = Object.assign({}, dirModel.linkDirs);
                let changed = false;
                for (const e of dirModel.entries) {
                    if (!e.isSymlink) continue;
                    const verdict = dirs[e.fileName] === true;
                    if (next[e.fileName] !== verdict) { next[e.fileName] = verdict; changed = true; }
                }
                if (!changed) return;
                dirModel.linkDirs = next;
                dirModel.entries = dirModel.entries.map(e =>
                    (e.isSymlink && next[e.fileName] === true && !e.fileIsDir)
                        ? Object.assign({}, e, { fileIsDir: true }) : e);
            }
        }
    }

    // find is one-shot, so poll for changes. A listing is ~3ms.
    Timer {
        interval: 4000
        running: !GameMode.active
        repeat: true
        triggeredOnStart: true
        onTriggered: dirModel.refresh()
    }

    // Safe area: keeps the reserved bar/dock strips click-through.
    Item {
        id: safeArea
        anchors.fill: parent
        anchors.topMargin:    root.insetTop
        anchors.bottomMargin: root.insetBottom
        anchors.leftMargin:   root.insetLeft
        anchors.rightMargin:  root.insetRight

        // Insets move the container, not the tiles, so the grid has to glide itself.
        Behavior on anchors.topMargin {
            NumberAnimation { duration: 220; easing.type: Easing.OutCubic }
        }
        Behavior on anchors.bottomMargin {
            NumberAnimation { duration: 220; easing.type: Easing.OutCubic }
        }
        Behavior on anchors.leftMargin {
            NumberAnimation { duration: 220; easing.type: Easing.OutCubic }
        }
        Behavior on anchors.rightMargin {
            NumberAnimation { duration: 220; easing.type: Easing.OutCubic }
        }

        // Empty space: click clears, right-click menu, left-drag rubberband. z: -1 so tiles win.
        MouseArea {
            id: emptyClickArea
            anchors.fill: parent
            acceptedButtons: Qt.LeftButton | Qt.RightButton
            hoverEnabled: true
            // Touch has no right button; long-press opens the menu.
            pressAndHoldInterval: 450
            onPressAndHold: (m) => {
                if (m.button !== Qt.LeftButton || emptyClickArea._dragging) return
                ctx.popup(m.x + root.insetLeft,
                          m.y + root.insetTop,
                          root._emptyMenu())
                m.accepted = true
            }
            z: -1
            property real _sx: 0
            property real _sy: 0
            property bool _dragging: false
            onPressed: (mouse) => {
                _sx = mouse.x
                _sy = mouse.y
                _dragging = false
                _justDragged = false
                if (mouse.button === Qt.LeftButton) {
                    // Don't clear yet: may be an additive (Ctrl) rubberband.
                    root._rubberbandActive = true
                    root._rubberbandX = mouse.x
                    root._rubberbandY = mouse.y
                    root._rubberbandW = 0
                    root._rubberbandH = 0
                    root._rubberbandAdditive = (mouse.modifiers & Qt.ControlModifier) !== 0
                }
                mouse.accepted = true
            }
            onPositionChanged: (mouse) => {
                if (!pressed || mouse.button !== Qt.NoButton && !(pressedButtons & Qt.LeftButton)) return
                const dx = mouse.x - _sx
                const dy = mouse.y - _sy
                if (!_dragging && (Math.abs(dx) > 3 || Math.abs(dy) > 3))
                    _dragging = true
                if (_dragging) {
                    root._rubberbandX = Math.min(_sx, mouse.x)
                    root._rubberbandY = Math.min(_sy, mouse.y)
                    root._rubberbandW = Math.abs(dx)
                    root._rubberbandH = Math.abs(dy)
                    root._rubberbandRecompute()
                }
            }
            // onClicked fires AFTER onReleased; _justDragged outlives the release.
            property bool _justDragged: false
            onReleased: (mouse) => {
                if (_dragging && root._rubberbandActive) {
                    const m = root._rubberbandAdditive
                        ? Object.assign({}, root.selectedFiles)
                        : {}
                    const hits = root._rubberbandHits
                    for (const k of Object.keys(hits)) if (hits[k]) m[k] = true
                    root.selectedFiles = m
                }
                _justDragged = _dragging
                root._rubberbandActive = false
                root._rubberbandHits = ({})
                root._rubberbandW = 0
                root._rubberbandH = 0
                _dragging = false
                mouse.accepted = true
            }
            onClicked: (mouse) => {
                if (_justDragged) {
                    _justDragged = false
                    mouse.accepted = true
                    return
                }
                if (mouse.button === Qt.LeftButton) {
                    if (!(mouse.modifiers & Qt.ControlModifier))
                        root._clearSelection()
                } else if (mouse.button === Qt.RightButton) {
                    ctx.popup(mouse.x + root.insetLeft,
                              mouse.y + root.insetTop,
                              root._emptyMenu())
                }
                mouse.accepted = true
            }
        }

        // Rubberband visual, in safeArea coords to match the tiles.
        Rectangle {
            visible: root._rubberbandActive && (root._rubberbandW > 1 || root._rubberbandH > 1)
            x: root._rubberbandX
            y: root._rubberbandY
            width: root._rubberbandW
            height: root._rubberbandH
            z: 100
            color: Qt.alpha(Appearance.m3colors.m3primary, 0.18)
            border.width: 1
            border.color: Appearance.m3colors.m3primary
            radius: 4
            enabled: false
        }
    }

    // ── Selection model ────────────────────────────────────────────────
    // path → true. A var map (not Set) so bindings update on reassign.
    property var selectedFiles: ({})
    // Last clicked path — anchor for Shift-click range selection.
    property string selectionAnchor: ""

    function _isSelected(path) { return !!selectedFiles[path] }
    function _selectedCount() { return Object.keys(selectedFiles).length }
    function _selectedPaths() { return Object.keys(selectedFiles) }
    function _clearSelection() {
        if (Object.keys(selectedFiles).length > 0) selectedFiles = {}
    }
    function _selectOnly(path) {
        const m = {}; m[path] = true; selectedFiles = m
        selectionAnchor = path
    }
    function _toggleSelected(path) {
        const m = Object.assign({}, selectedFiles)
        if (m[path]) delete m[path]; else m[path] = true
        selectedFiles = m
        selectionAnchor = path
    }
    function _addSelected(path) {
        if (selectedFiles[path]) return
        const m = Object.assign({}, selectedFiles)
        m[path] = true; selectedFiles = m
    }
    // ── Rubberband selection state ─────────────────────────────────────
    // Coords are safeArea-local, matching tile x/y.
    property bool _rubberbandActive: false
    property real _rubberbandX: 0
    property real _rubberbandY: 0
    property real _rubberbandW: 0
    property real _rubberbandH: 0
    // Ctrl-started drag unions with the prior selection on release.
    property bool _rubberbandAdditive: false
    // Live hits (path → true); tiles highlight from it before release commits.
    property var _rubberbandHits: ({})
    property var _tileBounds: ({})   // path → {x, y, w, h}
    // Mutated in place: fires per tile per frame during drags, and nothing binds to it.
    function _registerTile(path, x, y, w, h) {
        _tileBounds[path] = { x: x, y: y, w: w, h: h }
    }
    function _unregisterTile(path) {
        delete _tileBounds[path]
    }
    function _rubberbandRecompute() {
        const rx = _rubberbandX, ry = _rubberbandY
        const rw = _rubberbandW, rh = _rubberbandH
        const m = {}
        for (const p of Object.keys(_tileBounds)) {
            const b = _tileBounds[p]
            const hit = !(b.x > rx + rw || b.x + b.w < rx
                       || b.y > ry + rh || b.y + b.h < ry)
            if (hit) m[p] = true
        }
        _rubberbandHits = m
    }

    function _rangeSelect(path) {
        if (!selectionAnchor) { _selectOnly(path); return }
        let aIdx = -1, bIdx = -1
        for (let i = 0; i < dirModel.count; i++) {
            const fp = dirModel.get(i, "filePath")
            if (fp === selectionAnchor) aIdx = i
            if (fp === path)            bIdx = i
        }
        if (aIdx < 0 || bIdx < 0) { _selectOnly(path); return }
        const lo = Math.min(aIdx, bIdx), hi = Math.max(aIdx, bIdx)
        const m = {}
        for (let i = lo; i <= hi; i++) m[dirModel.get(i, "filePath")] = true
        selectedFiles = m
    }

    // ── Helpers ────────────────────────────────────────────────────────
    function _isImage(name) {
        return /\.(jpe?g|png|webp|gif|bmp|svg)$/i.test(name)
    }
    function _isVideo(name) {
        return /\.(mp4|webm|mkv|avi|mov|m4v)$/i.test(name)
    }
    function _mimeIcon(name, isDir) {
        if (isDir) return "folder"
        if (_isImage(name)) return "image"
        if (_isVideo(name)) return "movie"
        if (/\.(mp3|flac|ogg|wav|m4a|opus)$/i.test(name)) return "music_note"
        if (/\.(pdf)$/i.test(name)) return "picture_as_pdf"
        if (/\.(zip|rar|7z|tar|gz|xz|bz2)$/i.test(name)) return "folder_zip"
        if (/\.(txt|md|log|conf|ini)$/i.test(name)) return "description"
        if (/\.(sh|bash|zsh|fish|py|js|ts|rs|go|c|cpp|h|hpp|qml|json|yaml|yml|toml)$/i.test(name)) return "code"
        return "draft"
    }
    // XDG icon name for Quickshell.iconPath(); MaterialSymbol is the fallback.
    function _themeIconName(name, isDir) {
        const lower = name.toLowerCase()
        if (isDir) {
            // KDE/freedesktop convention for well-known folder names.
            const special = {
                "pictures": "folder-pictures",
                "images":   "folder-pictures",
                "music":    "folder-music",
                "videos":   "folder-videos",
                "downloads":"folder-download",
                "documents":"folder-documents",
                "desktop":  "user-desktop",
                "public":   "folder-publicshare",
                "templates":"folder-templates",
            }
            return special[lower] || "inode-directory"
        }
        if (_isImage(lower))  return "image-x-generic"
        if (_isVideo(lower))  return "video-x-generic"
        if (/\.(mp3|flac|ogg|wav|m4a|opus|aac|wma)$/i.test(lower))    return "audio-x-generic"
        if (/\.pdf$/i.test(lower))                                    return "application-pdf"
        if (/\.(zip|rar|7z|tar|gz|xz|bz2|zst)$/i.test(lower))         return "package-x-generic"
        if (/\.(txt|md|log|conf|ini|cfg|csv|tsv)$/i.test(lower))      return "text-x-generic"
        if (/\.(sh|bash|zsh|fish|py|js|ts|rs|go|c|cpp|h|hpp|qml|json|yaml|yml|toml|html|css|xml)$/i.test(lower))
            return "text-x-script"
        if (/\.(doc|docx|odt)$/i.test(lower))                         return "application-vnd.oasis.opendocument.text"
        if (/\.(xls|xlsx|ods)$/i.test(lower))                         return "application-vnd.oasis.opendocument.spreadsheet"
        if (/\.(ppt|pptx|odp)$/i.test(lower))                         return "application-vnd.oasis.opendocument.presentation"
        if (/\.(deb|rpm|pkg|appimage)$/i.test(lower))                 return "application-x-package"
        if (/\.(exe|msi|bat|cmd)$/i.test(lower))                      return "application-x-ms-dos-executable"
        if (/\.iso$/i.test(lower))                                    return "application-x-cd-image"
        if (/\.desktop$/i.test(lower))                                return "application-x-executable"
        return "application-x-zerosize"
    }

    // ── Per-icon menu ──────────────────────────────────────────────────
    // Acts on the whole selection; single-target items only show for one file.
    function _iconMenu(entry) {
        const paths = root._selectedCount() > 1
            ? root._selectedPaths()
            : [entry.path]
        const multi = paths.length > 1
        const openLabel = multi ? qsTr("Open %1 items").arg(paths.length)
                                : qsTr("Open")
        const cutLabel  = multi ? qsTr("Cut %1 items").arg(paths.length)
                                : qsTr("Cut")
        const copyLabel = multi ? qsTr("Copy %1 items").arg(paths.length)
                                : qsTr("Copy")
        const trashLabel = multi ? qsTr("Move %1 items to Trash").arg(paths.length)
                                 : qsTr("Move to Trash")
        const items = [
            { icon: "open_in_new", label: openLabel,
              onTriggered: () => { for (const p of paths) root._open(p) } },
        ]
        if (!multi) items.push({
            icon: "launch", label: qsTr("Open with…"),
            onTriggered: () => root._openWith(entry.path)
        })
        items.push({ separator: true })
        items.push({ icon: "content_cut",  label: cutLabel,
                     onTriggered: () => root._setClipboard(paths, true) })
        items.push({ icon: "content_copy", label: copyLabel,
                     onTriggered: () => root._setClipboard(paths, false) })
        if (!multi) items.push({
            icon: "drive_file_rename_outline", label: qsTr("Rename…"),
            onTriggered: () => root._rename(entry)
        })
        items.push({ separator: true })
        if (!multi) items.push({
            icon: "info", label: qsTr("Properties"),
            onTriggered: () => root._properties(entry.path)
        })
        items.push({ icon: "delete", label: trashLabel, danger: true,
                     onTriggered: () => { for (const p of paths) root._trash(p) } })
        return items
    }

    // ── Empty-space menu ───────────────────────────────────────────────
    function _emptyMenu() {
        return [
            { icon: "create_new_folder", label: qsTr("New folder"),
              onTriggered: () => root._newFolder() },
            { icon: "note_add",          label: qsTr("New text file"),
              onTriggered: () => root._newFile() },
            { separator: true },
            { icon: "content_paste",     label: qsTr("Paste"),
              onTriggered: () => root._paste() },
            { icon: "refresh",           label: qsTr("Refresh"),
              onTriggered: () => root._refresh() },
            { separator: true },
            // Sort by → field → order; each field gets an explicit direction submenu.
            { icon: "sort", label: qsTr("Sort by"), submenu: [
                { icon: "sort_by_alpha", label: qsTr("Name"),     submenu: root._orderMenu("name") },
                { icon: "schedule",      label: qsTr("Modified"), submenu: root._orderMenu("mtime") },
                { icon: "data_usage",    label: qsTr("Size"),     submenu: root._orderMenu("size") },
                { icon: "category",      label: qsTr("Type"),     submenu: root._orderMenu("type") },
            ]},
            { separator: true },
            { icon: "grid_view",         label: qsTr("Realign to grid"),
              onTriggered: () => { root.iconPositions = {}; root._savePositions() } },
            { icon: "widgets",           label: qsTr("Widgets"),
              submenu: root._widgetsMenu() },
            { icon: "wallpaper",         label: qsTr("Change wallpaper…"),
              onTriggered: () => GlobalStates.skwdWallOpen = true },
        ]
    }

    // Widget toggles; the menu has no checkboxes, so the icon shows on/off.
    readonly property var _widgetList: [
        { key: "clock",       icon: "schedule",          label: qsTr("Clock") },
        { key: "weather",     icon: "partly_cloudy_day", label: qsTr("Weather") },
        { key: "calendar",    icon: "calendar_month",    label: qsTr("Calendar") },
        { key: "worldClock",  icon: "public",            label: qsTr("World clock") },
        { key: "resources",   icon: "monitor_heart",     label: qsTr("Resources") },
        { key: "timers",      icon: "timer",             label: qsTr("Timers") },
        { key: "todo",        icon: "add_task",          label: qsTr("To-Do") },
        { key: "userCard",    icon: "person",            label: qsTr("User card") },
        { key: "visualizer",  icon: "graphic_eq",        label: qsTr("Visualizer") },
        { key: "customImage", icon: "image",             label: qsTr("Image") },
    ]

    function _widgetsMenu() {
        const w = Config.options.background.widgets
        const items = root._widgetList.map(e => ({
            icon: w[e.key].enable ? "check_box" : "check_box_outline_blank",
            label: e.label,
            onTriggered: () => w[e.key].enable = !w[e.key].enable
        }))
        items.push({ separator: true })
        items.push({
            icon: Config.options.background.widgetsLocked ? "lock" : "lock_open",
            label: qsTr("Lock positions"),
            onTriggered: () => Config.options.background.widgetsLocked = !Config.options.background.widgetsLocked
        })
        return items
    }

    // ── File operations (shelled out) ──────────────────────────────────
    Process { id: opProc; command: ["bash", "-c", "true"] }
    function _sh(cmd) {
        opProc.command = ["bash", "-c", cmd]
        opProc.running = false
        opProc.running = true
    }
    function _q(s) { return "'" + String(s).replace(/'/g, "'\\''") + "'" }

    function _open(path)      { _sh("xdg-open " + _q(path)) }
    function _openWith(path)  {
        _sh("(command -v handlr >/dev/null && handlr open " + _q(path)
            + " || command -v xdg-mime-launcher >/dev/null && xdg-mime-launcher "
            + _q(path) + " || xdg-open " + _q(path) + ") &")
    }
    function _trash(path)     {
        // Falls back to mv into the local trash dir.
        _sh("command -v gio >/dev/null && gio trash " + _q(path)
            + " || (mkdir -p \"$HOME/.local/share/Trash/files\" && mv "
            + _q(path) + " \"$HOME/.local/share/Trash/files/\")")
    }
    function _setClipboard(paths, cut) {
        // x-special/gnome-copied-files: the format Nautilus, Dolphin, etc. read.
        const op = cut ? "cut" : "copy"
        const lines = [op].concat(paths.map(p => "file://" + p)).join("\n")
        _sh("printf '%s' " + _q(lines)
            + " | wl-copy -t x-special/gnome-copied-files 2>/dev/null"
            + " || printf '%s' " + _q(lines)
            + " | xclip -i -selection clipboard -t x-special/gnome-copied-files 2>/dev/null")
    }
    function _paste() {
        const dest = (Quickshell.env("HOME") || "/home/caesar") + "/Desktop"
        _sh(`
            clip="$(wl-paste -t x-special/gnome-copied-files 2>/dev/null || xclip -o -selection clipboard -t x-special/gnome-copied-files 2>/dev/null)"
            [ -z "$clip" ] && exit 0
            op="$(printf '%s' "$clip" | head -n1)"
            urls="$(printf '%s' "$clip" | tail -n +2)"
            printf '%s\\n' "$urls" | while IFS= read -r u; do
                [ -z "$u" ] && continue
                src="$(printf '%s' "$u" | sed -e 's|^file://||' -e 's|%20| |g')"
                [ ! -e "$src" ] && continue
                if [ "$op" = "cut" ]; then
                    mv -n -- "$src" ${root._q(dest)}/
                else
                    cp -rn -- "$src" ${root._q(dest)}/
                fi
            done
        `.trim())
    }
    function _newFolder() {
        const dest = (Quickshell.env("HOME") || "/home/caesar") + "/Desktop"
        _sh(`d=${root._q(dest)}; i=1; n="New folder"; while [ -e "$d/$n" ]; do n="New folder ($i)"; i=$((i+1)); done; mkdir -p "$d/$n"`)
    }
    function _newFile() {
        const dest = (Quickshell.env("HOME") || "/home/caesar") + "/Desktop"
        _sh(`d=${root._q(dest)}; i=1; n="New file.txt"; while [ -e "$d/$n" ]; do n="New file ($i).txt"; i=$((i+1)); done; touch "$d/$n"`)
    }
    function _refresh() {
        dirModel.refresh()
    }
    function _properties(path) {
        _sh("(command -v kio-properties >/dev/null && kio-properties " + _q(path)
            + " || command -v nautilus >/dev/null && nautilus --select " + _q(path)
            + " || notify-send -a 'Desktop' 'Path' " + _q(path) + ") &")
    }
    function _rename(entry) {
        renameDialog.target = entry
        renameDialog.input  = entry.name
        renameDialog.opened = true
    }

    // ── Rename dialog ──────────────────────────────────────────────────
    Item {
        id: renameDialog
        anchors.fill: parent
        z: 9100
        visible: opened
        property bool opened: false
        property string input: ""
        property var target: ({ name: "", path: "" })

        MouseArea {
            anchors.fill: parent
            onClicked: renameDialog.opened = false
        }
        Rectangle {
            anchors.centerIn: parent
            width: 380; height: 130
            radius: Appearance.rounding.normal
            color: Appearance.colors.colLayer1
            border.width: 1; border.color: Appearance.colors.colLayer0Border
            MouseArea { anchors.fill: parent }  // swallow

            ColumnLayout {
                anchors.fill: parent; anchors.margins: 14
                spacing: 10
                StyledText {
                    text: qsTr("Rename")
                    font.pixelSize: Appearance.font.pixelSize.large
                    color: Appearance.colors.colOnLayer1
                }
                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: 36
                    radius: 6
                    color: Appearance.colors.colLayer2
                    border.width: 1; border.color: Appearance.colors.colLayer0Border
                    TextInput {
                        id: renameInput
                        anchors.fill: parent
                        anchors.leftMargin: 10; anchors.rightMargin: 10
                        verticalAlignment: TextInput.AlignVCenter
                        text: renameDialog.input
                        color: Appearance.colors.colOnLayer1
                        font.pixelSize: Appearance.font.pixelSize.normal
                        selectByMouse: true
                        focus: renameDialog.opened
                        onAccepted: {
                            const dir = renameDialog.target.path.replace(/\/[^/]+$/, "")
                            root._sh("mv -n -- " + root._q(renameDialog.target.path)
                                + " " + root._q(dir + "/" + text))
                            renameDialog.opened = false
                        }
                    }
                }
                RowLayout {
                    Layout.alignment: Qt.AlignRight
                    spacing: 8
                    Rectangle {
                        implicitWidth: 80; implicitHeight: 30
                        radius: 6
                        color: cnHov.hovered ? Appearance.colors.colLayer2 : "transparent"
                        border.width: 1; border.color: Appearance.colors.colLayer0Border
                        HoverHandler { id: cnHov }
                        TapHandler { onTapped: renameDialog.opened = false }
                        StyledText {
                            anchors.centerIn: parent
                            text: qsTr("Cancel")
                            color: Appearance.colors.colOnLayer1
                        }
                    }
                    Rectangle {
                        implicitWidth: 80; implicitHeight: 30
                        radius: 6
                        color: Appearance.m3colors.m3primary
                        TapHandler { onTapped: renameInput.accepted() }
                        StyledText {
                            anchors.centerIn: parent
                            text: qsTr("Rename")
                            color: Appearance.m3colors.m3onPrimary
                        }
                    }
                }
            }
        }
    }

    // ── Icon grid ──────────────────────────────────────────────────────
    Repeater {
        parent: safeArea
        model: ScriptModel { values: dirModel.entries }
        delegate: Item {
            id: tile
            required property int index
            required property var modelData
            readonly property string fileName:     tile.modelData.fileName
            readonly property string filePath:     tile.modelData.filePath
            readonly property bool   fileIsDir:    tile.modelData.fileIsDir
            readonly property var    fileModified: tile.modelData.fileModified
            readonly property int    fileSize:     tile.modelData.fileSize

            // Saved position (safeArea-relative), else grid slot by index.
            readonly property var savedPos: root.iconPositions[fileName]
            property real px: savedPos ? savedPos.x : ((index % root._cols) * root.gridStep)
            property real py: savedPos ? savedPos.y : (Math.floor(index / root._cols) * root.gridStepY)
            x: px
            y: py

            // Animate corrections (snap, re-flow), but not during a drag: icons would lag the cursor.
            Behavior on x {
                enabled: !root.anyDragging
                NumberAnimation { duration: 140; easing.type: Easing.OutCubic }
            }
            Behavior on y {
                enabled: !root.anyDragging
                NumberAnimation { duration: 140; easing.type: Easing.OutCubic }
            }

            width:  root.gridStep - 8
            height: root.cellSize + root.labelHeight

            readonly property bool selected: root._isSelected(filePath)
                || root._rubberbandHits[filePath] === true

            Component.onCompleted: root._registerTile(filePath, x, y, width, height)
            Component.onDestruction: root._unregisterTile(filePath)
            onXChanged: root._registerTile(filePath, x, y, width, height)
            onYChanged: root._registerTile(filePath, x, y, width, height)

            // Selection background
            Rectangle {
                anchors.fill: parent
                anchors.margins: -4
                radius: 10
                color: tile.selected
                    ? Qt.alpha(Appearance.m3colors.m3primary, 0.22)
                    : (hov.hovered ? Qt.alpha("white", 0.07) : "transparent")
                border.width: tile.selected ? 1 : 0
                border.color: Appearance.m3colors.m3primary
                Behavior on color { ColorAnimation { duration: 110 } }
            }
            HoverHandler { id: hov }

            // Icon (thumbnail if available, else MIME symbol)
            Item {
                id: iconBox
                anchors.top: parent.top
                anchors.horizontalCenter: parent.horizontalCenter
                width: root.cellSize
                height: root.cellSize

                // Thumbnail for images/videos, from the Freedesktop cache.
                Loader {
                    anchors.fill: parent
                    active: root.useThumbs && !tile.fileIsDir
                            && (root._isImage(tile.fileName) || root._isVideo(tile.fileName))
                    visible: active && status === Loader.Ready && item && item.status === Image.Ready
                    sourceComponent: ThumbnailImage {
                        sourcePath: tile.filePath
                        fillMode: Image.PreserveAspectCrop
                        anchors.margins: 6
                    }
                }
                // Themed icon; hidden while a thumbnail shows.
                Image {
                    id: themeIcon
                    anchors.centerIn: parent
                    width:  root.cellSize * 0.66
                    height: width
                    asynchronous: true
                    cache: true
                    smooth: true
                    mipmap: true
                    fillMode: Image.PreserveAspectFit
                    sourceSize.width: width * 2
                    sourceSize.height: height * 2
                    source: Quickshell.iconPath(
                        root._themeIconName(tile.fileName, tile.fileIsDir),
                        "")
                    visible: !(iconBox.children[0].active && iconBox.children[0].item
                               && iconBox.children[0].item.status === Image.Ready)
                              && status === Image.Ready
                }
                // MaterialSymbol fallback when neither thumbnail nor theme icon loaded.
                MaterialSymbol {
                    anchors.centerIn: parent
                    visible: !(iconBox.children[0].active && iconBox.children[0].item
                               && iconBox.children[0].item.status === Image.Ready)
                              && themeIcon.status !== Image.Ready
                    text: root._mimeIcon(tile.fileName, tile.fileIsDir)
                    iconSize: root.cellSize * 0.62
                    color: tile.fileIsDir
                        ? Appearance.m3colors.m3primary
                        : Appearance.colors.colOnLayer1
                }
            }

            // Label
            Rectangle {
                anchors.top: iconBox.bottom
                anchors.topMargin: 2
                anchors.horizontalCenter: parent.horizontalCenter
                width: parent.width
                height: root.labelHeight
                radius: 6
                color: tile.selected
                    ? Appearance.m3colors.m3primary
                    : Qt.alpha("black", 0.45)
                StyledText {
                    anchors.fill: parent
                    anchors.margins: 3
                    text: tile.fileName
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                    elide: Text.ElideMiddle
                    wrapMode: Text.NoWrap
                    color: tile.selected
                        ? Appearance.m3colors.m3onPrimary
                        : "white"
                    font.pixelSize: Appearance.font.pixelSize.small
                }
            }

            // Drag is left-button only, or right-click's menu never fires. Explicit
            // m.accepted everywhere, or the layer surface drops the release.
            MouseArea {
                id: tileMa
                anchors.fill: parent
                acceptedButtons: Qt.LeftButton | Qt.RightButton
                hoverEnabled: true
                cursorShape: pressed ? Qt.ClosedHandCursor : Qt.PointingHandCursor
                drag.target: tile
                drag.threshold: 4
                drag.axis: Drag.XAndYAxis
                property real _grabbedX: 0
                property real _grabbedY: 0
                property bool _dragged: false
                Connections {
                    target: tileMa.drag
                    function onActiveChanged() { root.anyDragging = tileMa.drag.active }
                }
                // Start positions of the selected tiles, so the group moves by the same delta.
                property var _dragGroupStart: ({})
                onPressed: (m) => {
                    _grabbedX = tile.x
                    _grabbedY = tile.y
                    _dragged = false
                    // KDE rules: ctrl toggles, shift ranges, plain press keeps a selected set or replaces it.
                    if (m.button === Qt.LeftButton) {
                        if (m.modifiers & Qt.ControlModifier) {
                            root._toggleSelected(tile.filePath)
                        } else if (m.modifiers & Qt.ShiftModifier) {
                            root._rangeSelect(tile.filePath)
                        } else if (!root._isSelected(tile.filePath)) {
                            root._selectOnly(tile.filePath)
                        } else {
                            root.selectionAnchor = tile.filePath
                        }
                    } else if (m.button === Qt.RightButton) {
                        // Right-press on an unselected tile narrows the selection to it.
                        if (!root._isSelected(tile.filePath))
                            root._selectOnly(tile.filePath)
                    }
                    if (m.button === Qt.LeftButton && root._isSelected(tile.filePath)) {
                        const snap = {}
                        for (const p of root._selectedPaths()) {
                            const b = root._tileBounds[p]
                            if (b) snap[p] = { x: b.x, y: b.y }
                        }
                        _dragGroupStart = snap
                    } else {
                        _dragGroupStart = {}
                    }
                    m.accepted = true
                }
                onPositionChanged: (m) => {
                    if (!pressed) return
                    const dx = tile.x - _grabbedX
                    const dy = tile.y - _grabbedY
                    if (!_dragged && (Math.abs(dx) > 2 || Math.abs(dy) > 2))
                        _dragged = true
                    // Live-shift the other selected tiles through the shared position store.
                    if (_dragged && Object.keys(_dragGroupStart).length > 1) {
                        const mp = Object.assign({}, root.iconPositions)
                        for (const p of Object.keys(_dragGroupStart)) {
                            if (p === tile.filePath) continue
                            for (let i = 0; i < dirModel.count; i++) {
                                if (dirModel.get(i, "filePath") === p) {
                                    const nm = dirModel.get(i, "fileName")
                                    const startP = _dragGroupStart[p]
                                    mp[nm] = {
                                        x: Math.max(0, startP.x + dx),
                                        y: Math.max(0, startP.y + dy),
                                    }
                                    break
                                }
                            }
                        }
                        root.iconPositions = mp
                    }
                }
                onReleased: (m) => {
                    if (_dragged) {
                        const dx = tile.x - _grabbedX
                        const dy = tile.y - _grabbedY
                        const sx = Math.max(0, Math.round(tile.x / root.gridStep) * root.gridStep)
                        const sy = Math.max(0, Math.round(tile.y / root.gridStepY) * root.gridStepY)
                        tile.px = sx
                        tile.py = sy
                        const mp = Object.assign({}, root.iconPositions)
                        mp[tile.fileName] = { x: sx, y: sy }
                        // Move the other selected tiles by the snapped delta.
                        const deltaX = sx - _grabbedX
                        const deltaY = sy - _grabbedY
                        for (const p of Object.keys(_dragGroupStart)) {
                            if (p === tile.filePath) continue
                            // Positions are keyed by name, not path.
                            for (let i = 0; i < dirModel.count; i++) {
                                if (dirModel.get(i, "filePath") === p) {
                                    const nm = dirModel.get(i, "fileName")
                                    const startP = _dragGroupStart[p]
                                    const nx = Math.max(0, startP.x + deltaX)
                                    const ny = Math.max(0, startP.y + deltaY)
                                    mp[nm] = { x: nx, y: ny }
                                    break
                                }
                            }
                        }
                        root.iconPositions = mp
                        root._savePositions()
                    }
                    _dragGroupStart = {}
                    m.accepted = true
                }
                // Long-press menu, guarded: a menu popping up mid-drag is worse than none.
                pressAndHoldInterval: 450
                onPressAndHold: (m) => {
                    if (m.button !== Qt.LeftButton) return
                    if (_dragged || drag.active) return
                    if (!root._isSelected(tile.filePath)) root._selectOnly(tile.filePath)
                    _dragged = true   // suppress the click that follows
                    ctx.popup(tile.x + m.x + root.insetLeft,
                              tile.y + m.y + root.insetTop,
                              root._iconMenu({
                                  name: tile.fileName,
                                  path: tile.filePath,
                                  isDir: tile.fileIsDir
                              }))
                    m.accepted = true
                }
                onClicked: (m) => {
                    if (_dragged) { m.accepted = true; return }
                    if (m.button === Qt.RightButton) {
                        ctx.popup(tile.x + m.x + root.insetLeft,
                                  tile.y + m.y + root.insetTop,
                                  root._iconMenu({
                                      name: tile.fileName,
                                      path: tile.filePath,
                                      isDir: tile.fileIsDir
                                  }))
                    }
                    m.accepted = true
                }
                onDoubleClicked: (m) => {
                    if (m.button === Qt.LeftButton) {
                        const paths = root._selectedCount() > 1
                            ? root._selectedPaths()
                            : [tile.filePath]
                        for (const p of paths) root._open(p)
                        m.accepted = true
                    }
                }
            }
        }
    }

    // Auto-grid: how many columns fit horizontally inside the safe area.
    readonly property int _cols: Math.max(1, Math.floor(safeArea.width / gridStep))

    // Give every icon a saved position: pinned keep theirs, the rest take the next
    // free cell. Stale entries reserve nothing.
    Timer {
        id: persistLayoutTimer
        interval: 900   // a refresh emits many countChanged in a burst
        repeat: false
        onTriggered: {
            if (!dirModel.ready || dirModel.count === 0)
                return;
            // Re-flow when the sort mode changed (saved positions beat model order).
            const wantSort = Config.options.desktop.icons.sortMode || "name";
            let next = Object.assign({}, root.iconPositions);
            if (next.__sort !== wantSort)
                next = { __sort: wantSort };
            const taken = {};
            const unplaced = [];
            for (let i = 0; i < dirModel.count; ++i) {
                const n = dirModel.get(i, "fileName");
                if (!n) continue;
                const p = next[n];
                if (p) taken[Math.round(p.y / root.gridStepY) + "," + Math.round(p.x / root.gridStep)] = true;
                else unplaced.push(n);
            }
            if (unplaced.length === 0) return;
            let cursor = 0;
            for (const n of unplaced) {
                let r, c;
                do {
                    r = Math.floor(cursor / root._cols);
                    c = cursor % root._cols;
                    cursor++;
                } while (taken[r + "," + c]);
                taken[r + "," + c] = true;
                next[n] = { x: c * root.gridStep, y: r * root.gridStepY };
            }
            root.iconPositions = next;
            root._savePositions();
        }
    }

    Connections {
        target: dirModel
        function onCountChanged() { persistLayoutTimer.restart() }
        function onReadyChanged() { if (dirModel.ready) persistLayoutTimer.restart() }
    }

    // ── Context menu surface (above everything in this content) ───────
    PopupContextMenu { id: ctx }

    // Delete trashes the selection, F2 renames a single one, Ctrl+A selects all, Esc clears.
    Keys.onPressed: (event) => {
        if (event.key === Qt.Key_Delete && root._selectedCount() > 0) {
            for (const p of root._selectedPaths()) _trash(p)
            _clearSelection()
            event.accepted = true
        } else if (event.key === Qt.Key_F2 && root._selectedCount() === 1) {
            const sel = root._selectedPaths()[0]
            for (let i = 0; i < dirModel.count; i++) {
                if (dirModel.get(i, "filePath") === sel) {
                    _rename({ name: dirModel.get(i, "fileName"), path: sel })
                    break
                }
            }
            event.accepted = true
        } else if (event.key === Qt.Key_A && (event.modifiers & Qt.ControlModifier)) {
            const m = {}
            for (let i = 0; i < dirModel.count; i++)
                m[dirModel.get(i, "filePath")] = true
            selectedFiles = m
            event.accepted = true
        } else if (event.key === Qt.Key_Escape) {
            _clearSelection()
            event.accepted = true
        }
    }
}








