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
        const url = Directories.documents + "/Notes/Cheatsheets"
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

    // Everything refreshes on open, and nothing runs while closed: one
    // directory scan plus a re-read of the open file. No inotify watches, no
    // timers. The tradeoff is that an edit made WHILE the sheet is open is not
    // picked up until it is reopened.
    onVisibleChanged: {
        if (!visible) return;
        folderTree.refresh();
        if (root.activePath.length > 0) activeFile.reload();
    }

    FileView {
        id: activeFile
        path: root.activePath
    }

    // ── Outline extraction ──────────────────────────────────────────
    // Parse #/##/### headings out of the loaded markdown so the user
    // can jump within a long document.
    property var outline: []

    // Anchor id -> the heading it labels.
    //
    // These cheatsheets link internally with explicit markers -- kiefr_bible.md
    // alone has 104 of them, written as `<a id="s-a"></a>` on the line above the
    // heading. Qt's markdown renderer drops the tag from the rendered document
    // but still reports "#s-a" out of onLinkActivated, so the id can only be
    // resolved against the SOURCE text. Built here because this is already the
    // one pass over the source that knows where the headings are.
    property var anchorMap: ({})

    function _rebuildOutline() {
        const text = activeFile.text() ?? ""
        const lines = text.split("\n")
        const out = []
        const anchors = {}
        const seen = {}          // heading text -> how many already passed
        let pending = []         // anchor ids waiting for their heading
        let inFence = false
        for (let i = 0; i < lines.length; i++) {
            const l = lines[i]
            if (l.startsWith("```") || l.startsWith("~~~")) inFence = !inFence
            if (inFence) continue

            const am = l.match(/<a\s+(?:id|name)\s*=\s*"([^"]+)"\s*>\s*<\/a>/i)
            if (am) { pending.push(am[1]); continue }

            // 1..6, not 1..3: the outline only shows the top three levels, but a
            // link can perfectly well point at an #### heading and must still land.
            const m = l.match(/^(#{1,6})\s+(.*?)\s*#*\s*$/)
            if (m) {
                let txt = m[2]
                const attr = txt.match(/\s*\{#([^}]+)\}\s*$/)   // pandoc-style {#id}
                if (attr) { pending.push(attr[1]); txt = txt.replace(/\s*\{#[^}]+\}\s*$/, "") }

                const occ = seen[txt] ?? 0
                seen[txt] = occ + 1
                for (let a = 0; a < pending.length; a++)
                    anchors[pending[a]] = { text: txt, occurrence: occ }

                // GitHub-style slug too, so files WITHOUT explicit ids still work.
                const slug = txt.toLowerCase().replace(/[^\w\s-]/g, "").trim().replace(/\s+/g, "-")
                if (slug.length > 0 && anchors[slug] === undefined)
                    anchors[slug] = { text: txt, occurrence: occ }

                pending = []
                if (m[1].length <= 3) out.push({ level: m[1].length, text: txt, line: i })
            } else if (l.trim().length > 0) {
                pending = []     // anchor was not attached to a heading after all
            }
        }
        outline = out
        anchorMap = anchors
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

    // Scroll to a heading, by index into `outline`.
    //
    // This used to sum character offsets in the raw MARKDOWN and assign that to
    // cursorPosition — but cursorPosition indexes the RENDERED document, where
    // every "#", "**", backtick, table pipe and link bracket has been consumed.
    // The rendered text is far shorter than the source, so the error grew the
    // further down the file you clicked.
    //
    // Instead, search the rendered text for the heading's own words, which
    // survive rendering intact.
    // Scroll the rendered document to the Nth occurrence of a heading's text.
    // Returns false if it could not be located, so callers can fall back.
    function _scrollToHeadingText(text, occurrence) {
        if (!renderArea || !text) return false
        // getText() returns the rendered document as plain text, so its offsets
        // line up with cursorPosition. `renderArea.text` would give the source.
        const rendered = renderArea.getText(0, renderArea.length)
        if (!rendered) return false

        let pos = -1, from = 0
        for (let n = 0; n <= occurrence; n++) {
            pos = rendered.indexOf(text, from)
            if (pos < 0) return false
            from = pos + 1
        }

        renderArea.cursorPosition = pos
        const r = renderArea.cursorRectangle
        if (renderScroll && renderScroll.contentItem) {
            const maxY = Math.max(0, renderScroll.contentItem.contentHeight - renderScroll.height)
            renderScroll.contentItem.contentY = Math.min(maxY, Math.max(0, r.y - 16))
        }
        return true
    }

    function _jumpToHeading(idx) {
        const item = root.outline[idx]
        if (!item) return
        // Repeated heading text is common ("Notes", "Example"), so land on the
        // occurrence matching this outline entry rather than always the first.
        let occurrence = 0
        for (let i = 0; i < idx; i++)
            if (root.outline[i].text === item.text) occurrence++
        root._scrollToHeadingText(item.text, occurrence)
    }

    // Markdown link click. Three cases, and only the last one was handled before:
    // an in-document anchor, a link relative to the file, and an absolute URL.
    function _followLink(link) {
        if (!link || link.length === 0) return

        if (link.charAt(0) === "#") {
            const id = decodeURIComponent(link.slice(1))
            const target = root.anchorMap[id]
            if (target && root._scrollToHeadingText(target.text, target.occurrence)) return
            // Previously every one of these fell through to xdg-open, which was
            // handed the literal string "#s-a" and silently did nothing.
            console.log("[cheatsheet] no target for anchor", link)
            return
        }

        // A bare "other.md" would be resolved by xdg-open against the shell's
        // working directory, not the document's -- so make it absolute first.
        if (!/^[a-z][a-z0-9+.-]*:/i.test(link)) {
            const dir = root.activePath.replace(/\/[^\/]*$/, "")
            if (dir.length > 0) {
                Quickshell.execDetached(["xdg-open", dir + "/" + link])
                return
            }
        }
        Quickshell.execDetached(["xdg-open", link])
    }

    // ── Search ────────────────────────────────────────────────────────
    // Searches the RENDERED text, not the markdown source, for the same reason
    // the heading jump does: cursorPosition indexes the rendered document, so
    // matching against the source would select the wrong span.
    property string searchQuery: ""
    property var matchPositions: []
    property int matchIndex: -1

    function _runSearch() {
        root.matchPositions = []
        root.matchIndex = -1
        const q = root.searchQuery
        if (!renderArea || q.length < 2) {
            renderArea?.deselect()
            return
        }
        const hay = renderArea.getText(0, renderArea.length).toLowerCase()
        const needle = q.toLowerCase()
        const out = []
        let from = 0
        while (true) {
            const i = hay.indexOf(needle, from)
            if (i < 0) break
            out.push(i)
            from = i + needle.length
            if (out.length > 500) break   // pathological queries stay responsive
        }
        root.matchPositions = out
        if (out.length > 0) root._gotoMatch(0)
    }

    function _gotoMatch(i) {
        const n = root.matchPositions.length
        if (n === 0 || !renderArea) return
        // Wrap around in both directions.
        root.matchIndex = ((i % n) + n) % n
        const pos = root.matchPositions[root.matchIndex]
        renderArea.select(pos, pos + root.searchQuery.length)
        renderArea.cursorPosition = pos
        const r = renderArea.cursorRectangle
        if (renderScroll && renderScroll.contentItem) {
            const maxY = Math.max(0, renderScroll.contentItem.contentHeight - renderScroll.height)
            // Centred rather than pinned to the top, so there is context above.
            const target = r.y - renderScroll.height / 2 + r.height
            renderScroll.contentItem.contentY = Math.min(maxY, Math.max(0, target))
        }
    }

    function _nextMatch() { root._gotoMatch(root.matchIndex + 1) }
    function _prevMatch() { root._gotoMatch(root.matchIndex - 1) }

    function focusSearch() {
        searchField.forceActiveFocus()
        searchField.selectAll()
    }

    // Re-run when the document changes underneath an active query.
    onSearchQueryChanged: searchDebounce.restart()
    Timer {
        id: searchDebounce
        interval: 140
        onTriggered: root._runSearch()
    }


    RowLayout {
        anchors.fill: parent
        spacing: 0

        // ── Left: folder tree, with the search box docked underneath ───
        ColumnLayout {
            Layout.preferredWidth: 260
            Layout.fillHeight: true
            spacing: 6

            FolderTree {
                id: folderTree
                Layout.fillWidth: true
                Layout.fillHeight: true
                rootPath: root.rootPath
                nameFilters: ["*.md", "*.markdown", "*.txt"]
                selected: root.activePath
                onFileSelected: p => {
                    root.activePath = p.startsWith("file://") ? p.slice(7) : p
                }
                onRootPathChanged: root.rootPath = rootPath
            }

            // Docked at the bottom of the tree column rather than across the
            // top of the document. Full-width at the top it ate the first line
            // of every sheet and pushed the text down; here it sits in dead
            // space and the reading area starts at the very top again.
            Rectangle {
                Layout.fillWidth: true
                Layout.bottomMargin: 4
                implicitHeight: searchCol.implicitHeight + 12
                radius: Appearance.rounding.small
                color: Qt.alpha(Appearance.colors.colLayer1, 0.35)

                ColumnLayout {
                    id: searchCol
                    anchors.fill: parent
                    anchors.margins: 6
                    spacing: 4

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 6

                        MaterialSymbol {
                            text: "search"
                            iconSize: 17
                            color: Appearance.colors.colSubtext
                        }

                        ToolbarTextField {
                            id: searchField
                            Layout.fillWidth: true
                            implicitWidth: 0   // 260 px column: let it shrink
                            placeholderText: qsTr("Search (Ctrl+F)")
                            text: root.searchQuery
                            onTextChanged: root.searchQuery = text
                            // Enter walks matches; Shift+Enter walks back; Esc clears.
                            Keys.onReturnPressed: event => {
                                if (event.modifiers & Qt.ShiftModifier) root._prevMatch()
                                else root._nextMatch()
                                event.accepted = true
                            }
                            Keys.onEscapePressed: {
                                root.searchQuery = ""
                                text = ""
                                renderArea.deselect()
                            }
                        }
                    }

                    // Counter + arrows only once a query is live — otherwise
                    // the column stays a single slim row.
                    RowLayout {
                        Layout.fillWidth: true
                        visible: root.searchQuery.length >= 2
                        spacing: 2

                        StyledText {
                            Layout.fillWidth: true
                            Layout.leftMargin: 6
                            text: root.matchPositions.length > 0
                                ? `${root.matchIndex + 1}/${root.matchPositions.length}`
                                : qsTr("no matches")
                            font.family: Appearance.font.family.monospace
                            font.pixelSize: Appearance.font.pixelSize.smallest
                            color: Appearance.colors.colSubtext
                        }

                        SearchNavButton {
                            enabled: root.matchPositions.length > 0
                            opacity: enabled ? 1 : 0.35
                            icon: "keyboard_arrow_up"
                            onActivated: root._prevMatch()
                        }
                        SearchNavButton {
                            enabled: root.matchPositions.length > 0
                            opacity: enabled ? 1 : 0.35
                            icon: "keyboard_arrow_down"
                            onActivated: root._nextMatch()
                        }
                    }
                }
            }
        }

        // ── Middle: rendered markdown ─────────────────────────────────
        ScrollView {
            id: renderScroll
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.leftMargin: 20
            Layout.rightMargin: 16
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
                // Anchors scroll in-document; everything else goes to xdg-open.
                onLinkActivated: link => root._followLink(link)
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
                    required property int index
                    width: ListView.view.width
                    label: modelData.text
                    depth: modelData.level - 1
                    dimInactive: modelData.level !== 1
                    onTriggered: root._jumpToHeading(index)
                }
            }
        }
    }
}
