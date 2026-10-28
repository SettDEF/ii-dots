pragma ComponentBehavior: Bound
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Widgets

/**
 * The share sheet: what `share` was given (files, links, text, the clipboard) and where it can go —
 * the apps that open it (from their desktop files, like Android) on top, then the targets in
 * ~/.config/share/targets (scripts). Keys: 1–9 run, arrows move, Enter runs, Esc closes.
 * The most used come first (~/.local/state/share/usage.json).
 */
Scope {
    id: root
    readonly property string runDir: (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/share"
    readonly property string usagePath: Quickshell.env("HOME") + "/.local/state/share/usage.json"

    property var share: ({ kind: "", items: [], targets: [] })
    property var usage: ({})
    FileView {
        id: itemFile
        path: root.runDir + "/item.json"
        watchChanges: true
        onFileChanged: reload()
        onLoaded: { try { root.share = JSON.parse(text()) } catch (e) { root.share = { kind: "", items: [], targets: [] } } }
    }
    FileView {
        id: usageFile
        path: root.usagePath
        onLoaded: { try { root.usage = JSON.parse(text()) } catch (e) { root.usage = {} } }
        onLoadFailed: root.usage = {}
    }
    function used(t) { return root.usage[t.id] ?? 0 }
    readonly property var apps: (share.targets ?? []).filter(t => t.app).sort((a, b) => used(b) - used(a)).slice(0, 8)
    readonly property var groups: ["open", "send", "copy", "save"]
    readonly property var actions: (share.targets ?? []).filter(t => !t.app)
        .sort((a, b) => (groups.indexOf(a.group) - groups.indexOf(b.group)) || (used(b) - used(a)))
    readonly property var all: apps.concat(actions)
    property int sel: 0

    function run(t) {
        if (!t) return
        const items = root.share.items ?? []
        if (t.app) Quickshell.execDetached(["gio", "launch", t.path].concat(items))
        else Quickshell.execDetached([t.path].concat(items))
        const u = Object.assign({}, root.usage); u[t.id] = (u[t.id] ?? 0) + 1; root.usage = u
        Quickshell.execDetached(["sh", "-c", 'mkdir -p "$(dirname "$1")" && printf %s "$2" > "$1"', "sh", root.usagePath, JSON.stringify(u)])
        GlobalStates.shareOpen = false
    }

    // what is shared, in words
    readonly property string title: {
        const it = share.items ?? []
        if (!it.length) return ""
        const a = String(it[0])
        if (share.kind === "url") return a.replace(/^[a-z]+:\/\//i, "").replace(/\/$/, "")
        if (share.kind === "text") return a.split("\n")[0].slice(0, 90)
        const name = a.slice(a.lastIndexOf("/") + 1)
        return it.length > 1 ? `${name} and ${it.length - 1} more` : name
    }
    readonly property string kindIcon: ({ url: "link", text: "notes", image: "image", video: "movie", audio: "music_note", dir: "folder", files: "folder_copy", "text-file": "description", file: "draft" })[share.kind] ?? "ios_share"

    PanelWindow {
        id: win
        visible: GlobalStates.shareOpen
        anchors { top: true; bottom: true; left: true; right: true }
        exclusiveZone: 0
        color: "transparent"
        WlrLayershell.namespace: "quickshell:share"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand
        mask: Region { item: card }

        Component.onCompleted: GlobalFocusGrab.addDismissable(win)
        Component.onDestruction: GlobalFocusGrab.removeDismissable(win)
        Connections {
            target: GlobalFocusGrab
            function onDismissed() { GlobalStates.shareOpen = false }
        }
        onVisibleChanged: if (visible) { itemFile.reload(); usageFile.reload(); root.sel = 0 }

        Timer {
            running: win.visible
            interval: 50; repeat: true; triggeredOnStart: true
            property int ticks: 0
            onRunningChanged: ticks = 0
            onTriggered: { card.forceActiveFocus(); if (++ticks >= 6) stop() }
        }

        Rectangle {
            id: card
            anchors.centerIn: parent
            width: 520
            height: col.implicitHeight + 32
            radius: Appearance.rounding.large
            color: Appearance.m3colors.m3surfaceContainerLow   // solid: the colLayer roles follow the shell's transparency
            border.width: 1; border.color: Appearance.colors.colLayer0Border
            focus: true
            Keys.onPressed: (e) => {
                if (e.key === Qt.Key_Escape) { GlobalStates.shareOpen = false; e.accepted = true }
                else if (e.key >= Qt.Key_1 && e.key <= Qt.Key_9) { root.run(root.all[e.key - Qt.Key_1]); e.accepted = true }
                else if (e.key === Qt.Key_Right || e.key === Qt.Key_Down || e.key === Qt.Key_Tab) { root.sel = Math.min(root.all.length - 1, root.sel + (e.key === Qt.Key_Down && root.sel < root.apps.length ? Math.min(4, root.apps.length - root.sel) : 1)); e.accepted = true }
                else if (e.key === Qt.Key_Left || e.key === Qt.Key_Up || e.key === Qt.Key_Backtab) { root.sel = Math.max(0, root.sel - (e.key === Qt.Key_Up && root.sel < root.apps.length + 1 && root.sel >= 4 ? 4 : 1)); e.accepted = true }
                else if (e.key === Qt.Key_Return || e.key === Qt.Key_Enter) { root.run(root.all[root.sel]); e.accepted = true }
            }

            ColumnLayout {
                id: col
                anchors { left: parent.left; right: parent.right; top: parent.top; margins: 16 }
                spacing: 12

                // what is shared
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 12
                    Rectangle {
                        implicitWidth: 44; implicitHeight: 44; radius: 22
                        color: Appearance.colors.colPrimaryContainer
                        MaterialSymbol { anchors.centerIn: parent; text: root.kindIcon; iconSize: 22; color: Appearance.colors.colOnPrimaryContainer }
                    }
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 0
                        StyledText { Layout.fillWidth: true; text: "Share"; font.pixelSize: Appearance.font.pixelSize.smaller; color: Appearance.colors.colSubtext }
                        StyledText { Layout.fillWidth: true; text: root.title || "nothing"; elide: Text.ElideMiddle; font.pixelSize: Appearance.font.pixelSize.normal; font.weight: Font.DemiBold; color: Appearance.colors.colOnLayer0 }
                    }
                    StyledText { text: `${(root.share.items ?? []).length} · ${root.share.kind}`; font.family: Appearance.font.family.monospace; font.pixelSize: Appearance.font.pixelSize.smallest; color: Appearance.colors.colSubtext }
                }

                // apps that open it
                StyledText { visible: root.apps.length > 0; text: "OPEN WITH"; font.pixelSize: Appearance.font.pixelSize.smallest; font.weight: Font.DemiBold; font.letterSpacing: 0.8; color: Appearance.colors.colSubtext }
                GridLayout {
                    visible: root.apps.length > 0
                    Layout.fillWidth: true
                    columns: 4
                    columnSpacing: 6; rowSpacing: 6
                    Repeater {
                        model: root.apps
                        delegate: Rectangle {
                            id: tile
                            required property var modelData
                            required property int index
                            readonly property bool on: root.sel === index
                            Layout.fillWidth: true
                            implicitHeight: 86
                            radius: Appearance.rounding.normal
                            color: on ? Appearance.colors.colLayer1Hover : tHov.hovered ? Appearance.colors.colLayer1 : "transparent"
                            Behavior on color { ColorAnimation { duration: 120 } }
                            ColumnLayout {
                                anchors.centerIn: parent
                                width: parent.width - 12
                                spacing: 4
                                IconImage { Layout.alignment: Qt.AlignHCenter; implicitSize: 36; source: Quickshell.iconPath(tile.modelData.icon, "application-x-executable") }
                                StyledText { Layout.fillWidth: true; horizontalAlignment: Text.AlignHCenter; text: tile.modelData.name; elide: Text.ElideRight; font.pixelSize: Appearance.font.pixelSize.smaller; color: Appearance.colors.colOnLayer0 }
                            }
                            StyledText { visible: tile.index < 9; anchors { right: parent.right; top: parent.top; margins: 6 } text: tile.index + 1; font.family: Appearance.font.family.monospace; font.pixelSize: Appearance.font.pixelSize.smallest; color: Appearance.colors.colSubtext }
                            HoverHandler { id: tHov; cursorShape: Qt.PointingHandCursor; onHoveredChanged: if (hovered) root.sel = tile.index }
                            TapHandler { onTapped: root.run(tile.modelData) }
                        }
                    }
                }

                // the targets (scripts), by group
                Rectangle { visible: root.apps.length > 0 && root.actions.length > 0; Layout.fillWidth: true; implicitHeight: 1; color: Appearance.colors.colLayer0Border }
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 2
                    Repeater {
                        model: root.actions
                        delegate: Rectangle {
                            id: row
                            required property var modelData
                            required property int index
                            readonly property int at: root.apps.length + index
                            readonly property bool on: root.sel === at
                            readonly property bool firstOfGroup: index === 0 || root.actions[index - 1].group !== modelData.group
                            Layout.fillWidth: true
                            Layout.topMargin: firstOfGroup && index > 0 ? 6 : 0
                            implicitHeight: 38
                            radius: Appearance.rounding.small
                            color: on ? Appearance.colors.colLayer1Hover : rHov.hovered ? Appearance.colors.colLayer1 : "transparent"
                            Behavior on color { ColorAnimation { duration: 120 } }
                            RowLayout {
                                anchors { fill: parent; leftMargin: 10; rightMargin: 12 }
                                spacing: 12
                                MaterialSymbol { text: row.modelData.icon; iconSize: 19; color: row.on ? Appearance.colors.colPrimary : Appearance.colors.colOnLayer0 }
                                StyledText { Layout.fillWidth: true; text: row.modelData.name; elide: Text.ElideRight; font.pixelSize: Appearance.font.pixelSize.small; color: Appearance.colors.colOnLayer0 }
                                StyledText { visible: row.firstOfGroup; text: row.modelData.group; font.pixelSize: Appearance.font.pixelSize.smallest; color: Appearance.colors.colSubtext }
                                StyledText { visible: row.at < 9; text: row.at + 1; font.family: Appearance.font.family.monospace; font.pixelSize: Appearance.font.pixelSize.smallest; color: Appearance.colors.colSubtext }
                            }
                            HoverHandler { id: rHov; cursorShape: Qt.PointingHandCursor; onHoveredChanged: if (hovered) root.sel = row.at }
                            TapHandler { onTapped: root.run(row.modelData) }
                        }
                    }
                }
                StyledText {
                    Layout.fillWidth: true
                    horizontalAlignment: Text.AlignHCenter
                    text: "1–9 pick  ·  arrows + Enter  ·  Esc close  ·  add targets in ~/.config/share/targets"
                    font.pixelSize: Appearance.font.pixelSize.smallest; color: Appearance.colors.colSubtext
                }
            }
        }
    }
}
