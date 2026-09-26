pragma ComponentBehavior: Bound
import qs
import qs.services
import qs.modules.ii.audioPlugins
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import Quickshell.Services.Pipewire

/**
 * Audio device panel.
 *
 * The existing audio UI is a flat list of names and one volume slider, which
 * cannot answer the questions that actually come up: which physical output is
 * this, is it running in stereo or has it dropped to mono, is the left channel
 * quieter than the right, and does the right speaker even work.
 *
 * So the top is a speaker-layout preview driven by the device's real channel
 * map, and the controls below are per-channel rather than one master figure.
 *
 * The panel CHROME lives in StackedSettingsPanel and the channel/device logic
 * lives in the AudioLayout service — this file holds only what is specific to
 * audio, so the bar, mixer and OSD can reuse either half.
 */
Scope {
    id: root

    IpcHandler {
        target: "audioSettings"
        function toggle(): void { GlobalStates.audioSettingsOpen = !GlobalStates.audioSettingsOpen }
        function open(): void   { GlobalStates.audioSettingsOpen = true }
        function close(): void  { GlobalStates.audioSettingsOpen = false }
    }

    // Plugin profiles are a sheet OVER this panel, so opening them has to open
    // the panel too - otherwise the flag is set and there is nothing to draw on.
    function showPlugins(on) {
        GlobalStates.audioPluginsOpen = on
        if (on) GlobalStates.audioSettingsOpen = true
    }

    IpcHandler {
        target: "audioPlugins"
        function toggle(): void { root.showPlugins(!GlobalStates.audioPluginsOpen) }
        function open(): void   { root.showPlugins(true) }
        function close(): void  { root.showPlugins(false) }
    }

    GlobalShortcut {
        name: "audioPluginsToggle"
        description: "Toggle audio plugin profiles"
        onPressed: root.showPlugins(!GlobalStates.audioPluginsOpen)
    }

    GlobalShortcut {
        name: "audioSettingsToggle"
        description: "Toggle audio device panel"
        onPressed: GlobalStates.audioSettingsOpen = !GlobalStates.audioSettingsOpen
    }

    // The meter taps the sink monitor through ffmpeg, so it runs only while the
    // panel is open. Declared as a Binding rather than Component.onCompleted on
    // the panel itself: StackedSettingsPanel already uses that hook, and a
    // second declaration on the same object REPLACES it instead of adding to
    // it — which silently dropped its PanelStack.unregister and leaked ffmpeg.
    Binding {
        target: AudioMeter
        property: "active"
        value: GlobalStates.audioSettingsOpen
    }

    StackedPanelLoader {
        isOpen: GlobalStates.audioSettingsOpen

        sourceComponent: StackedSettingsPanel {
            id: win
            panelId: "audio"
            title: Translation.tr("Audio")
            icon: "graphic_eq"
            // Start below the corner popup while it is open, so the two read
            // as a stack rather than one floating over the other. Falls back
            // to flush with the bar the moment it closes.
            topOffset: GlobalStates.cornerPopupOpen
                ? GlobalStates.cornerPopupHeight + Appearance.sizes.hyprlandGapsOut
                : 0
            onRequestClose: GlobalStates.audioSettingsOpen = false

            // Routing is only rendered while this panel exists, so the graph
            // is only watched while it does. Profiles are read here too rather
            // than polled: a card changes profile only when something asks it
            // to. (One hook, not two — a second Component.onCompleted on the
            // same object silently replaces the first.)
            Component.onCompleted: {
                Audio.streamWatchers++
                AudioProfiles.refresh()
            }
            Component.onDestruction: Audio.streamWatchers--

            readonly property PwNode sink: Audio.sink
            readonly property var channels: win.sink?.audio?.channels ?? []
            readonly property var volumes: win.sink?.audio?.volumes ?? []
            readonly property bool muted: win.sink?.audio?.muted ?? false

            function setChannel(i, v) {
                if (win.sink?.audio)
                    win.sink.audio.volumes = AudioLayout.withChannel(win.volumes, i, v);
            }
            function setBalance(b) {
                if (win.sink?.audio)
                    win.sink.audio.volumes = AudioLayout.volumesForBalance(win.volumes, b);
            }

            Process { id: toneProc }
            function testChannel(index) {
                toneProc.exec(AudioLayout.testChannelCommand(win.channels.length, index));
            }

            // Output picker + per-app routing state.
            property bool sinkOpen: false

            // Every row in the sink list reads node.properties to pick its icon
            // and build its subtitle, and those are EMPTY until something
            // tracks the node — Audio.qml deliberately tracks only the current
            // default. That is why one row read "USB • Stereo" and the other
            // seven were an unlabelled generic box: not a styling problem, a
            // data problem. Tracking is scoped to the list actually being open
            // so the graph is only watched while someone is reading it.
            PwObjectTracker {
                objects: win.sinkOpen ? Audio.outputDevices : []
            }

            // Hardware first, then the machine's own outputs, then HDMI, and
            // software sinks last — the order the route sheet below already
            // uses, for the same reason: in plain graph order an equalizer
            // chain and four mostly-unplugged HDMI ports pushed the real
            // speakers, including the one in use, below the fold.
            //
            // Each entry carries the caption that opens its group, so the list
            // stays one Repeater instead of four.
            readonly property var sinkRows: {
                AudioProfiles.revision;   // recompute once profiles land
                // Grouped by how the thing is ATTACHED, not by the icon guess.
                // kindOf() ends in `return "laptop"` as its catch-all, which is
                // a reasonable icon for an unknown box and a bad answer to
                // "where is it" — it filed the USB DJ-808 under This computer.
                // The bus is the fact: pci is soldered in, usb and bluetooth
                // are things you plugged in.
                const rank = (d) => {
                    if (!AudioProfiles.isHardware(d)) return 3;
                    if (AudioLayout.kindOf(d) === "hdmi") return 2;
                    const bus = String(d?.properties?.["device.bus"] ?? "").toLowerCase();
                    return bus === "pci" ? 1 : 0;
                };
                const caption = [
                    Translation.tr("Devices"),
                    Translation.tr("This computer"),
                    Translation.tr("Displays"),
                    Translation.tr("Software"),
                ];
                const sorted = Audio.outputDevices.slice().sort((a, b) => {
                    const r = rank(a) - rank(b);
                    if (r !== 0) return r;
                    return Audio.friendlyDeviceName(a).localeCompare(Audio.friendlyDeviceName(b));
                });
                let last = -1;
                return sorted.map(d => {
                    const r = rank(d);
                    const head = r !== last ? caption[r] : "";
                    last = r;
                    return { dev: d, caption: head };
                });
            }
            property string routeAppOpen: ""   // app node id whose target sheet is open
            // Collapsible section state (Channels / Apps foldouts).
            property bool channelsOpen: false
            property bool appsOpen: false

            Process { id: routeProc }

            // Dismiss FIRST, then route. Starting a chain means waiting for its
            // sink to exist, and this used to close the sheet only once that
            // landed - so picking a stopped chain left the popup sitting open
            // for as long as the host took to come up, with nothing happening.
            // The wait is AudioPlugins' job; it owns the same routing for its
            // own card, and one implementation is enough.
            function startAndRoute(appNode, profile) {
                win.routeAppOpen = ""
                AudioPlugins.routeInto(appNode, profile)
            }
            // Pin an app's stream to a specific sink (or clear → automatic).
            // WirePlumber honours target.object = the sink's object.serial.
            function routeApp(appNode, sinkNode) {
                if (!appNode) return;
                const id = String(appNode.id);
                if (sinkNode) {
                    const target = sinkNode.properties?.["object.serial"] ?? sinkNode.name;
                    routeProc.exec(["pw-metadata", id, "target.object", String(target)]);
                } else {
                    routeProc.exec(["pw-metadata", "-d", id, "target.object"]);
                }
                win.routeAppOpen = "";
            }

            // ── Preview ─────────────────────────────────────────────────
            // Two visuals, chosen by what the device actually is. A top-down
            // room with speakers placed around a listener is the right picture
            // for speakers and surround, and the wrong one for headphones —
            // those are not in a room, they are on your head, and there are
            // only ever two of them. Drawing a headset as two dots in a room
            // told you nothing about which cup was which.

            // ── Output ──────────────────────────────────────────────────
            // Current sink; click to drop down and switch. Every entry carries
            // its own icon so you can see at a glance where sound will go.
            // No "Output" caption above it: the row carries the device's own
            // icon, its name and its layout, which is more than the word did,
            // and the caption cost a full row to repeat it.
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 3

                // The selected sink AND the master volume. They are the two
                // things you open this panel for and they were the two furthest
                // apart in it; together at the top, both are answered first.
                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: 46 + volumeStrip.height
                    radius: Appearance.rounding.small
                    color: sinkHdrHov.hovered ? Appearance.colors.colLayer1Hover
                                              : Appearance.colors.colLayer1
                    Behavior on color {
                        animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
                    }
                    HoverHandler { id: sinkHdrHov; cursorShape: Qt.PointingHandCursor }
                    TapHandler { onTapped: win.sinkOpen = !win.sinkOpen }
                    RowLayout {
                        anchors { left: parent.left; right: parent.right; top: parent.top }
                        height: 46
                        anchors.leftMargin: 10; anchors.rightMargin: 10
                        spacing: 10
                        CustomIcon {
                            width: 20; height: 20; colorize: true
                            source: AudioLayout.iconFor(Audio.sink)
                            visible: source.length > 0
                            color: Appearance.colors.colOnLayer0
                        }
                        MaterialSymbol {
                            visible: AudioLayout.iconFor(Audio.sink).length === 0
                            text: AudioLayout.materialSymbolFor(Audio.sink)
                            iconSize: 20
                            color: Appearance.colors.colOnLayer0
                        }
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 0
                            StyledText {
                                Layout.fillWidth: true
                                text: Audio.friendlyDeviceName(Audio.sink)
                                elide: Text.ElideRight
                                font.pixelSize: Appearance.font.pixelSize.smaller
                                color: Appearance.colors.colOnLayer0
                            }
                            StyledText {
                                Layout.fillWidth: true
                                text: {
                                    const bits = [];
                                    const t = AudioLayout.transportOf(Audio.sink);
                                    if (t.length > 0) bits.push(t);
                                    const lay = AudioLayout.layoutName(Audio.sink?.audio?.channels ?? []);
                                    if (lay !== "—") bits.push(lay);
                                    return bits.join("  •  ");
                                }
                                elide: Text.ElideRight
                                font.pixelSize: Appearance.font.pixelSize.smallest
                                color: Appearance.colors.colSubtext
                            }
                        }
                        MaterialSymbol {
                            text: "expand_more"; iconSize: 20
                            color: Appearance.colors.colSubtext
                            rotation: win.sinkOpen ? 180 : 0
                            Behavior on rotation {
                                animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                            }
                        }
                    }

                    // Master volume, under the device it belongs to.
                    RowLayout {
                        id: volumeStrip
                        anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
                        anchors.leftMargin: 10; anchors.rightMargin: 12
                        height: 40
                        spacing: 8

                        RippleButton {
                            implicitWidth: 28; implicitHeight: 28
                            buttonRadius: 14
                            onClicked: Audio.toggleMute()
                            contentItem: MaterialSymbol {
                                anchors.centerIn: parent
                                text: win.muted ? "volume_off" : "volume_up"
                                iconSize: 17
                                color: win.muted ? Appearance.m3colors.m3error
                                                 : Appearance.colors.colOnLayer0
                            }
                            StyledToolTip {
                                text: win.muted ? Translation.tr("Unmute") : Translation.tr("Mute")
                            }
                        }

                        StyledSlider {
                            Layout.fillWidth: true
                            enabled: !win.muted
                            opacity: win.muted ? 0.4 : 1.0
                            from: 0; to: 1
                            value: Audio.sink?.audio?.volume ?? 0
                            onMoved: if (Audio.sink?.audio) Audio.sink.audio.volume = value
                        }

                        StyledText {
                            Layout.minimumWidth: 38
                            horizontalAlignment: Text.AlignRight
                            text: win.muted ? Translation.tr("Muted")
                                            : Math.round((Audio.sink?.audio?.volume ?? 0) * 100) + "%"
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            font.family: Appearance.font.family.monospace
                            color: win.muted ? Appearance.m3colors.m3error
                                             : Appearance.colors.colOnLayer0
                        }
                    }

                }
                // Expanding sink list.
                Item {
                    Layout.fillWidth: true
                    clip: true
                    implicitHeight: win.sinkOpen ? sinkList.implicitHeight : 0
                                        ColumnLayout {
                        id: sinkList
                        // Slides into the space rather than growing it - see the note
                        // on the parent's height.
                        y: win.sinkOpen ? 0 : -sinkList.implicitHeight
                        opacity: win.sinkOpen ? 1 : 0
                        Behavior on y {
                            animation: Appearance.animation.elementMove.numberAnimation.createObject(this)
                        }
                        Behavior on opacity {
                            animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                        }
                        width: parent.width
                        spacing: 3
                        Repeater {
                            model: win.sinkRows
                            delegate: ColumnLayout {
                                id: devRow
                                required property var modelData
                                readonly property var dev: modelData.dev
                                Layout.fillWidth: true
                                spacing: 3

                                // Which picture is actually TRUE for this row.
                                //
                                // AudioLayout.iconFor() cannot answer this on
                                // its own: kindOf() ends in `return "laptop"`
                                // as a catch-all, so an equalizer chain, a
                                // DAW's output and a USB DJ controller all came
                                // back as this machine's own audio and were
                                // drawn with the tablet glyph. A wrong picture
                                // is worse than a generic one, so the two cases
                                // that catch-all swallows are taken back here.
                                readonly property bool virtualSink: {
                                    AudioProfiles.revision;
                                    return AudioProfiles.loaded
                                        && !AudioProfiles.isHardware(devRow.dev);
                                }
                                readonly property bool internalSink:
                                    String(devRow.dev?.properties?.["device.bus"] ?? "").toLowerCase() === "pci"
                                readonly property string artSource: {
                                    if (devRow.virtualSink) return "";
                                    const s = AudioLayout.iconFor(devRow.dev);
                                    // The chassis art is only honest about the
                                    // machine's own soldered-in audio.
                                    if ((s === "tablet-audio-symbolic.svg"
                                      || s === "laptop-audio-symbolic.svg") && !devRow.internalSink)
                                        return "";
                                    return s;
                                }

                                // Opens a group. Captions cost one line and
                                // save the reader from having to know that
                                // "Equalizer" is not a box on the desk.
                                StyledText {
                                    visible: devRow.modelData.caption.length > 0
                                    Layout.leftMargin: 4
                                    Layout.topMargin: 4
                                    text: devRow.modelData.caption
                                    font.pixelSize: Appearance.font.pixelSize.smallest
                                    font.letterSpacing: 0.6
                                    color: Appearance.colors.colSubtext
                                }

                            Rectangle {
                                id: dev
                                readonly property var modelData: devRow.dev
                                readonly property bool isDefault: modelData === Audio.sink
                                Layout.fillWidth: true
                                implicitHeight: 40
                                radius: Appearance.rounding.small
                                color: isDefault ? Appearance.colors.colPrimaryContainer
                                                 : (devHov.hovered ? Appearance.colors.colLayer1Hover
                                                                   : Appearance.colors.colLayer1)
                                Behavior on color {
                                    animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
                                }
                                HoverHandler { id: devHov; cursorShape: Qt.PointingHandCursor }
                                TapHandler { onTapped: { Audio.setDefaultSink(dev.modelData); win.sinkOpen = false; } }
                                RowLayout {
                                    anchors.fill: parent
                                    anchors.leftMargin: 10; anchors.rightMargin: 10
                                    spacing: 10
                                    CustomIcon {
                                        width: 18; height: 18; colorize: true
                                        source: devRow.artSource
                                        visible: source.length > 0
                                        color: dev.isDefault ? Appearance.colors.colOnPrimaryContainer
                                                             : Appearance.colors.colOnLayer0
                                    }
                                    MaterialSymbol {
                                        visible: devRow.artSource.length === 0
                                        text: devRow.virtualSink
                                            ? "graphic_eq"
                                            : AudioLayout.materialSymbolFor(dev.modelData)
                                        iconSize: 18
                                        color: dev.isDefault ? Appearance.colors.colOnPrimaryContainer
                                                             : Appearance.colors.colOnLayer0
                                    }
                                    ColumnLayout {
                                        Layout.fillWidth: true
                                        spacing: 0
                                        StyledText {
                                            Layout.fillWidth: true
                                            text: Audio.friendlyDeviceName(dev.modelData)
                                            elide: Text.ElideRight
                                            font.pixelSize: Appearance.font.pixelSize.smaller
                                            color: dev.isDefault ? Appearance.colors.colOnPrimaryContainer
                                                                 : Appearance.colors.colOnLayer0
                                        }
                                        StyledText {
                                            Layout.fillWidth: true
                                            visible: text.length > 0
                                            text: {
                                                const bits = [];
                                                const t = AudioLayout.transportOf(dev.modelData);
                                                if (t.length > 0) bits.push(t);
                                                const lay = AudioLayout.layoutName(dev.modelData?.audio?.channels ?? []);
                                                if (lay !== "—") bits.push(lay);
                                                // A headset whose card is in a
                                                // mic-carrying profile is the
                                                // one that sounds worse, so say
                                                // so on the row rather than
                                                // making it a buried setting.
                                                AudioProfiles.revision;
                                                if (AudioProfiles.micEnabled(dev.modelData))
                                                    bits.push(Translation.tr("Mic on"));
                                                // Nothing known is nothing said.
                                                // These come up empty when the
                                                // node has no tracker on it, so
                                                // "Virtual device" was being
                                                // asserted about real hardware -
                                                // HDMI and the analog codec both
                                                // read as virtual.
                                                return bits.join("  •  ");
                                            }
                                            elide: Text.ElideRight
                                            font.pixelSize: Appearance.font.pixelSize.smallest
                                            color: dev.isDefault
                                                ? Qt.alpha(Appearance.colors.colOnPrimaryContainer, 0.75)
                                                : Appearance.colors.colSubtext
                                        }
                                    }
                                    MaterialSymbol {
                                        visible: dev.isDefault
                                        text: "check"; iconSize: 16
                                        color: Appearance.colors.colOnPrimaryContainer
                                    }
                                }
                            }
                            }
                        }
                    }
                }
            }

            // ── Headset microphone ──────────────────────────────────────
            // Only appears for a card that has both a with-mic and a
            // without-mic profile, which is the only case where the choice
            // exists at all.
            //
            // This is NOT a mute. Muting leaves the capture endpoint in the
            // graph: applications still open it, still show the device in
            // their picker, and the card still runs in its headset mode. This
            // removes the endpoint, so nothing can record from it — and on
            // hardware where the two are mutually exclusive in firmware, that
            // is also what lets playback use the good mode.
            Rectangle {
                id: micCard
                readonly property var pair: {
                    AudioProfiles.revision;
                    return AudioProfiles.micPairFor(Audio.sink);
                }
                visible: micCard.pair !== null
                Layout.fillWidth: true
                implicitHeight: visible ? micCol.implicitHeight + 24 : 0
                radius: Appearance.rounding.normal
                color: Appearance.colors.colLayer1

                ColumnLayout {
                    id: micCol
                    anchors { left: parent.left; right: parent.right; top: parent.top; margins: 12 }
                    spacing: 8

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 10
                        MaterialSymbol {
                            text: micCard.pair?.enabled ? "mic" : "mic_off"
                            iconSize: 17
                            color: micCard.pair?.enabled ? Appearance.colors.colPrimary
                                                         : Appearance.colors.colSubtext
                        }
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 0
                            StyledText {
                                Layout.fillWidth: true
                                elide: Text.ElideRight
                                text: Translation.tr("Microphone on %1").arg(micCard.pair?.deviceName ?? "")
                                font.pixelSize: Appearance.font.pixelSize.smaller
                                font.weight: Font.Medium
                                color: Appearance.colors.colOnLayer1
                            }
                            StyledText {
                                Layout.fillWidth: true
                                wrapMode: Text.WordWrap
                                // Deliberately not "headset": this card appears
                                // for anything with a mic-carrying profile,
                                // and it rendered over a DJ controller.
                                text: micCard.pair?.enabled
                                    ? Translation.tr("Apps can record from this device. Some headsets drop to a lower-quality playback mode while their mic is on.")
                                    : Translation.tr("No app can record from this device, and playback keeps full quality.")
                                font.pixelSize: Appearance.font.pixelSize.smallest
                                color: Appearance.colors.colSubtext
                            }
                        }
                        StyledSwitch {
                            checked: micCard.pair?.enabled ?? false
                            onToggled: AudioProfiles.setMicEnabled(Audio.sink, checked)
                        }
                    }
                }
            }

            // ── Loudness ────────────────────────────────────────────────
            // Measured from the sink monitor, not derived from the volume
            // setting: those are different things, and only one of them tells
            // you how loud the output actually is.
            Rectangle {
                Layout.fillWidth: true
                implicitHeight: meterCol.implicitHeight + 20
                radius: Appearance.rounding.normal
                color: Appearance.colors.colLayer1
                border.width: 1
                border.color: Appearance.colors.colLayer0Border

                ColumnLayout {
                    id: meterCol
                    anchors.centerIn: parent
                    width: parent.width - 20
                    spacing: 6

                    RowLayout {
                        Layout.fillWidth: true
                        StyledText {
                            text: Translation.tr("Loudness")
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            color: Appearance.colors.colSubtext
                        }
                        Item { Layout.fillWidth: true }
                        StyledText {
                            text: !AudioMeter.measuring ? Translation.tr("Not measuring")
                                : AudioMeter.silent ? Translation.tr("Silent")
                                : AudioMeter.momentaryLufs.toFixed(1) + " LUFS"
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            font.family: Appearance.font.family.monospace
                            font.bold: true
                            color: Appearance.colors.colOnLayer0
                        }
                    }

                    // Momentary loudness as a bar. The marker sits at -14 LUFS,
                    // the streaming reference, so "louder or quieter than most
                    // things you play" is readable at a glance.
                    // Drawn the way StyledSlider draws a track. It was an 8px
                    // plain bar: a progress bar from another toolkit, under a
                    // panel full of sliders, with nowhere for the dot to sit.
                    Item {
                        id: loudTrack
                        Layout.fillWidth: true
                        implicitHeight: 22

                        readonly property real trackHeight: 14
                        readonly property real notch: 6
                        readonly property real fill:
                            Math.max(0, Math.min(1, AudioMeter.normalized(AudioMeter.momentaryLufs)))
                        readonly property real fillX: loudTrack.width * loudTrack.fill
                        readonly property color hot: AudioMeter.momentaryLufs > -6
                            ? Appearance.m3colors.m3error : Appearance.colors.colPrimary

                        // Active segment.
                        Rectangle {
                            anchors.verticalCenter: parent.verticalCenter
                            height: loudTrack.trackHeight
                            width: Math.max(0, loudTrack.fillX - loudTrack.notch / 2)
                            radius: Appearance.rounding.full
                            color: loudTrack.hot
                            Behavior on width { NumberAnimation { duration: 90 } }
                            Behavior on color { ColorAnimation { duration: 120 } }
                        }

                        // Remainder.
                        Rectangle {
                            anchors.verticalCenter: parent.verticalCenter
                            height: loudTrack.trackHeight
                            x: Math.min(parent.width, loudTrack.fillX + loudTrack.notch / 2)
                            width: Math.max(0, parent.width - x)
                            radius: Appearance.rounding.full
                            color: Appearance.colors.colSecondaryContainer
                            Behavior on x { NumberAnimation { duration: 90 } }

                            // StyledSlider's end dot.
                            Rectangle {
                                visible: parent.width > 14
                                anchors.verticalCenter: parent.verticalCenter
                                anchors.right: parent.right
                                anchors.rightMargin: 5
                                width: 4; height: 4
                                radius: Appearance.rounding.full
                                color: Appearance.m3colors.m3onSecondaryContainer
                            }
                        }

                        // The handle, in the notch.
                        Rectangle {
                            anchors.verticalCenter: parent.verticalCenter
                            x: loudTrack.fillX - width / 2
                            width: 3
                            height: loudTrack.trackHeight + 6
                            radius: Appearance.rounding.full
                            color: loudTrack.hot
                            Behavior on x { NumberAnimation { duration: 90 } }
                            Behavior on color { ColorAnimation { duration: 120 } }
                        }

                        // -14 LUFS, the streaming reference, so "louder or
                        // quieter than most things you play" is readable at a
                        // glance.
                        Rectangle {
                            anchors.verticalCenter: parent.verticalCenter
                            x: parent.width * AudioMeter.normalized(-14) - width / 2
                            width: 2
                            height: loudTrack.trackHeight - 4
                            radius: 1
                            color: Appearance.colors.colSubtext
                            opacity: 0.65
                        }

                        // Peak-hold dot, now sitting ON the track rather than
                        // floating over a flat bar. It snaps up instantly and
                        // only the fall-back is animated - easing the rise
                        // would hide the very transient it exists to catch.
                        Rectangle {
                            id: peakDot
                            visible: !AudioMeter.silent && AudioMeter.measuring
                            width: 10; height: 10
                            radius: Appearance.rounding.full
                            anchors.verticalCenter: parent.verticalCenter
                            x: parent.width * AudioMeter.normalized(AudioMeter.peakHoldLufs)
                               - width / 2
                            color: AudioMeter.peakHoldLufs > -6
                                   ? Appearance.m3colors.m3error
                                   : Appearance.colors.colPrimary
                            border.width: 2
                            border.color: Appearance.colors.colLayer1
                            Behavior on x {
                                enabled: !AudioMeter.rising
                                NumberAnimation { duration: 120; easing.type: Easing.OutCubic }
                            }
                            Behavior on color { ColorAnimation { duration: 120 } }

                            StyledToolTip {
                                extraVisibleCondition: false
                                alternativeVisibleCondition: peakHoldHov.hovered
                                text: Translation.tr("Peak") + ": "
                                      + AudioMeter.peakHoldLufs.toFixed(1) + " LUFS"
                            }
                            HoverHandler { id: peakHoldHov }
                        }
                    }

                    // Label over value on one line, not two rows of
                    // "Label: value": half the height, and the numbers line up
                    // in columns instead of reading as prose.
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 8

                        component Stat: ColumnLayout {
                            property string label: ""
                            property string value: "—"
                            property color tint: Appearance.colors.colOnLayer1
                            Layout.fillWidth: true
                            spacing: 0
                            StyledText {
                                Layout.fillWidth: true
                                text: label
                                font.pixelSize: Appearance.font.pixelSize.smallest
                                color: Appearance.colors.colSubtext
                            }
                            StyledText {
                                Layout.fillWidth: true
                                text: value
                                font.pixelSize: Appearance.font.pixelSize.smaller
                                font.family: Appearance.font.family.monospace
                                color: tint
                            }
                        }

                        Stat {
                            label: Translation.tr("Short")
                            value: AudioMeter.silent || AudioMeter.shortTermLufs <= -60
                                   ? "—" : AudioMeter.shortTermLufs.toFixed(1)
                        }
                        Stat {
                            label: Translation.tr("Integrated")
                            value: AudioMeter.silent || AudioMeter.integratedLufs <= -60
                                   ? "—" : AudioMeter.integratedLufs.toFixed(1)
                        }
                        Stat {
                            label: Translation.tr("Range")
                            value: AudioMeter.loudnessRange.toFixed(1) + " LU"
                        }
                        Stat {
                            // Clipping is a separate question from loudness:
                            // quiet material can still peak over 0 dBFS.
                            readonly property real tp: AudioMeter.channelTruePeaks.length > 0
                                ? Math.max(...AudioMeter.channelTruePeaks) : -70
                            label: Translation.tr("True peak")
                            value: tp <= -60 ? "—" : tp.toFixed(1)
                            tint: tp > -0.5 ? Appearance.m3colors.m3error
                                            : Appearance.colors.colOnLayer1
                        }
                    }
                }
            }

            // ── Recording ───────────────────────────────────────────────
            // Records the same monitor the meter measures, so the file is the
            // mix as heard. The service is a singleton and the keybind lives
            // in Shortcuts.qml, so this panel only ever reflects state - it is
            // never the thing keeping a recording alive.
            // One 46px row like the rest. It was a bordered card twice that
            // tall for a toggle and a filename.
            Rectangle {
                Layout.fillWidth: true
                implicitHeight: 46
                radius: Appearance.rounding.small
                color: recHov.hovered ? Appearance.colors.colLayer1Hover
                                      : Appearance.colors.colLayer1
                Behavior on color {
                    animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
                }
                HoverHandler { id: recHov; cursorShape: Qt.PointingHandCursor }
                TapHandler { onTapped: AudioRecorder.toggle() }

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 10
                    anchors.rightMargin: 12
                    spacing: 10

                    Rectangle {
                        implicitWidth: 26
                        implicitHeight: 26
                        radius: Appearance.rounding.full
                        color: AudioRecorder.recording ? Appearance.m3colors.m3error
                                                       : Appearance.colors.colLayer2
                        Behavior on color { ColorAnimation { duration: 140 } }
                        MaterialSymbol {
                            anchors.centerIn: parent
                            text: AudioRecorder.recording ? "stop" : "fiber_manual_record"
                            iconSize: 16
                            color: AudioRecorder.recording ? Appearance.m3colors.m3onError
                                                           : Appearance.colors.colOnLayer2
                        }
                    }

                    StyledText {
                        text: AudioRecorder.recording ? Translation.tr("Recording")
                                                      : Translation.tr("Record output")
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        color: Appearance.colors.colOnLayer0
                    }

                    // The filename only matters once there is one; before that
                    // the row says what it does and nothing more.
                    StyledText {
                        Layout.fillWidth: true
                        elide: Text.ElideMiddle
                        text: {
                            if (AudioRecorder.lastError.length > 0) return AudioRecorder.lastError
                            if (AudioRecorder.outputPath.length > 0)
                                return AudioRecorder.outputPath.split("/").pop()
                            return ""
                        }
                        font.pixelSize: Appearance.font.pixelSize.smallest
                        color: AudioRecorder.lastError.length > 0 ? Appearance.m3colors.m3error
                                                                  : Appearance.colors.colSubtext
                    }

                    // Monospace so the digits do not jitter each second.
                    StyledText {
                        visible: AudioRecorder.recording
                        text: AudioRecorder.formatElapsed()
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        font.family: Appearance.font.family.monospace
                        color: Appearance.m3colors.m3error
                    }

                    StyledToolTip {
                        text: AudioRecorder.recording ? Translation.tr("Stop recording")
                                                      : Translation.tr("Record output (Ctrl+Super+A)")
                    }
                }
            }

            // ── Per-channel (collapsible) ───────────────────────────────
            CollapsibleHeader {
                title: Translation.tr("Channels")
                value: {
                    const lay = AudioLayout.layoutName(win.channels)
                    return lay === "—" ? "" : lay
                }
                icon: "graphic_eq"
                expanded: win.channelsOpen
                onToggled: win.channelsOpen = !win.channelsOpen
            }
            Item {   // collapsible channels body
                Layout.fillWidth: true
                clip: true
                // A zero-height child still collects 14px of spacing above and
                // below; hidden, the layout skips it.
                visible: implicitHeight > 0
                // Height is NOT tweened, and that is the whole point. This Item
                // feeds col -> card -> the PanelWindow's implicitHeight, so an
                // animated height reconfigures the layer-shell surface on every
                // frame of the tween and reallocates its buffer with it. The card
                // already refuses to animate its own height for exactly this
                // reason; animating a section's height put the cost straight back.
                //
                // So the space appears at once and the CONTENT slides into it.
                // One surface resize per toggle, and the motion is pure
                // compositing inside a surface that is not changing size.
                implicitHeight: win.channelsOpen ? chBody.implicitHeight : 0
                                ColumnLayout {
                    id: chBody
                    // Slides into the space rather than growing it - see the note
                    // on the parent's height.
                    y: win.channelsOpen ? 0 : -chBody.implicitHeight
                    opacity: win.channelsOpen ? 1 : 0
                    Behavior on y {
                        animation: Appearance.animation.elementMove.numberAnimation.createObject(this)
                    }
                    Behavior on opacity {
                        animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                    }
                    width: parent.width
                    spacing: 4
            // A channel's volume and its live level, together. They were two
            // blocks - meters under the device card, sliders in here - so
            // setting a channel meant watching one place and dragging in
            // another.
            Repeater {
                model: win.channels
                delegate: RowLayout {
                    id: chRow
                    required property var modelData
                    required property int index
                    readonly property real lvl: AudioMeter.silent
                        ? 0 : AudioMeter.peakNormalized(chRow.index)
                    readonly property real hold: AudioMeter.silent
                        ? -1 : AudioMeter.channelPeakHoldNormalized(chRow.index)
                    readonly property real db: chRow.index < AudioMeter.channelPeaks.length
                        ? AudioMeter.channelPeaks[chRow.index] : -70
                    Layout.fillWidth: true
                    spacing: 8

                    // Tap the label for a test tone through this channel.
                    StyledText {
                        Layout.minimumWidth: 30
                        text: AudioLayout.labelFor(chRow.modelData)
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        font.family: Appearance.font.family.monospace
                        color: labelHov.hovered ? Appearance.colors.colPrimary
                                                : Appearance.colors.colOnLayer0
                        HoverHandler { id: labelHov; cursorShape: Qt.PointingHandCursor }
                        TapHandler { onTapped: win.testChannel(chRow.index) }
                        StyledToolTip { text: Translation.tr("Play a test tone on this channel") }
                    }

                    // The live level runs inside the volume slider's own track:
                    // where you set the level and what is coming out, in one
                    // control.
                    StyledSlider {
                        Layout.fillWidth: true
                        from: 0; to: 1
                        value: win.volumes[chRow.index] ?? 0
                        onMoved: win.setChannel(chRow.index, value)
                        level: chRow.lvl
                        peakHold: chRow.hold
                        levelHot: chRow.db > -1
                    }

                    // Volume over live dB.
                    ColumnLayout {
                        Layout.minimumWidth: 46
                        spacing: 0
                        StyledText {
                            Layout.alignment: Qt.AlignRight
                            text: Math.round((win.volumes[chRow.index] ?? 0) * 100) + "%"
                            font.pixelSize: Appearance.font.pixelSize.smallest
                            font.family: Appearance.font.family.monospace
                            color: Appearance.colors.colOnLayer0
                        }
                        StyledText {
                            Layout.alignment: Qt.AlignRight
                            text: AudioMeter.silent || chRow.db <= -60
                                  ? "—" : Math.round(chRow.db) + " dB"
                            font.pixelSize: Appearance.font.pixelSize.smallest
                            font.family: Appearance.font.family.monospace
                            color: chRow.db > -1 ? Appearance.m3colors.m3error
                                                 : Appearance.colors.colSubtext
                        }
                    }
                }
            }

            // Balance is only a meaningful control for exactly two channels.
            ColumnLayout {
                Layout.fillWidth: true
                Layout.topMargin: 8
                visible: AudioLayout.isStereo(win.channels)
                spacing: 2
                RowLayout {
                    Layout.fillWidth: true
                    StyledText {
                        text: Translation.tr("Balance")
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        color: Appearance.colors.colSubtext
                    }
                    Item { Layout.fillWidth: true }
                    StyledText {
                        readonly property real b: AudioLayout.balanceOf(win.volumes)
                        text: Math.abs(b) < 0.02 ? Translation.tr("Centered")
                            : (b < 0 ? "L " : "R ") + Math.round(Math.abs(b) * 100) + "%"
                        font.pixelSize: Appearance.font.pixelSize.smallest
                        color: Appearance.colors.colSubtext
                    }
                }
                StyledSlider {
                    Layout.fillWidth: true
                    from: -1; to: 1
                    value: AudioLayout.balanceOf(win.volumes)
                    onMoved: win.setBalance(value)
                }
            }
                }   // chBody
            }       // collapsible channels body

            // ── Apps (collapsible) ─────────────────────────────────────
            // Every OPEN app, silent ones included, from the same AppVolumes
            // rows and the same row widget as the corner popup. It used to list
            // only apps with a live stream, rebuilt from Audio.outputAppNodes on
            // every PipeWire node change; the shared rows are only replaced when
            // the set of apps actually changes.
            CollapsibleHeader {
                Layout.topMargin: 4
                visible: AppVolumes.rows.length > 0
                title: Translation.tr("Apps")
                value: {
                    const live = AppVolumes.rows.filter(r => r.live).length
                    return Translation.tr("%1 playing · %2 open").arg(live).arg(AppVolumes.rows.length)
                }
                icon: "apps"
                expanded: win.appsOpen
                onToggled: win.appsOpen = !win.appsOpen
            }
            Item {   // collapsible apps body
                Layout.fillWidth: true
                clip: true
                // A zero-height child still collects spacing; hidden, it is skipped.
                visible: AppVolumes.rows.length > 0 && implicitHeight > 0
                implicitHeight: win.appsOpen ? appBody.implicitHeight : 0
                ColumnLayout {
                    id: appBody
                    y: win.appsOpen ? 0 : -appBody.implicitHeight
                    opacity: win.appsOpen ? 1 : 0
                    Behavior on y {
                        animation: Appearance.animation.elementMove.numberAnimation.createObject(this)
                    }
                    Behavior on opacity {
                        animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                    }
                    width: parent.width
                    spacing: 2
                    Repeater {
                        model: AppVolumes.rows
                        delegate: AppAudioRow {
                            required property var modelData
                            Layout.fillWidth: true
                            row: modelData
                            showRouting: true
                            onRouteRequested: win.routeAppOpen = String(modelData.node?.id ?? "")
                        }
                    }
                }
            }       // collapsible apps body

            // -- Plugins ------------------------------------------------------
            // A row, not a section. Building a chain means browsing a hundred
            // plugins, which does not fit in a panel this narrow - so it opens
            // as its own sheet, the same way the device and network lists do.
            Rectangle {
                Layout.fillWidth: true
                Layout.topMargin: 4
                implicitHeight: 34
                radius: Appearance.rounding.small
                color: pluginRowHov.hovered ? Appearance.colors.colLayer1Hover
                                            : Appearance.colors.colLayer1
                Behavior on color {
                    animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
                }
                HoverHandler { id: pluginRowHov; cursorShape: Qt.PointingHandCursor }
                TapHandler { onTapped: root.showPlugins(true) }
                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 10; anchors.rightMargin: 8
                    spacing: 8
                    MaterialSymbol {
                        text: "graphic_eq"; iconSize: 17
                        color: Appearance.colors.colPrimary
                    }
                    StyledText {
                        Layout.fillWidth: true
                        text: Translation.tr("Plugin profiles")
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        color: Appearance.colors.colOnLayer1
                    }
                    StyledText {
                        text: AudioPlugins.profiles.length > 0
                            ? Translation.tr("%1").arg(AudioPlugins.profiles.length)
                            : ""
                        font.pixelSize: Appearance.font.pixelSize.smallest
                        color: Appearance.colors.colSubtext
                    }
                    MaterialSymbol {
                        text: "chevron_right"; iconSize: 18
                        color: Appearance.colors.colSubtext
                    }
                }
            }

            // ── Route picker ───────────────────────────────────────────
            // A sheet, not an inline foldout: expanding the target list pushed
            // eight outputs into the middle of the panel and scrolled the app
            // you were routing out of sight.
            PanelSheet {
                id: routeSheet
                readonly property var appNode:
                    Audio.outputAppNodes.find(n => String(n?.id) === win.routeAppOpen) ?? null
                readonly property string currentSink:
                    routeSheet.appNode ? Audio.sinkForStream(routeSheet.appNode.id) : ""

                // The name outlives the selection: appNode goes null the instant
                // the sheet is dismissed, and the heading blanked mid-fade.
                property string heldName: ""
                property string heldSink: ""
                onOpenChanged: if (open) {
                    heldName = Audio.appNodeDisplayName(routeSheet.appNode)
                    heldSink = routeSheet.currentSink
                }

                // Where it is going now, first; then real devices; the laptop's
                // own outputs; HDMI last. A machine with a dock lists four HDMI
                // ports that are mostly unplugged, and in plain graph order they
                // pushed the actual speakers - including the one in use - below
                // the fold.
                function rankOf(d) {
                    const k = AudioLayout.kindOf(d)
                    return k === "hdmi" ? 2 : (k === "laptop" ? 1 : 0)
                }
                readonly property var outputs: {
                    const cur = routeSheet.currentSink
                    return Audio.outputDevices
                        .filter(d => !AudioPlugins.isProfileSink(d?.name))
                        .slice()
                        .sort((a, b) => {
                            const ca = (a?.description ?? "") === cur ? 0 : 1
                            const cb = (b?.description ?? "") === cur ? 0 : 1
                            if (ca !== cb) return ca - cb
                            const r = routeSheet.rankOf(a) - routeSheet.rankOf(b)
                            if (r !== 0) return r
                            return Audio.friendlyDeviceName(a).localeCompare(Audio.friendlyDeviceName(b))
                        })
                }
                readonly property string defaultName: Audio.friendlyDeviceName(Audio.sink)

                open: win.routeAppOpen !== "" && routeSheet.appNode !== null
                title: Translation.tr("Send %1 to").arg(routeSheet.heldName)
                // Live while open (the routing read can land after opening),
                // held while fading out.
                readonly property string shownSink: routeSheet.open && routeSheet.currentSink.length > 0
                    ? routeSheet.currentSink : routeSheet.heldSink
                subtitle: routeSheet.shownSink.length > 0
                    ? Translation.tr("Playing on %1").arg(routeSheet.shownSink) : ""
                onClosed: win.routeAppOpen = ""

                // One row in a grouped list.
                component Option: Rectangle {
                    id: opt
                    property string label: ""
                    property string sublabel: ""
                    property string symbol: ""
                    property string customIcon: ""
                    property bool chosen: false
                    property bool divider: true
                    signal picked()
                    Layout.fillWidth: true
                    implicitHeight: sublabel.length > 0 ? 46 : 40
                    radius: Appearance.rounding.verysmall
                    color: chosen ? Appearance.colors.colPrimaryContainer
                         : (optHov.hovered ? Appearance.colors.colLayer2Hover : "transparent")
                    Behavior on color {
                        animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
                    }
                    HoverHandler { id: optHov; cursorShape: Qt.PointingHandCursor }
                    TapHandler { onTapped: opt.picked() }

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 10; anchors.rightMargin: 10
                        spacing: 10
                        CustomIcon {
                            visible: opt.customIcon.length > 0
                            width: 18; height: 18; colorize: true
                            source: opt.customIcon
                            color: opt.chosen ? Appearance.colors.colOnPrimaryContainer
                                              : Appearance.colors.colOnLayer1
                        }
                        MaterialSymbol {
                            visible: opt.customIcon.length === 0
                            text: opt.symbol; iconSize: 18
                            color: opt.chosen ? Appearance.colors.colOnPrimaryContainer
                                              : Appearance.colors.colOnLayer1
                        }
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 0
                            StyledText {
                                Layout.fillWidth: true
                                elide: Text.ElideRight
                                text: opt.label
                                font.pixelSize: Appearance.font.pixelSize.smaller
                                font.weight: opt.chosen ? Font.Medium : Font.Normal
                                color: opt.chosen ? Appearance.colors.colOnPrimaryContainer
                                                  : Appearance.colors.colOnLayer1
                            }
                            StyledText {
                                Layout.fillWidth: true
                                visible: opt.sublabel.length > 0
                                elide: Text.ElideRight
                                text: opt.sublabel
                                font.pixelSize: Appearance.font.pixelSize.smallest
                                color: opt.chosen ? Appearance.colors.colOnPrimaryContainer
                                                  : Appearance.colors.colSubtext
                            }
                        }
                        MaterialSymbol {
                            visible: opt.chosen
                            text: "check"; iconSize: 16
                            color: Appearance.colors.colOnPrimaryContainer
                        }
                    }
                }

                // A captioned group: one surface, rows inside it. Separate pills
                // for every output made a column of eight near-identical cards
                // that read as noise before it read as a list.
                component Group: ColumnLayout {
                    id: grp
                    property string caption: ""
                    default property alias rows: grpRows.data
                    Layout.fillWidth: true
                    spacing: 4
                    StyledText {
                        visible: grp.caption.length > 0
                        Layout.leftMargin: 4
                        text: grp.caption
                        font.pixelSize: Appearance.font.pixelSize.smallest
                        font.letterSpacing: 0.6
                        color: Appearance.colors.colSubtext
                    }
                    Rectangle {
                        Layout.fillWidth: true
                        implicitHeight: grpRows.implicitHeight + 8
                        radius: Appearance.rounding.normal
                        color: Appearance.colors.colLayer1
                        ColumnLayout {
                            id: grpRows
                            anchors { left: parent.left; right: parent.right; top: parent.top; margins: 4 }
                            spacing: 2
                        }
                    }
                }

                StyledFlickable {
                    id: optionFlick
                    Layout.fillWidth: true
                    Layout.preferredHeight: Math.min(optionCol.implicitHeight, 400)
                    contentHeight: optionCol.implicitHeight
                    clip: true

                    ColumnLayout {
                        id: optionCol
                        // optionFlick.width, not parent.width: inside a Flickable
                        // `parent` is the content item, zero-width until set.
                        width: optionFlick.width
                        spacing: 12

                        Group {
                            Option {
                                symbol: "auto_mode"
                                label: Translation.tr("Automatic")
                                // Say what automatic resolves to right now.
                                sublabel: routeSheet.defaultName.length > 0
                                    ? Translation.tr("Default output · %1").arg(routeSheet.defaultName)
                                    : Translation.tr("Follow the default output")
                                onPicked: win.routeApp(routeSheet.appNode, null)
                            }
                        }

                        Group {
                            visible: AudioPlugins.profiles.length > 0
                            caption: Translation.tr("Plugin chains")
                            Repeater {
                                model: AudioPlugins.profiles
                                delegate: Option {
                                    required property var modelData
                                    readonly property var sinkNode:
                                        Audio.outputDevices.find(d =>
                                            d?.name === AudioPlugins.sinkNameFor(modelData)) ?? null
                                    symbol: "graphic_eq"
                                    label: modelData?.name ?? ""
                                    sublabel: AudioPlugins.isRunning(modelData.id)
                                        ? Translation.tr("Running")
                                        : Translation.tr("Starts the chain, then routes")
                                    chosen: sinkNode !== null
                                            && routeSheet.currentSink === (sinkNode.description ?? "")
                                    onPicked: {
                                        if (sinkNode) win.routeApp(routeSheet.appNode, sinkNode)
                                        else win.startAndRoute(routeSheet.appNode, modelData)
                                    }
                                }
                            }
                        }

                        Group {
                            caption: Translation.tr("Outputs")
                            Repeater {
                                model: routeSheet.outputs
                                delegate: Option {
                                    required property var modelData
                                    customIcon: AudioLayout.iconFor(modelData)
                                    symbol: AudioLayout.materialSymbolFor(modelData)
                                    label: Audio.friendlyDeviceName(modelData)
                                    sublabel: {
                                        const bits = []
                                        const t = AudioLayout.transportOf(modelData)
                                        if (t.length > 0) bits.push(t)
                                        const lay = AudioLayout.layoutName(modelData?.audio?.channels ?? [])
                                        if (lay !== "—") bits.push(lay)
                                        return bits.join("  •  ")
                                    }
                                    chosen: routeSheet.currentSink.length > 0
                                            && routeSheet.currentSink === (modelData?.description ?? "")
                                    onPicked: win.routeApp(routeSheet.appNode, modelData)
                                }
                            }
                        }
                    }
                }
            }

            // ── Plugins ────────────────────────────────────────────────
            // A sheet over this panel, not a panel of its own beside it. As a
            // stacked panel, the thing you build a chain in and the thing that
            // routes audio into it were two windows opened separately - and
            // PanelStack could evict one to make room for the other.
            PanelSheet {
                open: GlobalStates.audioPluginsOpen
                title: Translation.tr("Plugins")
                maxWidth: 380
                onClosed: GlobalStates.audioPluginsOpen = false

                AudioPluginsPanel {}
            }

        }
    }
}
