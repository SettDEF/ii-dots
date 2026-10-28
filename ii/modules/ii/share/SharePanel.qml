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
    // the "New target" form instead of the lists
    property bool making: false
    property var takes: []
    property string newIcon: "bolt"
    readonly property var kindsOffered: [["url", "Links"], ["files", "Files"], ["image", "Images"], ["video", "Video"], ["audio", "Audio"], ["text", "Text"]]
    readonly property var iconsOffered: ["bolt", "play_circle", "send", "cloud_upload", "edit_note", "translate", "terminal", "image", "music_note", "download"]
    // writes ~/.config/share/targets/60-<name> (the header the share script reads, the command once
    // per item), then shares the same items again so the new target shows at once
    function saveTarget(name, cmd) {
        if (!name.trim() || !cmd.trim() || !takes.length) return false
        const slug = name.trim().toLowerCase().replace(/[^a-z0-9]+/g, "-").replace(/^-|-$/g, "")
        const line = cmd.includes("{}") ? cmd.split("{}").join('"$x"') : cmd + ' "$x"'
        const body = ["#!/usr/bin/env bash", `# share-name: ${name.trim()}`, `# share-icon: ${newIcon}`,
            `# share-accepts: ${takes.join(" ")}`, "# share-group: open",
            "# made in the share sheet; edit freely ($@ is what was shared)",
            `for x in "$@"; do setsid -f ${line} >/dev/null 2>&1; done`, ""].join("\n")
        Quickshell.execDetached(["sh", "-c", 'mkdir -p "$1" && printf %s "$3" > "$1/60-$2" && chmod +x "$1/60-$2" && shift 3 && exec "$@"',
            "sh", Quickshell.env("HOME") + "/.config/share/targets", slug, body,
            Quickshell.env("HOME") + "/.scripts/apps/share/share"].concat(root.share.items ?? []))
        return true
    }

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
                if (root.making) return   // the form has the keys
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
                        StyledText { visible: !!root.share.from; Layout.fillWidth: true; text: `found from the text “${root.share.from}”`; elide: Text.ElideMiddle; font.pixelSize: Appearance.font.pixelSize.smallest; color: Appearance.colors.colSubtext }
                    }
                    StyledText { text: `${(root.share.items ?? []).length} · ${root.share.kind}`; font.family: Appearance.font.family.monospace; font.pixelSize: Appearance.font.pixelSize.smallest; color: Appearance.colors.colSubtext }
                }

                // apps that open it
                StyledText { visible: !root.making && root.apps.length > 0; text: "OPEN WITH"; font.pixelSize: Appearance.font.pixelSize.smallest; font.weight: Font.DemiBold; font.letterSpacing: 0.8; color: Appearance.colors.colSubtext }
                GridLayout {
                    visible: !root.making && root.apps.length > 0
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
                Rectangle { visible: !root.making && root.apps.length > 0 && root.actions.length > 0; Layout.fillWidth: true; implicitHeight: 1; color: Appearance.colors.colLayer0Border }
                ColumnLayout {
                    Layout.fillWidth: true
                    visible: !root.making
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
                // ── New target: a form, so nobody has to know the script header ──
                ColumnLayout {
                    visible: root.making
                    Layout.fillWidth: true
                    spacing: 8
                    StyledText { text: "NEW TARGET"; font.pixelSize: Appearance.font.pixelSize.smallest; font.weight: Font.DemiBold; font.letterSpacing: 0.8; color: Appearance.colors.colSubtext }
                    Rectangle {
                        Layout.fillWidth: true
                        implicitHeight: 38; radius: Appearance.rounding.small
                        color: Appearance.colors.colLayer1
                        border.width: nameField.activeFocus ? 1 : 0; border.color: Appearance.colors.colPrimary
                        TextInput {
                            id: nameField
                            anchors { fill: parent; leftMargin: 12; rightMargin: 12 }
                            verticalAlignment: TextInput.AlignVCenter
                            clip: true
                            color: Appearance.colors.colOnLayer1; font.pixelSize: Appearance.font.pixelSize.small
                            StyledText { visible: !nameField.text; anchors.verticalCenter: parent.verticalCenter; text: "Name, e.g. Upload to my server"; color: Appearance.colors.colSubtext; font.pixelSize: Appearance.font.pixelSize.small }
                            Keys.onEscapePressed: root.making = false
                        }
                    }
                    Rectangle {
                        Layout.fillWidth: true
                        implicitHeight: 38; radius: Appearance.rounding.small
                        color: Appearance.colors.colLayer1
                        border.width: cmdField.activeFocus ? 1 : 0; border.color: Appearance.colors.colPrimary
                        TextInput {
                            id: cmdField
                            anchors { fill: parent; leftMargin: 12; rightMargin: 12 }
                            verticalAlignment: TextInput.AlignVCenter
                            clip: true
                            color: Appearance.colors.colOnLayer1; font.pixelSize: Appearance.font.pixelSize.small; font.family: Appearance.font.family.monospace
                            StyledText { visible: !cmdField.text; anchors.verticalCenter: parent.verticalCenter; text: "Command, {} is the item: mpv --loop {}"; color: Appearance.colors.colSubtext; font.pixelSize: Appearance.font.pixelSize.small }
                            Keys.onEscapePressed: root.making = false
                        }
                    }
                    StyledText { text: "Takes"; font.pixelSize: Appearance.font.pixelSize.smaller; color: Appearance.colors.colSubtext }
                    Flow {
                        Layout.fillWidth: true
                        spacing: 6
                        Repeater {
                            model: root.kindsOffered
                            delegate: Rectangle {
                                id: kc
                                required property var modelData
                                readonly property bool on: root.takes.includes(modelData[0])
                                implicitWidth: kcT.implicitWidth + 24; implicitHeight: 30; radius: 15
                                color: on ? Appearance.colors.colPrimary : Appearance.colors.colLayer1
                                Behavior on color { ColorAnimation { duration: 140 } }
                                StyledText { id: kcT; anchors.centerIn: parent; text: kc.modelData[1]; font.pixelSize: Appearance.font.pixelSize.smaller; color: kc.on ? Appearance.colors.colOnPrimary : Appearance.colors.colOnLayer1 }
                                HoverHandler { cursorShape: Qt.PointingHandCursor }
                                TapHandler { onTapped: root.takes = kc.on ? root.takes.filter(k => k !== kc.modelData[0]) : root.takes.concat([kc.modelData[0]]) }
                            }
                        }
                    }
                    StyledText { text: "Icon"; font.pixelSize: Appearance.font.pixelSize.smaller; color: Appearance.colors.colSubtext }
                    Flow {
                        Layout.fillWidth: true
                        spacing: 4
                        Repeater {
                            model: root.iconsOffered
                            delegate: Rectangle {
                                id: ic
                                required property string modelData
                                implicitWidth: 34; implicitHeight: 34; radius: 17
                                color: root.newIcon === modelData ? Appearance.colors.colPrimaryContainer : icHov.hovered ? Appearance.colors.colLayer1 : "transparent"
                                MaterialSymbol { anchors.centerIn: parent; text: ic.modelData; iconSize: 19; color: root.newIcon === ic.modelData ? Appearance.colors.colOnPrimaryContainer : Appearance.colors.colOnLayer0 }
                                HoverHandler { id: icHov; cursorShape: Qt.PointingHandCursor }
                                TapHandler { onTapped: root.newIcon = ic.modelData }
                            }
                        }
                    }
                    RowLayout {
                        Layout.fillWidth: true
                        Layout.topMargin: 4
                        Item { Layout.fillWidth: true }
                        DialogButton { buttonText: "Cancel"; onClicked: root.making = false }
                        DialogButton {
                            buttonText: "Save target"
                            enabled: nameField.text.trim().length > 0 && cmdField.text.trim().length > 0 && root.takes.length > 0
                            onClicked: if (root.saveTarget(nameField.text, cmdField.text)) root.making = false
                        }
                    }
                }

                // footer: keys, and the way to add your own
                RowLayout {
                    Layout.fillWidth: true
                    visible: !root.making
                    StyledText { Layout.fillWidth: true; text: "1–9 pick  ·  arrows + Enter  ·  Esc close"; font.pixelSize: Appearance.font.pixelSize.smallest; color: Appearance.colors.colSubtext }
                    RippleButtonWithIcon {
                        materialIcon: "add"; mainText: "New target"
                        onClicked: { root.takes = [root.share.kind === "text-file" || root.share.kind === "file" ? "files" : root.share.kind]; root.newIcon = "bolt"; nameField.text = ""; cmdField.text = ""; root.making = true; nameField.forceActiveFocus() }
                    }
                    RippleButtonWithIcon {
                        materialIcon: "folder_open"; mainText: ""
                        onClicked: { Quickshell.execDetached(["xdg-open", Quickshell.env("HOME") + "/.config/share/targets"]); GlobalStates.shareOpen = false }
                        StyledToolTip { text: "The targets folder: one script per target" }
                    }
                }
            }
        }
    }
}
