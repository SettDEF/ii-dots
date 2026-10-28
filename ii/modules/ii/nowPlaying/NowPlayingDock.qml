pragma ComponentBehavior: Bound
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland

/**
 * Now playing, docked at the right edge: what YouTube Music plays in the tela-zen tab, through the
 * ytm bridge (127.0.0.1:8788, ~/.scripts/ytm). Cover, title, a progress bar that moves on between
 * the page's reports, prev / play-pause / next, and synced lyrics when the page sends them
 * (state.lyrics: [{t, line}] or a plain string). Toggle: `qs -c ii ipc call nowPlaying toggle`.
 */
Scope {
    id: root
    readonly property string bridge: "http://127.0.0.1:8788"
    property var st: ({ connected: false })
    // the position moves on from what the page last said, at the time the bridge got it
    property real now: Date.now() / 1000
    readonly property real pos: {
        if (!st.connected || st.position == null) return 0
        const p = st.position + (st.playing ? Math.max(0, now - (st.seen || now)) : 0)
        return Math.min(p, st.duration || p)
    }
    readonly property var lines: Array.isArray(st.lyrics) ? st.lyrics : []
    // Song or Video: the page's own mode when it reports one (YT Music), else what was picked here
    property string pickedMode: "song"
    readonly property string mode: st.hasVideo !== true ? "song" : (st.mode === "song" || st.mode === "video") ? st.mode : pickedMode
    function setMode(m) { pickedMode = m; if (st.site === "music.youtube.com" || st.mode !== undefined) cmd("mode", m) }
    readonly property int lineAt: {
        let i = -1
        for (let k = 0; k < lines.length; k++) { if (lines[k].t <= pos + 0.25) i = k; else break }
        return i
    }

    function fetchState() {
        const x = new XMLHttpRequest()
        x.onreadystatechange = () => {
            if (x.readyState !== XMLHttpRequest.DONE) return
            try { root.st = x.status === 200 ? JSON.parse(x.responseText) : { connected: false } } catch (e) { root.st = { connected: false } }
        }
        x.open("GET", root.bridge + "/state"); x.send()
    }
    function cmd(c, arg) {
        const x = new XMLHttpRequest()
        x.open("POST", root.bridge + "/cmd"); x.setRequestHeader("Content-Type", "application/json")
        x.onreadystatechange = () => { if (x.readyState === XMLHttpRequest.DONE) refetch.restart() }
        x.send(JSON.stringify({ cmd: c, arg: arg ?? null }))
    }
    function clock(s) { s = Math.max(0, Math.floor(s || 0)); return `${Math.floor(s / 60)}:${String(s % 60).padStart(2, "0")}` }

    Timer { interval: 1000; running: GlobalStates.nowPlayingOpen; repeat: true; triggeredOnStart: true; onTriggered: root.fetchState() }
    Timer { interval: 100; running: GlobalStates.nowPlayingOpen && root.st.playing === true; repeat: true; onTriggered: root.now = Date.now() / 1000 }
    Timer { id: refetch; interval: 350; onTriggered: root.fetchState() }

    PanelWindow {
        id: win
        visible: GlobalStates.nowPlayingOpen
        anchors { right: true; top: true; bottom: true }
        implicitWidth: 360
        exclusiveZone: 0
        color: "transparent"
        WlrLayershell.namespace: "quickshell:nowPlaying"
        WlrLayershell.layer: WlrLayer.Top
        // the keyboard only after a click (Esc closes, Space plays/pauses), and gone when it is lost
        property bool keys: false
        WlrLayershell.keyboardFocus: keys ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None
        onVisibleChanged: keys = false
        mask: Region { item: card }

        Rectangle {
            id: card
            anchors { right: parent.right; verticalCenter: parent.verticalCenter; rightMargin: 12 }
            width: 336
            height: col.implicitHeight + 32
            radius: Appearance.rounding.large
            color: Appearance.m3colors.m3surfaceContainerLow
            border.width: 1; border.color: Appearance.colors.colLayer0Border
            // slides in from the edge
            opacity: GlobalStates.nowPlayingOpen ? 1 : 0
            transform: Translate { x: GlobalStates.nowPlayingOpen ? 0 : 40; Behavior on x { NumberAnimation { duration: 260; easing.type: Easing.OutCubic } } }
            Behavior on opacity { NumberAnimation { duration: 180 } }
            Behavior on height { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }

            PointHandler { acceptedButtons: Qt.AllButtons; onActiveChanged: if (active) { win.keys = true; Qt.callLater(() => card.forceActiveFocus()) } }
            readonly property bool winActive: Window.active
            onWinActiveChanged: if (!winActive) win.keys = false
            Keys.onPressed: (e) => {
                if (e.key === Qt.Key_Escape) { GlobalStates.nowPlayingOpen = false; e.accepted = true }
                else if (e.key === Qt.Key_Space) { root.cmd("toggle"); e.accepted = true }
                else if (e.key === Qt.Key_Right) { root.cmd("next"); e.accepted = true }
                else if (e.key === Qt.Key_Left) { root.cmd("prev"); e.accepted = true }
            }

            ColumnLayout {
                id: col
                anchors { left: parent.left; right: parent.right; top: parent.top; margins: 16 }
                spacing: 12

                // nothing connected: say how to get it
                ColumnLayout {
                    visible: !root.st.connected
                    Layout.fillWidth: true
                    spacing: 6
                    MaterialSymbol { Layout.alignment: Qt.AlignHCenter; text: "music_off"; iconSize: 36; color: Appearance.colors.colSubtext }
                    StyledText { Layout.fillWidth: true; horizontalAlignment: Text.AlignHCenter; wrapMode: Text.Wrap; text: "YouTube Music is not open"; font.pixelSize: Appearance.font.pixelSize.normal; font.weight: Font.DemiBold; color: Appearance.colors.colOnLayer0 }
                    StyledText { Layout.fillWidth: true; horizontalAlignment: Text.AlignHCenter; wrapMode: Text.Wrap; text: "Open music.youtube.com in tela; the tab can stay in the background."; font.pixelSize: Appearance.font.pixelSize.smaller; color: Appearance.colors.colSubtext }
                }

                // Song / Video, like YT Music's switch: only when the tab plays a video (state.hasVideo);
                // on YT Music it also flips the page's own mode (cmd "mode")
                Rectangle {
                    visible: root.st.connected && root.st.hasVideo === true
                    Layout.alignment: Qt.AlignHCenter
                    implicitWidth: modeRow.implicitWidth + 8; implicitHeight: 36; radius: 18
                    color: Appearance.colors.colLayer1
                    Row {
                        id: modeRow
                        anchors.centerIn: parent
                        spacing: 4
                        Repeater {
                            model: [["song", "Song", "music_note"], ["video", "Video", "videocam"]]
                            delegate: Rectangle {
                                id: mb
                                required property var modelData
                                readonly property bool on: root.mode === modelData[0]
                                width: mbRow.implicitWidth + 24; height: 28; radius: 14
                                color: on ? Appearance.colors.colPrimary : mbHov.hovered ? Appearance.colors.colLayer1Hover : "transparent"
                                Behavior on color { ColorAnimation { duration: 140 } }
                                Row {
                                    id: mbRow
                                    anchors.centerIn: parent
                                    spacing: 6
                                    MaterialSymbol { anchors.verticalCenter: parent.verticalCenter; text: mb.modelData[2]; iconSize: 16; color: mb.on ? Appearance.colors.colOnPrimary : Appearance.colors.colOnLayer1 }
                                    StyledText { anchors.verticalCenter: parent.verticalCenter; text: mb.modelData[1]; font.pixelSize: Appearance.font.pixelSize.smaller; font.weight: mb.on ? Font.DemiBold : Font.Normal; color: mb.on ? Appearance.colors.colOnPrimary : Appearance.colors.colOnLayer1 }
                                }
                                HoverHandler { id: mbHov; cursorShape: Qt.PointingHandCursor }
                                TapHandler { onTapped: root.setMode(mb.modelData[0]) }
                            }
                        }
                    }
                }

                // the cover (Song) or the tab's live picture (Video), the title
                Rectangle {
                    visible: root.st.connected
                    Layout.fillWidth: true
                    // a video is wide, a cover square; the change of shape animates
                    implicitHeight: root.mode === "video" ? width * 9 / 16 : width
                    Behavior on implicitHeight { NumberAnimation { duration: 240; easing.type: Easing.OutCubic } }
                    radius: Appearance.rounding.normal
                    color: Appearance.colors.colLayer1
                    clip: true
                    Image {
                        anchors.fill: parent
                        source: root.st.artUrl ?? ""
                        fillMode: Image.PreserveAspectCrop
                        asynchronous: true
                        opacity: status === Image.Ready ? 1 : 0
                        Behavior on opacity { NumberAnimation { duration: 300 } }
                    }
                    MaterialSymbol { visible: !root.st.artUrl; anchors.centerIn: parent; text: "album"; iconSize: 64; color: Appearance.colors.colSubtext }
                    // Video until the bridge streams the tab's picture (GET /tabs/<id>/video): the cover, dimmed, says so
                    Rectangle {
                        anchors.fill: parent
                        visible: root.mode === "video"
                        color: Qt.rgba(0, 0, 0, 0.55)
                        Column {
                            anchors.centerIn: parent
                            spacing: 6
                            MaterialSymbol { anchors.horizontalCenter: parent.horizontalCenter; text: "videocam"; iconSize: 32; color: "white" }
                            StyledText { anchors.horizontalCenter: parent.horizontalCenter; text: "The live picture comes with the next bridge"; font.pixelSize: Appearance.font.pixelSize.smallest; color: "white" }
                        }
                    }
                }
                ColumnLayout {
                    visible: root.st.connected
                    Layout.fillWidth: true
                    spacing: 2
                    StyledText { Layout.fillWidth: true; text: root.st.title ?? "—"; elide: Text.ElideRight; font.pixelSize: Appearance.font.pixelSize.large; font.weight: Font.DemiBold; color: Appearance.colors.colOnLayer0 }
                    StyledText { Layout.fillWidth: true; text: [root.st.artist, root.st.album].filter(x => x).join("  ·  "); elide: Text.ElideRight; font.pixelSize: Appearance.font.pixelSize.small; color: Appearance.colors.colSubtext }
                }

                // progress: moves on every 100 ms between reports
                ColumnLayout {
                    visible: root.st.connected && (root.st.duration ?? 0) > 0
                    Layout.fillWidth: true
                    spacing: 4
                    Rectangle {
                        Layout.fillWidth: true
                        implicitHeight: 6; radius: 3
                        color: Appearance.colors.colLayer1
                        Rectangle {
                            width: parent.width * Math.min(1, root.pos / Math.max(1, root.st.duration ?? 1))
                            height: parent.height; radius: 3
                            color: Appearance.colors.colPrimary
                            Behavior on width { NumberAnimation { duration: 120 } }
                        }
                    }
                    RowLayout {
                        Layout.fillWidth: true
                        StyledText { text: root.clock(root.pos); font.family: Appearance.font.family.monospace; font.pixelSize: Appearance.font.pixelSize.smallest; color: Appearance.colors.colSubtext }
                        Item { Layout.fillWidth: true }
                        StyledText { text: root.clock(root.st.duration); font.family: Appearance.font.family.monospace; font.pixelSize: Appearance.font.pixelSize.smallest; color: Appearance.colors.colSubtext }
                    }
                }

                // controls
                RowLayout {
                    visible: root.st.connected
                    Layout.alignment: Qt.AlignHCenter
                    spacing: 10
                    Repeater {
                        model: [["skip_previous", "prev", 40], [root.st.playing ? "pause" : "play_arrow", "toggle", 52], ["skip_next", "next", 40]]
                        delegate: Rectangle {
                            id: b
                            required property var modelData
                            readonly property bool main: modelData[1] === "toggle"
                            implicitWidth: modelData[2]; implicitHeight: modelData[2]; radius: width / 2
                            color: main ? Appearance.colors.colPrimary : bh.hovered ? Appearance.colors.colLayer1Hover : Appearance.colors.colLayer1
                            Behavior on color { ColorAnimation { duration: 140 } }
                            MaterialSymbol { anchors.centerIn: parent; text: b.modelData[0]; iconSize: b.main ? 28 : 22; color: b.main ? Appearance.colors.colOnPrimary : Appearance.colors.colOnLayer1 }
                            HoverHandler { id: bh; cursorShape: Qt.PointingHandCursor }
                            TapHandler { onTapped: root.cmd(b.modelData[1]) }
                        }
                    }
                }

                // synced lyrics: the current line in the middle, the list slides to it
                Item {
                    visible: root.st.connected && (root.lines.length > 0 || typeof root.st.lyrics === "string")
                    Layout.fillWidth: true
                    implicitHeight: 200
                    clip: true
                    ListView {
                        id: lyr
                        anchors.fill: parent
                        visible: root.lines.length > 0
                        model: root.lines
                        interactive: false
                        spacing: 6
                        preferredHighlightBegin: height / 2 - 14
                        preferredHighlightEnd: height / 2 + 14
                        highlightRangeMode: ListView.StrictlyEnforceRange
                        highlightMoveDuration: 420
                        currentIndex: Math.max(0, root.lineAt)
                        delegate: StyledText {
                            required property var modelData
                            required property int index
                            readonly property bool on: index === root.lineAt
                            width: lyr.width
                            wrapMode: Text.Wrap
                            text: modelData.line
                            font.pixelSize: Appearance.font.pixelSize.normal
                            font.weight: on ? Font.DemiBold : Font.Normal
                            color: on ? Appearance.colors.colOnLayer0 : Appearance.colors.colSubtext
                            opacity: on ? 1 : Math.max(0.25, 1 - Math.abs(index - root.lineAt) * 0.22)
                            Behavior on opacity { NumberAnimation { duration: 300 } }
                            Behavior on color { ColorAnimation { duration: 300 } }
                        }
                    }
                    // unsynced lyrics: just the text, scrolled with the song
                    StyledText {
                        visible: typeof root.st.lyrics === "string"
                        width: parent.width
                        y: -Math.max(0, implicitHeight - parent.height) * Math.min(1, root.pos / Math.max(1, root.st.duration ?? 1))
                        wrapMode: Text.Wrap
                        text: typeof root.st.lyrics === "string" ? root.st.lyrics : ""
                        font.pixelSize: Appearance.font.pixelSize.small
                        color: Appearance.colors.colSubtext
                        Behavior on y { NumberAnimation { duration: 900 } }
                    }
                }
            }
        }
    }
}
