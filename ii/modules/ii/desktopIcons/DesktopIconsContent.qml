// KDE-style desktop icons. Grid layout over ~/Desktop, snap-grid by default
// with free-form repositioning via drag. Right-click on an icon → file
// actions menu; right-click on empty space → folder/refresh/wallpaper menu.
//
// Memory budget: ~5 MB baseline (delegates + MIME icons). With thumbnails
// on, peak is ~30 MB for a typical Desktop folder (20–40 items × ~500 KB
// per cached pixmap). Both the panel and content are LazyPanelLoader-
// driven from the family file — toggled off, RAM cost is 0.
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
    // ── Reserved-edge insets ───────────────────────────────────────────
    // The Background layer surface spans the full screen — including the
    // strip the bar / vertical bar / dock occupies — so icons would draw
    // UNDER those without these offsets. Mirrors each panel's anchor
    // logic from its .qml so a config switch (bar on bottom, vertical
    // bar, dock off) automatically flips the inset to the matching edge.
    readonly property bool _barOnBottom: Config.options.bar.bottom === true
    readonly property bool _barIsVertical: Config.options.bar.vertical === true
    readonly property int _gap: Math.round(Appearance.sizes.hyprlandGapsOut)
    readonly property int insetTop: (!_barIsVertical && !_barOnBottom)
        ? Math.round(Appearance.sizes.barHeight) + _gap + padding : padding
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
    readonly property bool showHidden: Config.options.desktop.icons.showHidden
    readonly property bool useThumbs: Config.options.desktop.icons.thumbnails
    // FolderListModel.SortField: 0=Unsorted 1=Name 2=Time 3=Size 4=Type
    readonly property int sortFieldIdx: {
        switch (Config.options.desktop.icons.sortMode) {
            case "mtime": return 2
            case "size":  return 3
            case "type":  return 4
            default:      return 1
        }
    }

    // ── Persisted icon positions ───────────────────────────────────────
    // { filename → { x, y } } so dragging is sticky across sessions.
    //
    // Local state is the source of truth during a session. Config is only
    // read ONCE at startup. The previous onPositionsChanged handler
    // self-raced: our own _savePositions() write would trigger the
    // handler, which re-read Config (sometimes catching the disk-flushed
    // OLD value mid-debounce) and overwrote our fresh in-memory state.
    // That's why only one position was persisting despite many drags.
    property var iconPositions: ({})
    function _loadPositions() {
        try { iconPositions = JSON.parse(Config.options.desktop.icons.positions || "{}") }
        catch (e) { iconPositions = {} }
    }
    function _savePositions() {
        Config.options.desktop.icons.positions = JSON.stringify(iconPositions)
    }
    Component.onCompleted: _loadPositions()
    // No Connections on Config.options.desktop.icons.positions —
    // that handler caused the persistence-loss race. If the user resets
    // positions via Settings, they can reload Quickshell to pick it up.

    // Source of truth for the visible items.
    FolderListModel {
        id: dirModel
        folder: "file://" + (Quickshell.env("HOME") || "/home/caesar") + "/Desktop"
        showDirs: true
        showFiles: true
        showHidden: root.showHidden
        showDotAndDotDot: false
        sortField: root.sortFieldIdx
        sortReversed: false
    }

    // Safe area — everything (icons, click handlers) lives inside this
    // Item so the reserved bar / dock strips stay click-through and free.
    Item {
        id: safeArea
        anchors.fill: parent
        anchors.topMargin:    root.insetTop
        anchors.bottomMargin: root.insetBottom
        anchors.leftMargin:   root.insetLeft
        anchors.rightMargin:  root.insetRight

        // Empty-space handler: plain click clears selection, right-click
        // opens the folder menu, left-press+drag draws the rubberband.
        // z: -1 so per-tile MouseAreas (added later by the Repeater) win
        // when the press lands on an icon.
        MouseArea {
            id: emptyClickArea
            anchors.fill: parent
            acceptedButtons: Qt.LeftButton | Qt.RightButton
            hoverEnabled: true
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
                    // Don't clear yet — user might be starting a rubberband
                    // additive drag (Ctrl held). Clear happens in onClicked
                    // for non-drag presses, or in onReleased when a drag
                    // committed without Ctrl.
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
            // QML fires onClicked AFTER onReleased. We need a flag that
            // outlives the release so onClicked can tell "this was a
            // committed drag, don't clear selection". `_dragging` would
            // be reset by then; `_justDragged` persists until the next
            // press resets it.
            property bool _justDragged: false
            onReleased: (mouse) => {
                if (_dragging && root._rubberbandActive) {
                    // Commit the hit set into the real selection.
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

        // Rubberband visual. Drawn inside safeArea so its coords match
        // the tile coords directly. Sits on top of tiles (z: 100) but
        // is purely decorative — input goes through to the MouseArea.
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
            // Pure overlay — no input, so the MouseArea below still sees
            // the drag-motion events that grew this rectangle.
            enabled: false
        }
    }

    // ── Selection model ────────────────────────────────────────────────
    // path → true. var (not Set) so QML binding updates fire and value
    // semantics work the same on every reassign.
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
    // Range-select between the anchor and `path` using current model order.
    // ── Rubberband selection state ─────────────────────────────────────
    // Active during a left-press+drag on empty space. Coords are in
    // safeArea-local space so they match tile.x/tile.y directly.
    property bool _rubberbandActive: false
    property real _rubberbandX: 0
    property real _rubberbandY: 0
    property real _rubberbandW: 0
    property real _rubberbandH: 0
    // True when the drag started with Ctrl held → the rubberband UNIONs
    // with the prior selection on release instead of replacing it.
    property bool _rubberbandAdditive: false
    // Live hit map updated by _rubberbandRecompute. Tiles read it as a
    // SECOND source of truth (path → true) so they highlight during the
    // drag without committing into selectedFiles until release.
    property var _rubberbandHits: ({})
    // Recompute hits by intersecting the rubberband rect with each
    // tile's bounding box. O(N) per move — fine for a typical desktop
    // (10–100 items). Tiles register themselves via _tileBounds on
    // create / position change.
    property var _tileBounds: ({})   // path → {x, y, w, h}
    function _registerTile(path, x, y, w, h) {
        const m = Object.assign({}, _tileBounds)
        m[path] = { x: x, y: y, w: w, h: h }
        _tileBounds = m
    }
    function _unregisterTile(path) {
        if (!_tileBounds[path]) return
        const m = Object.assign({}, _tileBounds); delete m[path]; _tileBounds = m
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
    // XDG icon-name lookup so Quickshell.iconPath() resolves against
    // the user's installed icon theme (e.g. breeze-plus-dark). Special
    // folders inside ~/Desktop get themed sub-icons (Pictures, Music,
    // etc.); regular dirs get inode-directory; files get the standard
    // <type>-x-generic name pattern. Returned name feeds into
    // Quickshell.iconPath(name, fallback) — falls back to MaterialSymbol
    // if the theme has no match.
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
    // Acts on the WHOLE selection set when multi-select is active; the
    // right-press on a tile in onPressed already arranged for the
    // clicked tile to be in the selection. Single-target operations
    // (Open with…, Rename, Properties) only show when count == 1.
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
            { icon: "sort_by_alpha",     label: qsTr("Sort: Name"),
              onTriggered: () => Config.options.desktop.icons.sortMode = "name" },
            { icon: "schedule",          label: qsTr("Sort: Modified"),
              onTriggered: () => Config.options.desktop.icons.sortMode = "mtime" },
            { icon: "data_usage",        label: qsTr("Sort: Size"),
              onTriggered: () => Config.options.desktop.icons.sortMode = "size" },
            { separator: true },
            { icon: "grid_view",         label: qsTr("Realign to grid"),
              onTriggered: () => { root.iconPositions = {}; root._savePositions() } },
            { icon: "wallpaper",         label: qsTr("Change wallpaper…"),
              onTriggered: () => GlobalStates.skwdWallOpen = true },
        ]
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
        // Re-uses xdg-open; users with a chooser like rifle/handlr can swap
        // this. Kept light to avoid pulling in a full picker dialog.
        _sh("(command -v handlr >/dev/null && handlr open " + _q(path)
            + " || command -v xdg-mime-launcher >/dev/null && xdg-mime-launcher "
            + _q(path) + " || xdg-open " + _q(path) + ") &")
    }
    function _trash(path)     {
        // gio is in glib2 (already a system dep). Falls back to mv into a
        // local trash dir so the file isn't permanently lost.
        _sh("command -v gio >/dev/null && gio trash " + _q(path)
            + " || (mkdir -p \"$HOME/.local/share/Trash/files\" && mv "
            + _q(path) + " \"$HOME/.local/share/Trash/files/\")")
    }
    function _setClipboard(paths, cut) {
        // x-special/gnome-copied-files is the de-facto clipboard format for
        // file managers — Nautilus, Nemo, Dolphin, Caja all read it.
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
        // FolderListModel doesn't expose an explicit refresh; rebinding the
        // folder URL forces a re-scan.
        const f = dirModel.folder
        dirModel.folder = ""
        dirModel.folder = f
    }
    function _properties(path) {
        // Hand off to a desktop properties dialog if installed.
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
        model: dirModel
        delegate: Item {
            id: tile
            required property int    index
            required property string fileName
            required property string filePath
            required property bool   fileIsDir
            required property var    fileModified
            required property int    fileSize

            // Snap to grid by index unless we have a saved position.
            // Coordinates are RELATIVE to safeArea so changing the bar
            // position doesn't break saved layouts.
            readonly property var savedPos: root.iconPositions[fileName]
            property real px: savedPos ? savedPos.x : ((index % root._cols) * root.gridStep)
            property real py: savedPos ? savedPos.y : (Math.floor(index / root._cols) * (root.gridStep + 4))
            x: px
            y: py
            width:  root.cellSize
            height: root.cellSize + root.labelHeight

            readonly property bool selected: root._isSelected(filePath)
                || root._rubberbandHits[filePath] === true

            // Register / update bounds with the rubberband intersector
            // so it can hit-test in O(1) per move (instead of walking the
            // ListView delegates each time).
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

                // Thumbnail branch — only for previewable images / videos
                // when thumbnails are enabled. ThumbnailImage reads the
                // Freedesktop cache and triggers generation via the
                // existing vipsthumbnail / ffmpegthumbnailer pipeline, so
                // RAM stays bounded regardless of source file size.
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
                // Themed icon (from the user's icon theme — breeze-plus-dark
                // etc.) Resolved via Quickshell.iconPath against the XDG
                // icon-name spec. Hidden when the thumbnail Loader is
                // showing a real image preview. If the theme has no
                // matching icon, MaterialSymbol below catches it.
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
                // MaterialSymbol fallback — shown when there's no thumbnail
                // AND the theme couldn't resolve a real icon (themeIcon
                // failed to load). Keeps every tile rendered even if the
                // user's theme is incomplete.
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

            // Click / drag / context handlers. Drag is left-button only —
            // if right-click also armed a drag, the click would never
            // fire and the icon's context menu would silently fail.
            // Explicit `m.accepted = true` on every handler so the layer-
            // shell surface considers the event consumed (otherwise QML
            // composes a release-without-press and silently drops it).
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
                // Snapshot of every selected tile's start position when the
                // drag begins. Lets us move the whole selection together by
                // the same delta as the dragged tile.
                property var _dragGroupStart: ({})
                onPressed: (m) => {
                    _grabbedX = tile.x
                    _grabbedY = tile.y
                    _dragged = false
                    // Selection update follows KDE-style rules:
                    //   ctrl-press     → toggle this tile in the set
                    //   shift-press    → range-select from anchor
                    //   plain press on selected     → keep current set
                    //   plain press on unselected   → replace with this
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
                        // Right-press on an unselected tile narrows
                        // selection to just it so the menu acts on a
                        // single item. Right-press on an already-selected
                        // tile keeps the multi-selection intact.
                        if (!root._isSelected(tile.filePath))
                            root._selectOnly(tile.filePath)
                    }
                    // Cache start positions of every selected tile so the
                    // drag can move them together. Skip if right-pressing.
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
                    // Group-drag visual: live-shift every other selected
                    // tile by writing into the shared position store. The
                    // delegate's `savedPos` binding rebinds and they all
                    // move together while the user drags.
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
                        // Snap the dragged tile to grid.
                        const sx = Math.max(0, Math.round(tile.x / root.gridStep) * root.gridStep)
                        const sy = Math.max(0, Math.round(tile.y / (root.gridStep + 4)) * (root.gridStep + 4))
                        tile.px = sx
                        tile.py = sy
                        const mp = Object.assign({}, root.iconPositions)
                        mp[tile.fileName] = { x: sx, y: sy }
                        // Move every OTHER selected tile by the dragged
                        // tile's snapped delta, so the group stays in the
                        // same relative arrangement.
                        const deltaX = sx - _grabbedX
                        const deltaY = sy - _grabbedY
                        for (const p of Object.keys(_dragGroupStart)) {
                            if (p === tile.filePath) continue
                            // Look up that path's filename via the model
                            // (positions are keyed by name, not path).
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
                    // Left-click selection already settled in onPressed.
                    m.accepted = true
                }
                onDoubleClicked: (m) => {
                    if (m.button === Qt.LeftButton) {
                        // Opens every selected file — KDE-style "open the
                        // group" if user double-clicks while multiple are
                        // selected, falling back to just this one.
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

    // ── Context menu surface (above everything in this content) ───────
    PopupContextMenu { id: ctx }

    // Keyboard: Delete → trash every selected file, F2 → rename the
    // single-selected file (no-op when multi-selected — KDE blocks this
    // too because the rename dialog is intrinsically 1-target), Ctrl+A
    // → select everything in the folder, Esc → clear selection.
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
