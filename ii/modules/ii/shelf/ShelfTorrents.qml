import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell

// Torrents sub-tab under Files.
//   - Header: status, totals, pause-all/resume-all, "+" opens add popup
//   - Filter chips with live counts + search field
//   - Per-state visual differentiation (error tint for missing-files)
//   - Inline delete-confirm (3.5s auto-cancel)
//   - Right-click row → context menu (pause/recheck/copy magnet/open folder/…)
Item {
    id: root

    // ── UI state ──────────────────────────────────────────────────────────
    // Filter is GLOBAL: BarContent renders the chip pills on the bar's right
    // cluster while this tab is open, just like Battle's sub-tab pills.
    property string searchQuery: ""
    property string pendingDeleteHash: ""

    readonly property var visibleTorrents: {
        const items  = (Qbt && Qbt.torrents) ? Qbt.torrents : []
        const filter = (GlobalStates.shelfTorrentsFilter || "all")
        const q      = (searchQuery || "").toLowerCase()
        const isAll  = filter === "all"
        const out = []
        for (let i = 0; i < items.length; ++i) {
            const t = items[i]
            const s = t.state || ""
            if (!isAll) {
                if (filter === "active"  && !Qbt.isDownloadingState(s)) continue
                if (filter === "seeding" && !Qbt.isSeedingState(s))     continue
                if (filter === "paused"  && !Qbt.isPausedState(s))      continue
                if (filter === "error"   && !Qbt.isErrorState(s))       continue
            }
            if (q.length > 0 && !(t.name || "").toLowerCase().includes(q)) continue
            out.push(t)
        }
        return out
    }

    // ── Header row (status, search, global actions, add) ─────────────────
    // Height matches the top bar exactly so the torrent list gets the same
    // vertical real estate it would have if the shelf were a fresh window.
    RowLayout {
        id: header
        anchors {
            top: parent.top
            left: parent.left; leftMargin: 14
            right: parent.right; rightMargin: 14
        }
        height: Appearance.sizes.baseBarHeight
        spacing: 8

        MaterialSymbol {
            text: Qbt.available ? "downloading" : "cloud_off"
            iconSize: 20
            color: Qbt.available ? Appearance.colors.colPrimary : Appearance.colors.colSubtext
        }
        StyledText {
            text: Qbt.available
                ? qsTr("%1 active · ↓ %2  ↑ %3")
                    .arg(Qbt.activeCount).arg(root.formatRate(Qbt.totalDown)).arg(root.formatRate(Qbt.totalUp))
                : qsTr("qBittorrent WebUI offline")
            color: Appearance.colors.colOnLayer0
            font.pixelSize: Appearance.font.pixelSize.normal
            elide: Text.ElideRight
        }
        // Flexible gap pushes the search + actions to the right.
        Item { Layout.fillWidth: true; Layout.preferredHeight: 1 }

        PillTextField {
            id: searchField
            visible: Qbt.available
            Layout.preferredWidth: 220
            Layout.preferredHeight: 34
            Layout.alignment: Qt.AlignVCenter
            placeholderText: qsTr("Search…")
            leadingIcon: "search"
            text: root.searchQuery
            onTextChanged: root.searchQuery = text
            onCleared: root.searchQuery = ""
        }
        IconToolbarButton {
            text: "pause"
            visible: Qbt.available && Qbt.activeCount > 0
            ToolTip.visible: hovered; ToolTip.text: qsTr("Pause all")
            onClicked: Qbt.pauseAll()
        }
        IconToolbarButton {
            text: "play_arrow"
            visible: Qbt.available && (Qbt.torrents.length - Qbt.activeCount) > 0
            ToolTip.visible: hovered; ToolTip.text: qsTr("Resume all")
            onClicked: Qbt.resumeAll()
        }
        IconToolbarButton {
            text: "add"
            enabled: Qbt.available
            ToolTip.visible: hovered; ToolTip.text: qsTr("Add torrent")
            onClicked: addPopup.open()
        }
    }

    // ── 3. Empty placeholder ──────────────────────────────────────────────
    Item {
        anchors {
            top: header.bottom; topMargin: 4
            left: parent.left; right: parent.right; bottom: parent.bottom
        }
        visible: visibleTorrents.length === 0
        ColumnLayout {
            anchors.centerIn: parent
            spacing: 8
            MaterialSymbol {
                Layout.alignment: Qt.AlignHCenter
                text: Qbt.available
                    ? (Qbt.torrents.length === 0 ? "inbox" : "filter_alt_off")
                    : "wifi_off"
                iconSize: 32
                color: Appearance.colors.colOnLayer0; opacity: 0.25
            }
            StyledText {
                Layout.alignment: Qt.AlignHCenter
                text: !Qbt.available ? qsTr("Start qBittorrent to see your downloads")
                    : Qbt.torrents.length === 0 ? qsTr("No torrents — click + to add one")
                    : qsTr("No torrents match this filter")
                color: Appearance.colors.colSubtext
                font.pixelSize: Appearance.font.pixelSize.small
            }
        }
    }

    // ── 4. Torrent list ───────────────────────────────────────────────────
    StyledListView {
        anchors {
            top: header.bottom; topMargin: 4
            left: parent.left; right: parent.right; bottom: parent.bottom
            leftMargin: 10; rightMargin: 10; bottomMargin: 10
        }
        clip: true
        spacing: 6
        visible: visibleTorrents.length > 0
        model: visibleTorrents

        delegate: Rectangle {
            id: row
            required property var modelData
            width: parent ? parent.width : 0
            height: 72
            radius: Appearance.rounding.normal

            readonly property string s: modelData.state || ""
            readonly property bool isPaused:   Qbt.isPausedState(s)
            readonly property bool isError:    Qbt.isErrorState(s)
            readonly property bool isSeeding:  Qbt.isSeedingState(s)
            readonly property bool isFinished: (modelData.progress ?? 0) >= 1.0
            readonly property bool confirmingDelete: root.pendingDeleteHash === modelData.hash

            color: isError ? Qt.rgba(Appearance.colors.colError.r,
                                     Appearance.colors.colError.g,
                                     Appearance.colors.colError.b, 0.10)
                           : Appearance.colors.colLayer1
            border.width: isError ? 1 : 0
            border.color: Appearance.colors.colError

            // Right-click captures the whole row → wallpaper-picker-style
            // context menu. Coords are mapped to root so the menu, which
            // overlays the tab Item, opens under the cursor.
            MouseArea {
                anchors.fill: parent
                acceptedButtons: Qt.RightButton
                onClicked: event => {
                    const p = row.mapToItem(root, event.x, event.y)
                    root._openRowMenu(row.modelData, p.x, p.y)
                }
            }

            RowLayout {
                anchors.fill: parent
                anchors.margins: 10
                spacing: 10

                Rectangle {
                    Layout.preferredWidth: 36
                    Layout.preferredHeight: 36
                    radius: 18
                    color: row.isError    ? Appearance.colors.colError
                         : row.isPaused   ? Appearance.colors.colLayer0
                         : row.isSeeding  ? Appearance.colors.colTertiary
                         : Appearance.colors.colPrimary
                    MaterialSymbol {
                        anchors.centerIn: parent
                        text: row.isError    ? "report_problem"
                            : row.isPaused   ? "play_arrow"
                            : row.isFinished ? "check"
                            : "pause"
                        iconSize: 18
                        color: row.isPaused ? Appearance.colors.colOnLayer0
                                            : Appearance.colors.colOnPrimary
                    }
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: row.isPaused ? Qbt.resume(row.modelData.hash)
                                                : Qbt.pause(row.modelData.hash)
                    }
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 4
                    StyledText {
                        text: row.modelData.name || qsTr("Unknown")
                        elide: Text.ElideRight
                        Layout.fillWidth: true
                        color: Appearance.colors.colOnLayer1
                        font.pixelSize: Appearance.font.pixelSize.small
                    }
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 6
                        Rectangle {
                            Layout.fillWidth: true
                            height: 4
                            radius: 2
                            color: Appearance.colors.colLayer0
                            Rectangle {
                                anchors.left: parent.left
                                anchors.top: parent.top
                                anchors.bottom: parent.bottom
                                width: parent.width * Math.max(0, Math.min(1, row.modelData.progress || 0))
                                radius: 2
                                color: row.isError    ? Appearance.colors.colError
                                     : row.isSeeding  ? Appearance.colors.colTertiary
                                     : row.isFinished ? Appearance.colors.colTertiary
                                     : row.isPaused   ? Appearance.colors.colSubtext
                                     : Appearance.colors.colPrimary
                            }
                        }
                        StyledText {
                            text: `${Math.floor((row.modelData.progress || 0) * 100)}%`
                            color: Appearance.colors.colSubtext
                            font.pixelSize: Appearance.font.pixelSize.smaller
                        }
                    }
                    StyledText {
                        text: {
                            if (row.isError) return qsTr("Missing files — qBittorrent can't find the saved data")
                            const d = row.modelData
                            const dl = root.formatRate(d.dlspeed || 0)
                            const up = root.formatRate(d.upspeed || 0)
                            const eta = root.formatEta(d.eta || 8640000)
                            const parts = [`↓${dl}`, `↑${up}`]
                            if (eta) parts.push(eta)
                            return parts.join(" · ")
                        }
                        color: row.isError ? Appearance.colors.colError : Appearance.colors.colSubtext
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        elide: Text.ElideRight
                        Layout.fillWidth: true
                    }
                }

                Item {
                    Layout.preferredWidth: row.confirmingDelete ? 92 : 32
                    Layout.preferredHeight: 32
                    Behavior on Layout.preferredWidth {
                        NumberAnimation { duration: 160; easing.type: Easing.OutCubic }
                    }
                    MaterialSymbol {
                        anchors.centerIn: parent
                        text: "close"
                        iconSize: 18
                        color: Appearance.colors.colSubtext
                        visible: !row.confirmingDelete
                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                root.pendingDeleteHash = row.modelData.hash
                                confirmExpiry.restart()
                            }
                        }
                    }
                    RowLayout {
                        anchors.fill: parent
                        spacing: 4
                        visible: row.confirmingDelete
                        IconToolbarButton {
                            text: "delete_outline"
                            ToolTip.visible: hovered; ToolTip.text: qsTr("Remove (keep files)")
                            onClicked: {
                                Qbt.deleteTorrent(row.modelData.hash, false)
                                root.pendingDeleteHash = ""
                            }
                        }
                        IconToolbarButton {
                            text: "delete_forever"
                            ToolTip.visible: hovered; ToolTip.text: qsTr("Remove + delete files (destructive)")
                            onClicked: {
                                Qbt.deleteTorrent(row.modelData.hash, true)
                                root.pendingDeleteHash = ""
                            }
                        }
                        IconToolbarButton {
                            text: "undo"
                            ToolTip.visible: hovered; ToolTip.text: qsTr("Cancel")
                            onClicked: root.pendingDeleteHash = ""
                        }
                    }
                }
            }
        }
    }

    Timer {
        id: confirmExpiry
        interval: 3500
        onTriggered: root.pendingDeleteHash = ""
    }

    // ── Add-torrent popup ─────────────────────────────────────────────────
    Popup {
        id: addPopup
        // Anchor to the centre of the tab
        anchors.centerIn: parent
        width: Math.min(540, root.width - 60)
        padding: 16
        modal: true
        focus: true
        closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside

        background: Rectangle {
            radius: Appearance.rounding.large
            color: Appearance.colors.colLayer1
            border.color: Appearance.m3colors.m3outline
            border.width: 1
        }

        onOpened: { addUrlField.text = ""; addUrlField.forceActiveFocus() }

        contentItem: ColumnLayout {
            spacing: 12
            StyledText {
                text: qsTr("Add torrent")
                font.pixelSize: Appearance.font.pixelSize.large
                color: Appearance.colors.colOnLayer1
            }
            StyledText {
                Layout.fillWidth: true
                text: qsTr("Paste a magnet link or .torrent URL. Use the save-path default from qBittorrent's preferences.")
                color: Appearance.colors.colSubtext
                font.pixelSize: Appearance.font.pixelSize.small
                wrapMode: Text.WordWrap
            }
            MaterialTextField {
                id: addUrlField
                Layout.fillWidth: true
                placeholderText: qsTr("magnet:?xt=… or https://…/file.torrent")
                onAccepted: addSubmit.clicked()
            }
            RowLayout {
                Layout.fillWidth: true
                spacing: 8
                Item { Layout.fillWidth: true }
                RippleButtonWithIcon {
                    materialIcon: "close"
                    mainText: qsTr("Cancel")
                    onClicked: addPopup.close()
                }
                RippleButtonWithIcon {
                    id: addSubmit
                    materialIcon: "add"
                    mainText: qsTr("Add")
                    enabled: addUrlField.text.trim().length > 0
                    onClicked: {
                        const url = addUrlField.text.trim()
                        if (!url) return
                        Qbt.addUrl(url, "")
                        addPopup.close()
                    }
                }
            }
        }
    }

    // ── Per-row context menu (wallpaper-picker style) ────────────────────
    PopupContextMenu { id: rowMenu }

    function _openRowMenu(t, x, y) {
        if (!t) return
        const isPaused = Qbt.isPausedState(t.state || "")
        const items = [
            { icon: isPaused ? "play_arrow" : "pause",
              label: isPaused ? qsTr("Resume") : qsTr("Pause"),
              onTriggered: () => isPaused ? Qbt.resume(t.hash) : Qbt.pause(t.hash) },
            { icon: "fast_forward", label: qsTr("Force resume"),
              onTriggered: () => Qbt._request("POST",
                  "/api/v2/torrents/setForceStart",
                  "hashes=" + encodeURIComponent(t.hash) + "&value=true",
                  () => Qbt.refresh()) },
            { icon: "refresh", label: qsTr("Re-check"),
              onTriggered: () => Qbt.recheck(t.hash) },
            { separator: true },
            { icon: "folder_open", label: qsTr("Open save folder"),
              onTriggered: () => {
                  const p = t.save_path || t.content_path || ""
                  if (p) Quickshell.execDetached(["xdg-open", p])
              } },
            { icon: "link", label: qsTr("Copy magnet link"),
              onTriggered: () => {
                  const m = t.magnet_uri || `magnet:?xt=urn:btih:${t.hash}`
                  Quickshell.execDetached(["sh", "-c",
                      `printf %s ${JSON.stringify(m)} | wl-copy`])
              } },
            { icon: "content_copy", label: qsTr("Copy name"),
              onTriggered: () => {
                  const n = t.name || ""
                  Quickshell.execDetached(["sh", "-c",
                      `printf %s ${JSON.stringify(n)} | wl-copy`])
              } },
            { separator: true },
            { icon: "delete_outline", label: qsTr("Remove (keep files)"),
              onTriggered: () => Qbt.deleteTorrent(t.hash, false) },
            { icon: "delete_forever", danger: true,
              label: qsTr("Remove + delete files"),
              onTriggered: () => Qbt.deleteTorrent(t.hash, true) },
        ]
        rowMenu.popup(x, y, items)
    }

    // ── Formatters ────────────────────────────────────────────────────────
    function formatRate(bps) {
        if (!bps || bps < 1) return "0 B/s"
        const u = ["B/s","KB/s","MB/s","GB/s"]
        let v = bps, i = 0
        while (v >= 1024 && i < u.length - 1) { v /= 1024; i++ }
        return v.toFixed(v < 10 ? 1 : 0) + " " + u[i]
    }
    function formatEta(sec) {
        if (sec === undefined || sec >= 8640000 || sec <= 0) return ""
        const h = Math.floor(sec / 3600)
        const m = Math.floor((sec % 3600) / 60)
        if (h > 0) return `${h}h ${m}m`
        if (m > 0) return `${m}m`
        return `${sec}s`
    }
}
