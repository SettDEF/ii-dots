// Reusable folder-tree browser. Flat list with depth-based indentation —
// tap a folder to expand/collapse its children inline.
//
// Lightweight: each folder spawns one `find -maxdepth 1` per expand, and
// when collapsed its children are removed from the model.
//
// Usage:
//   FolderTree {
//       rootPath: "/home/me/notes"
//       nameFilters: ["*.md", "*.txt"]
//       onFileSelected: p => myFileViewer.path = p
//   }
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell.Io

Item {
    id: root

    // Inputs
    property string rootPath: ""
    property var nameFilters: ["*"]
    property bool showHidden: false
    property bool showHeader: true

    // Outputs
    property string selected: ""
    signal fileSelected(string filePath)

    onFileSelected: p => selected = p

    implicitWidth: 240
    implicitHeight: 320

    // Each row: { path, name, isDir, depth, expanded }
    ListModel { id: itemsModel }

    function _matches(name) {
        if (!nameFilters || nameFilters.length === 0) return true
        for (let i = 0; i < nameFilters.length; i++) {
            const pat = nameFilters[i]
            const rx = "^" + pat.replace(/[.+^${}()|[\]\\]/g, "\\$&").replace(/\*/g, ".*") + "$"
            if (new RegExp(rx, "i").test(name)) return true
        }
        return false
    }

    function _cmdFor(path) {
        const TAB = "\t"
        const skipDot = showHidden ? "" : "continue;;"
        return "for e in " + JSON.stringify(path) + "/*; do " +
               "  [ -e \"$e\" ] || continue; " +
               "  n=${e##*/}; " +
               "  case \"$n\" in .*) " + skipDot + " esac; " +
               "  if [ -d \"$e\" ]; then printf 'd" + TAB + "%s\\n' \"$n\"; " +
               "  else printf 'f" + TAB + "%s\\n' \"$n\"; fi; " +
               "done"
    }

    // Path that has been (or is being) seeded — second call is a no-op.
    property string _seededPath: ""

    function _seed() {
        if (rootPath.length === 0) return
        if (rootPath === _seededPath) return        // already kicked off / done
        _seededPath = rootPath
        itemsModel.clear()
        listProc.parentPath = rootPath
        listProc.insertAt   = 0
        listProc.depth      = 0
        listProc.exec({ command: ["bash", "-c", _cmdFor(rootPath)] })
    }

    function _expand(rowIndex) {
        const row = itemsModel.get(rowIndex)
        if (!row || !row.isDir) return
        itemsModel.setProperty(rowIndex, "expanded", true)
        listProc.parentPath = row.path
        listProc.insertAt   = rowIndex + 1
        listProc.depth      = row.depth + 1
        listProc.exec({ command: ["bash", "-c", _cmdFor(row.path)] })
    }

    function _collapse(rowIndex) {
        const row = itemsModel.get(rowIndex)
        if (!row || !row.isDir || !row.expanded) return
        itemsModel.setProperty(rowIndex, "expanded", false)
        const baseDepth = row.depth
        let end = rowIndex + 1
        while (end < itemsModel.count && itemsModel.get(end).depth > baseDepth) end++
        if (end > rowIndex + 1)
            itemsModel.remove(rowIndex + 1, end - (rowIndex + 1))
    }

    Process {
        id: listProc
        property int insertAt: 0
        property int depth: 0
        property string parentPath: ""
        stdout: StdioCollector {
            onStreamFinished: {
                const lines = text.split("\n").filter(l => l.length > 0)
                const dirs = []
                const files = []
                for (let i = 0; i < lines.length; i++) {
                    const parts = lines[i].split("\t")
                    if (parts.length < 2) continue
                    if (parts[0] === "d") dirs.push(parts[1])
                    else                  files.push(parts[1])
                }
                let pos = listProc.insertAt
                for (const d of dirs) {
                    itemsModel.insert(pos, {
                        path: listProc.parentPath + "/" + d,
                        name: d, isDir: true,
                        depth: listProc.depth, expanded: false
                    })
                    pos++
                }
                for (const f of files) {
                    if (!root._matches(f)) continue
                    itemsModel.insert(pos, {
                        path: listProc.parentPath + "/" + f,
                        name: f, isDir: false,
                        depth: listProc.depth, expanded: false
                    })
                    pos++
                }
            }
        }
    }

    Component.onCompleted: _seed()
    onRootPathChanged: _seed()

    ColumnLayout {
        anchors.fill: parent
        spacing: 4

        // ── Editable path header ──────────────────────────────────────
        Rectangle {
            visible: root.showHeader
            Layout.fillWidth: true
            Layout.preferredHeight: 32
            radius: Appearance.rounding.small
            color: Qt.alpha(Appearance.colors.colLayer1, 0.5)

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 8
                anchors.rightMargin: 4
                spacing: 6

                MaterialSymbol {
                    text: "folder_open"
                    iconSize: Appearance.font.pixelSize.small
                    color: Appearance.colors.colOnLayer1
                }
                TextField {
                    Layout.fillWidth: true
                    text: root.rootPath
                    selectByMouse: true
                    background: null
                    color: Appearance.colors.colOnLayer1
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    onEditingFinished: root.rootPath = text
                }
            }
        }

        // ── Flat list with depth indentation ──────────────────────────
        ListView {
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            model: itemsModel
            spacing: 2
            ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

            delegate: AccentRow {
                id: rowItem
                width: ListView.view.width
                // Access ListView model roles via implicit context properties.
                active: !model.isDir && model.path === root.selected
                depth:  model.depth
                icon: model.isDir
                    ? (model.expanded ? "folder_open" : "folder")
                    : "description"
                trailingIcon: model.isDir
                    ? (model.expanded ? "expand_more" : "chevron_right")
                    : ""
                label: model.isDir
                    ? model.name
                    : model.name.replace(/\.(md|markdown|txt)$/i, "")
                onTriggered: {
                    if (model.isDir) {
                        if (model.expanded) root._collapse(model.index)
                        else                 root._expand(model.index)
                    } else {
                        root.fileSelected(model.path)
                    }
                }
            }
        }
    }
}
