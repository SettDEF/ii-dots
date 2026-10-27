pragma ComponentBehavior: Bound
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.walltune
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Widgets

/**
 * Discord presence: the "Listening to YouTube Music" card set by the
 * BetterDiscord plugin YouTubeMusicPresence. Edits its options.json and
 * previews status.json — see services/DiscordPresence.qml.
 */
Scope {
    id: root

    component Caption: StyledText {
        Layout.fillWidth: true
        Layout.leftMargin: 4
        Layout.bottomMargin: -6
        font.pixelSize: Appearance.font.pixelSize.smallest
        font.weight: Font.Medium
        color: Appearance.colors.colSubtext
    }

    IpcHandler {
        target: "discordPresence"
        function toggle(): void { GlobalStates.discordPresenceOpen = !GlobalStates.discordPresenceOpen }
        function open(): void   { GlobalStates.discordPresenceOpen = true }
        function close(): void  { GlobalStates.discordPresenceOpen = false }
        // value is JSON, e.g. setOption lyrics false / setStyle title mono
        function setOption(key: string, value: string): void { DiscordPresence.set(key, JSON.parse(value)) }
        function setStyle(line: string, style: string): void { DiscordPresence.setStyle(line, style) }
    }

    StackedPanelLoader {
        isOpen: GlobalStates.discordPresenceOpen

        sourceComponent: StackedSettingsPanel {
            id: win
            panelId: "discordPresence"
            title: Translation.tr("Discord presence")
            icon: "music_note"
            onRequestClose: GlobalStates.discordPresenceOpen = false

            readonly property var opt: DiscordPresence.options
            readonly property var st: DiscordPresence.status
            property string openStyle: ""

            Component.onCompleted: DiscordPresence.watching = true
            Component.onDestruction: DiscordPresence.watching = false


            function fmt(ms) {
                const s = Math.max(0, Math.floor(ms / 1000));
                return `${Math.floor(s / 60)}:${String(s % 60).padStart(2, "0")}`;
            }

            // ── 1. Live preview ──────────────────────────────────────────
            Rectangle {
                id: preview
                Layout.fillWidth: true
                implicitHeight: pv.implicitHeight + 28
                radius: Appearance.rounding.normal
                color: Appearance.colors.colLayer1

                readonly property bool live: DiscordPresence.active
                readonly property var prog: win.st?.progress ?? null
                readonly property real elapsed: prog ? DiscordPresence.now - prog.start : 0
                readonly property real length: prog?.end ? prog.end - prog.start : 0
                readonly property string eq: {
                    const f = DiscordPresence.eqFrames;
                    if (!win.opt.equalizer) return "";
                    const i = Math.floor(DiscordPresence.now / (win.opt.animationSeconds * 1000)) % f.length;
                    return f[i] + " ";
                }

                ColumnLayout {
                    id: pv
                    anchors { left: parent.left; right: parent.right; top: parent.top; margins: 14 }
                    spacing: 10

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 6
                        StyledText {
                            Layout.fillWidth: true
                            text: Translation.tr("Listening to %1").arg(win.st?.name || "YouTube Music")
                            font.pixelSize: Appearance.font.pixelSize.smallest
                            font.weight: Font.DemiBold
                            color: Appearance.colors.colSubtext
                        }
                        // Is the plugin alive, and is it showing something?
                        Rectangle {
                            implicitWidth: stateRow.implicitWidth + 14
                            implicitHeight: 20
                            radius: Appearance.rounding.full
                            color: preview.live ? Qt.alpha(Appearance.colors.colPrimary, 0.18) : Appearance.colors.colLayer2
                            RowLayout {
                                id: stateRow
                                anchors.centerIn: parent
                                spacing: 5
                                Rectangle {
                                    implicitWidth: 6; implicitHeight: 6; radius: 3
                                    color: preview.live ? Appearance.colors.colPrimary
                                         : DiscordPresence.running ? Appearance.colors.colSubtext
                                         : Appearance.m3colors.m3error
                                }
                                StyledText {
                                    text: preview.live ? Translation.tr("Live")
                                        : !DiscordPresence.pluginEnabled ? Translation.tr("Plugin off")
                                        : DiscordPresence.running ? Translation.tr("Idle")
                                        : Translation.tr("Discord closed")
                                    font.pixelSize: Appearance.font.pixelSize.smallest
                                    color: preview.live ? Appearance.colors.colPrimary : Appearance.colors.colSubtext
                                }
                            }
                        }
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 12

                        ClippingRectangle {
                            Layout.preferredWidth: 76
                            Layout.preferredHeight: 76
                            Layout.alignment: Qt.AlignTop
                            radius: Appearance.rounding.verysmall
                            color: Appearance.colors.colLayer2
                            MaterialSymbol {
                                anchors.centerIn: parent
                                visible: cover.status !== Image.Ready
                                text: preview.live ? "album" : "music_off"
                                iconSize: 30
                                color: Appearance.colors.colSubtext
                            }
                            Image {
                                id: cover
                                anchors.fill: parent
                                source: preview.live ? (win.st?.cover ?? "") : ""
                                visible: status === Image.Ready
                                fillMode: Image.PreserveAspectCrop
                                asynchronous: true
                                sourceSize: Qt.size(152, 152)
                            }
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            Layout.alignment: Qt.AlignVCenter
                            spacing: 2
                            StyledText {
                                Layout.fillWidth: true
                                text: preview.live ? (win.st?.line1 ?? "")
                                    : !DiscordPresence.pluginEnabled ? Translation.tr("YouTubeMusicPresence is disabled")
                                    : DiscordPresence.running ? Translation.tr("Nothing playing")
                                    : Translation.tr("No word from Discord")
                                elide: Text.ElideRight
                                font.pixelSize: Appearance.font.pixelSize.small
                                font.weight: preview.live ? Font.Normal : Font.Medium
                                color: Appearance.colors.colOnLayer1
                            }
                            StyledText {
                                Layout.fillWidth: true
                                text: preview.live ? preview.eq + (win.st?.line2 ?? "")
                                    : !DiscordPresence.pluginEnabled ? Translation.tr("Turn it on in BetterDiscord's plugin list")
                                    : DiscordPresence.running ? Translation.tr("Plays scrobbled to Last.fm from YouTube Music show up here")
                                    : Translation.tr("The card shows while Discord runs")
                                elide: Text.ElideRight
                                wrapMode: preview.live ? Text.NoWrap : Text.Wrap
                                maximumLineCount: 2
                                font.pixelSize: Appearance.font.pixelSize.smaller
                                color: Appearance.colors.colSubtext
                            }
                            StyledText {
                                Layout.fillWidth: true
                                visible: preview.live
                                text: win.st?.line3 ?? ""
                                elide: Text.ElideRight
                                font.pixelSize: Appearance.font.pixelSize.smaller
                                color: Appearance.colors.colSubtext
                            }
                        }
                    }

                    // Progress, as Discord draws it under a Listening card.
                    RowLayout {
                        Layout.fillWidth: true
                        visible: preview.live && preview.prog !== null
                        spacing: 8
                        StyledText {
                            text: win.fmt(preview.length > 0 ? Math.min(preview.elapsed, preview.length) : preview.elapsed)
                            font.pixelSize: Appearance.font.pixelSize.smallest
                            font.family: Appearance.font.family.monospace
                            color: Appearance.colors.colSubtext
                        }
                        Rectangle {
                            Layout.fillWidth: true
                            implicitHeight: 4
                            radius: 2
                            color: Qt.alpha(Appearance.colors.colOnLayer1, 0.12)
                            Rectangle {
                                height: parent.height
                                radius: 2
                                width: preview.length > 0 ? parent.width * Math.min(1, preview.elapsed / preview.length) : 0
                                color: Appearance.colors.colOnLayer1
                            }
                        }
                        StyledText {
                            text: preview.length > 0 ? win.fmt(preview.length) : "–:––"
                            font.pixelSize: Appearance.font.pixelSize.smallest
                            font.family: Appearance.font.family.monospace
                            color: Appearance.colors.colSubtext
                        }
                    }

                    // The buttons viewers get under the card.
                    RowLayout {
                        Layout.fillWidth: true
                        visible: preview.live && (win.st?.buttons?.length ?? 0) > 0
                        spacing: 6
                        Repeater {
                            model: win.st?.buttons ?? []
                            delegate: Rectangle {
                                required property string modelData
                                Layout.fillWidth: true
                                implicitHeight: 28
                                radius: Appearance.rounding.verysmall
                                color: Qt.alpha(Appearance.colors.colOnLayer1, 0.08)
                                StyledText {
                                    anchors.centerIn: parent
                                    width: parent.width - 12
                                    horizontalAlignment: Text.AlignHCenter
                                    elide: Text.ElideRight
                                    text: parent.modelData
                                    font.pixelSize: Appearance.font.pixelSize.smallest
                                    color: Appearance.colors.colOnLayer2
                                }
                            }
                        }
                    }

                    // Which game is being kept off the card right now.
                    RowLayout {
                        Layout.fillWidth: true
                        visible: preview.live && !!win.st?.gameHidden
                        spacing: 6
                        MaterialSymbol { text: "visibility_off"; iconSize: 14; color: Appearance.colors.colSubtext }
                        StyledText {
                            Layout.fillWidth: true
                            text: Translation.tr("Hiding “Playing %1” while music shows").arg(win.st?.gameHidden ?? "")
                            elide: Text.ElideRight
                            font.pixelSize: Appearance.font.pixelSize.smallest
                            color: Appearance.colors.colSubtext
                        }
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        visible: DiscordPresence.fileBad || (DiscordPresence.running && !!win.st?.error)
                        spacing: 6
                        MaterialSymbol { text: "error"; iconSize: 14; color: Appearance.m3colors.m3error }
                        StyledText {
                            Layout.fillWidth: true
                            text: DiscordPresence.fileBad ? Translation.tr("options.json is not valid JSON; the plugin keeps its last good options")
                                                          : (win.st?.error ?? "")
                            wrapMode: Text.Wrap
                            maximumLineCount: 3
                            elide: Text.ElideRight
                            font.pixelSize: Appearance.font.pixelSize.smallest
                            color: Appearance.m3colors.m3error
                        }
                    }
                }
            }

            // ── 2. Behaviour ─────────────────────────────────────────────
            Caption { text: Translation.tr("Behaviour") }
            PaletteCard {
                PaletteRow {
                    glyph: "sports_esports"
                    title: Translation.tr("Hide games while listening")
                    subtitle: Translation.tr("Music stays the activity people see")
                    trailing: "switch"
                    isOn: win.opt.hideGamesWhileListening
                    lit: isOn
                    onSwitched: DiscordPresence.set("hideGamesWhileListening", !isOn)
                }
                PaletteDivider {}
                PaletteRow {
                    glyph: "lyrics"
                    title: Translation.tr("Synced lyrics")
                    subtitle: Translation.tr("Line 3 follows the song, from lrclib.net")
                    trailing: "switch"
                    isOn: win.opt.lyrics
                    lit: isOn
                    onSwitched: DiscordPresence.set("lyrics", !isOn)
                }
                PaletteDivider {}
                PaletteRow {
                    glyph: "equalizer"
                    title: Translation.tr("Equalizer")
                    subtitle: DiscordPresence.eqFrames[0] + "  " + Translation.tr("animated, before the artist")
                    trailing: "switch"
                    isOn: win.opt.equalizer
                    lit: isOn
                    onSwitched: DiscordPresence.set("equalizer", !isOn)
                }
                PaletteDivider {}
                PaletteRow {
                    glyph: "smart_display"
                    title: Translation.tr("“Listen on YouTube Music” button")
                    trailing: "switch"
                    isOn: win.opt.buttons.includes("youtubemusic")
                    lit: isOn
                    onSwitched: DiscordPresence.toggleButton("youtubemusic")
                }
                PaletteDivider {}
                PaletteRow {
                    glyph: "link"
                    title: Translation.tr("“Last.fm” button")
                    trailing: "switch"
                    isOn: win.opt.buttons.includes("lastfm")
                    lit: isOn
                    onSwitched: DiscordPresence.toggleButton("lastfm")
                }
            }

            // ── 3. Text style ────────────────────────────────────────────
            Caption { text: Translation.tr("Text style") }
            PaletteCard {
                Repeater {
                    model: [
                        { id: "title",  glyph: "title",          label: Translation.tr("Title"),  sample: "Song title" },
                        { id: "artist", glyph: "person",         label: Translation.tr("Artist"), sample: "Artist" },
                        { id: "info",   glyph: "info",           label: Translation.tr("Line 3"), sample: "Album" },
                        { id: "lyrics", glyph: "lyrics",         label: Translation.tr("Lyrics"), sample: "Lyric line" },
                    ]
                    delegate: ColumnLayout {
                        id: line
                        required property var modelData
                        required property int index
                        readonly property string cur: win.opt.style[modelData.id] ?? "plain"
                        readonly property bool open: win.openStyle === modelData.id
                        Layout.fillWidth: true
                        spacing: 0

                        PaletteDivider { visible: line.index > 0 }
                        PaletteRow {
                            glyph: line.modelData.glyph
                            title: line.modelData.label
                            value: DiscordPresence.styled(line.cur, DiscordPresence.styleNames[line.cur])
                            lit: line.open
                            chevronIcon: "expand_more"
                            chevronRotation: line.open ? 180 : 0
                            onClicked: win.openStyle = line.open ? "" : line.modelData.id
                        }
                        // Each choice is written in its own style, so you pick by eye.
                        Flow {
                            Layout.fillWidth: true
                            Layout.leftMargin: 44
                            Layout.rightMargin: 10
                            Layout.bottomMargin: 10
                            visible: line.open
                            spacing: 5
                            Repeater {
                                model: DiscordPresence.styleIds
                                delegate: RippleButton {
                                    id: chip
                                    required property string modelData
                                    readonly property bool sel: chip.modelData === line.cur
                                    implicitHeight: 28
                                    implicitWidth: chipText.implicitWidth + 22
                                    buttonRadius: Appearance.rounding.full
                                    colBackground: chip.sel ? Appearance.colors.colPrimary : Qt.alpha(Appearance.colors.colOnLayer1, 0.06)
                                    colBackgroundHover: chip.sel ? Appearance.colors.colPrimary : Appearance.colors.colLayer2Hover
                                    onClicked: DiscordPresence.setStyle(line.modelData.id, chip.modelData)
                                    contentItem: StyledText {
                                        id: chipText
                                        anchors.centerIn: parent
                                        text: DiscordPresence.styled(chip.modelData, DiscordPresence.styleNames[chip.modelData])
                                        font.pixelSize: Appearance.font.pixelSize.smaller
                                        color: chip.sel ? Appearance.colors.colOnPrimary : Appearance.colors.colOnLayer2
                                    }
                                }
                            }
                        }
                    }
                }
            }

            // ── 4. Timing ────────────────────────────────────────────────
            Caption { text: Translation.tr("Timing") }
            PaletteCard {
                PaletteSlider {
                    title: Translation.tr("Text changes every")
                    valueText: win.opt.animationSeconds + " s"
                    from: 1; to: 10; stepSize: 1
                    value: win.opt.animationSeconds
                    onMoved: v => DiscordPresence.set("animationSeconds", Math.round(v))
                }
                PaletteSlider {
                    title: Translation.tr("Line 3 rotates every")
                    valueText: win.opt.rotateSeconds + " s"
                    from: 2; to: 15; stepSize: 1
                    value: win.opt.rotateSeconds
                    onMoved: v => DiscordPresence.set("rotateSeconds", Math.round(v))
                }
                StyledText {
                    Layout.fillWidth: true
                    Layout.margins: 10
                    Layout.topMargin: 4
                    text: Translation.tr("Discord sends at most 5 presence updates per 20 s, so viewers see fast changes in jumps; you see every step.")
                    wrapMode: Text.Wrap
                    font.pixelSize: Appearance.font.pixelSize.smallest
                    color: Appearance.colors.colSubtext
                }
            }

            // ── 5. Cover order ───────────────────────────────────────────
            Caption { text: Translation.tr("Cover, first match wins") }
            PaletteCard {
                Repeater {
                    model: win.opt.coverOrder
                    delegate: ColumnLayout {
                        id: src
                        required property string modelData
                        required property int index
                        Layout.fillWidth: true
                        spacing: 0
                        PaletteDivider { visible: src.index > 0 }
                        RowLayout {
                            Layout.fillWidth: true
                            Layout.leftMargin: 10
                            Layout.rightMargin: 6
                            Layout.preferredHeight: 40
                            spacing: 12
                            MaterialSymbol {
                                Layout.preferredWidth: 22
                                horizontalAlignment: Text.AlignHCenter
                                text: DiscordPresence.coverIcons[src.modelData] ?? "image"
                                iconSize: Appearance.font.pixelSize.larger
                                color: src.index === 0 ? Appearance.colors.colPrimary : Appearance.colors.colSubtext
                            }
                            StyledText {
                                Layout.fillWidth: true
                                text: DiscordPresence.coverNames[src.modelData] ?? src.modelData
                                font.pixelSize: Appearance.font.pixelSize.smaller
                                color: Appearance.colors.colOnLayer1
                            }
                            StyledText {
                                text: String(src.index + 1)
                                font.pixelSize: Appearance.font.pixelSize.smallest
                                font.family: Appearance.font.family.monospace
                                color: Appearance.colors.colSubtext
                            }
                            Repeater {
                                model: [{ icon: "arrow_upward", dir: -1 }, { icon: "arrow_downward", dir: 1 }]
                                delegate: RippleButton {
                                    id: mv
                                    required property var modelData
                                    readonly property bool can: mv.modelData.dir < 0 ? src.index > 0
                                                                                     : src.index < win.opt.coverOrder.length - 1
                                    implicitWidth: 28
                                    implicitHeight: 28
                                    buttonRadius: 14
                                    enabled: mv.can
                                    colBackground: "transparent"
                                    colBackgroundHover: Appearance.colors.colLayer1Hover
                                    onClicked: DiscordPresence.moveCover(src.index, mv.modelData.dir)
                                    contentItem: MaterialSymbol {
                                        anchors.centerIn: parent
                                        text: mv.modelData.icon
                                        iconSize: 16
                                        color: Appearance.colors.colOnLayer1
                                        opacity: mv.can ? 1 : 0.25
                                    }
                                }
                            }
                        }
                    }
                }
                StyledText {
                    Layout.fillWidth: true
                    Layout.margins: 10
                    Layout.topMargin: 2
                    text: Translation.tr("The YouTube Music logo is used when none has art.")
                    font.pixelSize: Appearance.font.pixelSize.smallest
                    color: Appearance.colors.colSubtext
                }
            }

            // ── 6. Footer ────────────────────────────────────────────────
            RowLayout {
                Layout.fillWidth: true
                Layout.leftMargin: 4
                Layout.rightMargin: 4
                spacing: 6
                Rectangle {
                    implicitWidth: 6; implicitHeight: 6; radius: 3
                    color: DiscordPresence.scrobblerActive ? Appearance.colors.colPrimary : Appearance.m3colors.m3error
                }
                StyledText {
                    Layout.fillWidth: true
                    text: Translation.tr("Last.fm: %1 · scrobbler %2").arg(DiscordPresence.lastfmUser)
                        .arg(DiscordPresence.scrobblerActive ? Translation.tr("running") : Translation.tr("not running"))
                    elide: Text.ElideRight
                    font.pixelSize: Appearance.font.pixelSize.smallest
                    color: Appearance.colors.colSubtext
                }
                RippleButton {
                    implicitHeight: 24
                    implicitWidth: resetText.implicitWidth + 16
                    buttonRadius: Appearance.rounding.full
                    colBackground: "transparent"
                    colBackgroundHover: Appearance.colors.colLayer1Hover
                    onClicked: DiscordPresence.reset()
                    contentItem: StyledText {
                        id: resetText
                        anchors.centerIn: parent
                        text: Translation.tr("Defaults")
                        font.pixelSize: Appearance.font.pixelSize.smallest
                        color: Appearance.colors.colSubtext
                    }
                }
            }
        }
    }
}
