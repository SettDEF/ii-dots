// Lightweight markdown viewer for personal cheatsheets.
//   - Folder tree on the left (FolderTree widget) — supports subfolders.
//   - Document outline (extracted #/##/### headings) for fast jumping.
//   - Clickable links open in the user's default browser.
//   - Last opened file + folder root persisted across reloads.
import qs
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io

Item {
    id: root

    // Strip the "file://" prefix Directories.documents adds for raw paths.
    readonly property string defaultRoot: {
        const url = Directories.documents + "/txt/cheatsheets"
        return url.startsWith("file://") ? url.slice(7) : url
    }

    // ── Persisted state (last file + root) ────────────────────────────
    property string activePath: Persistent.states.cheatsheet?.mdActivePath ?? ""
    property string rootPath: {
        const saved = Persistent.states.cheatsheet?.mdRootPath ?? ""
        return (saved && saved.length > 0) ? saved : defaultRoot
    }

    onActivePathChanged: {
        if (Persistent.states.cheatsheet)
            Persistent.states.cheatsheet.mdActivePath = activePath
    }
    onRootPathChanged: {
        if (Persistent.states.cheatsheet)
            Persistent.states.cheatsheet.mdRootPath = rootPath
    }

    // ── Per-file scroll memory ────────────────────────────────────────
    // Parse the persisted { path → contentY } map. Saved on every scroll
    // (debounced) and restored when a file finishes loading. Survives
    // closing the cheatsheet panel and reopening it with Super + /.
    property var scrollMap: {
        try {
            return JSON.parse(Persistent.states.cheatsheet?.mdScrollMap ?? "{}")
        } catch (e) {
            return ({})
        }
    }
    function _saveScrollPos(y) {
        if (!activePath || activePath.length === 0) return
        if (!Persistent.states.cheatsheet) return
        const m = Object.assign({}, scrollMap)
        m[activePath] = y
        scrollMap = m
        Persistent.states.cheatsheet.mdScrollMap = JSON.stringify(m)
    }
    function _restoreScrollPos() {
        if (!renderScroll || !renderScroll.contentItem) return
        const y = scrollMap[activePath]
        renderScroll.contentItem.contentY = (typeof y === "number") ? y : 0
    }
    Timer {
        id: scrollSaveDebounce
        interval: 350
        repeat: false
        onTriggered: {
            if (renderScroll && renderScroll.contentItem)
                root._saveScrollPos(renderScroll.contentItem.contentY)
        }
    }

    implicitWidth: 720
    implicitHeight: 480

    FileView {
        id: activeFile
        path: root.activePath
    }

    // ── Outline extraction ──────────────────────────────────────────
    // Parse #/##/### headings out of the loaded markdown so the user
    // can jump within a long document.
    property var outline: []
    function _rebuildOutline() {
        const text = activeFile.text() ?? ""
        const lines = text.split("\n")
        const out = []
        let inFence = false
        for (let i = 0; i < lines.length; i++) {
            const l = lines[i]
            if (l.startsWith("```") || l.startsWith("~~~")) inFence = !inFence
            if (inFence) continue
            const m = l.match(/^(#{1,3})\s+(.*?)\s*#*\s*$/)
            if (m) out.push({ level: m[1].length, text: m[2], line: i })
        }
        outline = out
    }
    Connections {
        target: activeFile
        function onLoaded() {
            Qt.callLater(root._rebuildOutline)
            // The TextArea needs a frame to compute its content size before
            // we can scroll to a meaningful Y; double callLater is enough.
            Qt.callLater(() => Qt.callLater(root._restoreScrollPos))
        }
    }
    Component.onCompleted: {
        Qt.callLater(_rebuildOutline)
        Qt.callLater(() => Qt.callLater(_restoreScrollPos))
    }

    // Scroll the rendered text to the line of the chosen heading.
    function _jumpToLine(line) {
        const text = activeFile.text() ?? ""
        if (!text) return
        const lines = text.split("\n")
        let pos = 0
        for (let i = 0; i < line && i < lines.length; i++) {
            pos += lines[i].length + 1
        }
        if (!renderArea) return
        renderArea.cursorPosition = pos
        const r = renderArea.cursorRectangle
        if (renderScroll && renderScroll.contentItem)
            renderScroll.contentItem.contentY = Math.max(0, r.y - 16)
    }

    RowLayout {
        anchors.fill: parent
        spacing: 0

        // ── Left: folder tree ──────────────────────────────────────────
        FolderTree {
            Layout.preferredWidth: 260
            Layout.fillHeight: true
            rootPath: root.rootPath
            nameFilters: ["*.md", "*.markdown", "*.txt"]
            selected: root.activePath
            onFileSelected: p => {
                root.activePath = p.startsWith("file://") ? p.slice(7) : p
            }
            onRootPathChanged: root.rootPath = rootPath
        }

        // ── Middle: rendered markdown ─────────────────────────────────
        ScrollView {
            id: renderScroll
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.leftMargin: 10
            Layout.rightMargin: 8
            ScrollBar.horizontal.policy: ScrollBar.AlwaysOff
            clip: true

            // Persist scroll position for the active file, debounced so we
            // don't hammer the state file on every wheel tick.
            Connections {
                target: renderScroll.contentItem
                function onContentYChanged() { scrollSaveDebounce.restart() }
            }

            TextArea {
                id: renderArea
                readOnly: true
                wrapMode: TextArea.Wrap
                textFormat: TextEdit.MarkdownText
                background: null
                color: Appearance.colors.colOnLayer0
                selectByMouse: true
                font.family: Appearance.font.family.reading ?? "sans-serif"
                font.pixelSize: Appearance.font.pixelSize.normal
                placeholderText: qsTr("Select a file from the tree on the left.")
                text: activeFile.text() ?? ""
                // Open clickable markdown links in xdg-open.
                onLinkActivated: link => Quickshell.execDetached(["xdg-open", link])
                // Hand cursor over hyperlinks.
                MouseArea {
                    anchors.fill: parent
                    acceptedButtons: Qt.NoButton
                    cursorShape: parent.hoveredLink.length > 0 ? Qt.PointingHandCursor : Qt.IBeamCursor
                }
            }
        }

        // ── Right: outline (sections) ────────────────────────────────
        Rectangle {
            Layout.preferredWidth: 220
            Layout.fillHeight: true
            color: Qt.alpha(Appearance.colors.colLayer1, 0.35)
            radius: Appearance.rounding.small
            visible: root.outline.length > 0

            ListView {
                anchors.fill: parent
                anchors.margins: 6
                clip: true
                spacing: 1
                model: root.outline
                ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

                delegate: AccentRow {
                    required property var modelData
                    width: ListView.view.width
                    label: modelData.text
                    depth: modelData.level - 1
                    dimInactive: modelData.level !== 1
                    onTriggered: root._jumpToLine(modelData.line)
                }
            }
        }
    }
}
