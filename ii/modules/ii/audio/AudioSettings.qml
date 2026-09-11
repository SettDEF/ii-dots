pragma ComponentBehavior: Bound
import qs
import qs.services
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
            property string routeAppOpen: ""   // app node id whose target list is expanded
            // Collapsible section state (Channels / Apps foldouts).
            property bool channelsOpen: false
            property bool appsOpen: false

            Process { id: routeProc }
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
            readonly property bool hasGlyph:
                AudioLayout.hasGlyphPreview(win.sink, win.channels)
            readonly property var spots: AudioLayout.glyphChannelSpots(win.sink)

            Rectangle {
                Layout.fillWidth: true
                implicitHeight: 190
                radius: Appearance.rounding.normal
                color: Appearance.colors.colLayer1
                border.width: 1
                border.color: Appearance.colors.colLayer0Border
                clip: true

                // ── Device view ─────────────────────────────────────────
                Item {
                    id: headsetView
                    anchors.fill: parent
                    visible: win.hasGlyph

                    // The device's own glyph, drawn large and dim as a backdrop
                    // — this is the picture of the thing you are listening on.
                    CustomIcon {
                        id: headsetGlyph
                        width: 150; height: 150
                        anchors.centerIn: parent
                        anchors.verticalCenterOffset: -8
                        colorize: true
                        color: Appearance.colors.colOnLayer0
                        opacity: 0.45
                        source: AudioLayout.previewGlyphFor(win.sink)
                    }

                    // Rings sit over the real emitters in the artwork —
                    // earcups on a headset, the grilles flanking the keyboard
                    // on a laptop — so the overlay lines up with the picture
                    // instead of floating beside it. Coordinates come from the
                    // service, which is what keeps them in step with the SVGs.
                    Repeater {
                        model: [0, 1]
                        delegate: LevelKnob {
                            id: cup
                            required property int modelData
                            readonly property bool isLeft: modelData === 0
                            readonly property real vol: win.volumes[modelData] ?? 0

                            // Side-firing drivers are tall slots in the edge of
                            // the chassis; everything else is a driver seen
                            // face-on. The silhouette should say which.
                            readonly property bool slot: AudioLayout.isTabletChassis
                                && AudioLayout.kindOf(win.sink) === "laptop"
                            width: slot ? 30 : 42
                            height: slot ? 58 : 42
                            cornerFactor: slot ? 0.32 : 0.5
                            x: headsetGlyph.x + headsetGlyph.width
                               * (isLeft ? win.spots.left : win.spots.right) - width / 2
                            y: headsetGlyph.y + headsetGlyph.height * win.spots.y - height / 2

                            muted: win.muted
                            value: cup.vol
                            level: AudioMeter.silent ? cup.vol
                                                     : AudioMeter.peakNormalized(cup.modelData)
                            peak: AudioMeter.silent ? -1
                                                    : AudioMeter.channelPeakHoldNormalized(cup.modelData)
                            label: cup.isLeft ? "L" : "R"
                            sublabel: AudioMeter.silent
                                      ? Math.round(cup.vol * 100) + "%"
                                      : (cup.modelData < AudioMeter.channelPeaks.length
                                         ? Math.round(AudioMeter.channelPeaks[cup.modelData]) + " dB"
                                         : "—")
                            onMoved: v => win.setChannel(cup.modelData, v)
                            onTapped: win.testChannel(cup.modelData)
                        }
                    }
                }

                // ── Room view ───────────────────────────────────────────
                Item {
                    anchors.fill: parent
                    visible: !win.hasGlyph

                // Listener, for orientation: on a diagram with no fixed point
                // of reference, "left" is ambiguous.
                Rectangle {
                    x: parent.width / 2 - width / 2
                    y: parent.height * 0.56
                    width: 26; height: 26; radius: 13
                    color: "transparent"
                    border.width: 2
                    border.color: Appearance.colors.colSubtext
                    MaterialSymbol {
                        anchors.centerIn: parent
                        text: "person"; iconSize: 15
                        color: Appearance.colors.colSubtext
                    }
                }

                Repeater {
                    model: win.channels
                    delegate: LevelKnob {
                        id: spk
                        required property var modelData
                        required property int index
                        readonly property var pos: AudioLayout.positionFor(modelData)
                        readonly property real vol: win.volumes[index] ?? 0

                        visible: pos !== null
                        width: 46; height: 46
                        x: (pos ? pos.x : 0.5) * parent.width - width / 2
                        y: (pos ? pos.y : 0.5) * parent.height - height / 2

                        muted: win.muted
                        value: spk.vol
                        level: AudioMeter.silent ? spk.vol
                                                 : AudioMeter.peakNormalized(spk.index)
                        peak: AudioMeter.silent ? -1
                                                : AudioMeter.channelPeakHoldNormalized(spk.index)
                        label: AudioLayout.labelFor(spk.modelData)
                        sublabel: AudioMeter.silent
                                  ? Math.round(spk.vol * 100) + "%"
                                  : (spk.index < AudioMeter.channelPeaks.length
                                     ? Math.round(AudioMeter.channelPeaks[spk.index]) + " dB"
                                     : "—")
                        onMoved: v => win.setChannel(spk.index, v)
                        onTapped: win.testChannel(spk.index)
                    }
                }
                }

                StyledText {
                    anchors.bottom: parent.bottom
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.bottomMargin: 6
                    width: parent.width - 20
                    horizontalAlignment: Text.AlignHCenter
                    elide: Text.ElideRight
                    text: {
                        if (!win.sink) return AudioLayout.layoutName(win.channels);
                        const vendor = AudioLayout.vendorName(win.sink);
                        const model = AudioLayout.productName(win.sink)
                                      || Audio.friendlyDeviceName(win.sink);
                        const name = vendor.length > 0 && model.indexOf(vendor) < 0
                                     ? vendor + " " + model : model;
                        const cap = AudioLayout.previewCaption(win.sink);
                        return AudioLayout.layoutName(win.channels)
                             + (cap.length > 0 ? "  •  " + cap : "")
                             + "  •  " + name;
                    }
                    font.pixelSize: Appearance.font.pixelSize.smallest
                    color: Appearance.colors.colSubtext
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
                    Rectangle {
                        Layout.fillWidth: true
                        implicitHeight: 8
                        radius: 4
                        color: Appearance.colors.colLayer2
                        Rectangle {
                            width: parent.width * AudioMeter.normalized(AudioMeter.momentaryLufs)
                            height: parent.height
                            radius: parent.radius
                            color: AudioMeter.momentaryLufs > -6
                                   ? Appearance.m3colors.m3error
                                   : Appearance.colors.colPrimary
                            Behavior on width { NumberAnimation { duration: 90 } }
                        }
                        Rectangle {
                            x: parent.width * AudioMeter.normalized(-14) - width / 2
                            width: 2; height: parent.height + 4
                            y: -2
                            color: Appearance.colors.colSubtext
                            opacity: 0.7
                        }

                        // Peak-hold dot. Same colPrimary and full rounding as
                        // StyledSlider's handle, so it reads as a marker on the
                        // track rather than as part of the fill. It snaps up
                        // instantly and only the fall-back is animated —
                        // easing the rise would hide the very transient the
                        // marker exists to catch.
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

                    GridLayout {
                        Layout.fillWidth: true
                        columns: 2
                        columnSpacing: 10
                        rowSpacing: 2
                        StyledText {
                            text: Translation.tr("Short-term") + ": "
                                  + (AudioMeter.silent || AudioMeter.shortTermLufs <= -60
                                     ? "—" : AudioMeter.shortTermLufs.toFixed(1))
                            font.pixelSize: Appearance.font.pixelSize.smallest
                            color: Appearance.colors.colSubtext
                        }
                        StyledText {
                            text: Translation.tr("Integrated") + ": "
                                  + (AudioMeter.silent || AudioMeter.integratedLufs <= -60
                                     ? "—" : AudioMeter.integratedLufs.toFixed(1))
                            font.pixelSize: Appearance.font.pixelSize.smallest
                            color: Appearance.colors.colSubtext
                        }
                        StyledText {
                            text: Translation.tr("Range") + ": " + AudioMeter.loudnessRange.toFixed(1) + " LU"
                            font.pixelSize: Appearance.font.pixelSize.smallest
                            color: Appearance.colors.colSubtext
                        }
                        StyledText {
                            // Clipping is a separate question from loudness:
                            // quiet material can still peak over 0 dBFS.
                            readonly property real tp: AudioMeter.channelTruePeaks.length > 0
                                ? Math.max(...AudioMeter.channelTruePeaks) : -70
                            text: Translation.tr("True peak") + ": "
                                  + (tp <= -60 ? "—" : tp.toFixed(1) + " dBFS")
                            font.pixelSize: Appearance.font.pixelSize.smallest
                            color: tp > -0.5 ? Appearance.m3colors.m3error
                                             : Appearance.colors.colSubtext
                        }
                    }
                }
            }

            // ── Recording ───────────────────────────────────────────────
            // Records the same monitor the meter measures, so the file is the
            // mix as heard. The service is a singleton and the keybind lives
            // in Shortcuts.qml, so this panel only ever reflects state - it is
            // never the thing keeping a recording alive.
            Rectangle {
                Layout.fillWidth: true
                implicitHeight: recCol.implicitHeight + 20
                radius: Appearance.rounding.normal
                color: Appearance.colors.colLayer1
                border.width: 1
                border.color: Appearance.colors.colLayer0Border

                ColumnLayout {
                    id: recCol
                    anchors.centerIn: parent
                    width: parent.width - 20
                    spacing: 6

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 10

                        RippleButton {
                            implicitHeight: 34
                            implicitWidth: 34
                            buttonRadius: height / 2
                            colBackground: AudioRecorder.recording
                                ? Appearance.m3colors.m3error
                                : Appearance.colors.colLayer2
                            onClicked: AudioRecorder.toggle()
                            contentItem: MaterialSymbol {
                                anchors.centerIn: parent
                                horizontalAlignment: Text.AlignHCenter
                                text: AudioRecorder.recording ? "stop" : "fiber_manual_record"
                                iconSize: 19
                                color: AudioRecorder.recording
                                    ? Appearance.m3colors.m3onError
                                    : Appearance.colors.colOnLayer2
                            }
                            StyledToolTip {
                                text: AudioRecorder.recording
                                    ? Translation.tr("Stop recording")
                                    : Translation.tr("Record output (Ctrl+Super+A)")
                            }
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 1
                            StyledText {
                                text: AudioRecorder.recording
                                    ? Translation.tr("Recording")
                                    : Translation.tr("Record output")
                                font.pixelSize: Appearance.font.pixelSize.smaller
                                color: Appearance.colors.colOnLayer0
                            }
                            StyledText {
                                Layout.fillWidth: true
                                elide: Text.ElideMiddle
                                text: {
                                    if (AudioRecorder.lastError.length > 0)
                                        return AudioRecorder.lastError;
                                    if (AudioRecorder.outputPath.length > 0)
                                        return AudioRecorder.outputPath
                                            .split("/").pop();
                                    return Translation.tr("Captures the mix as heard");
                                }
                                font.pixelSize: Appearance.font.pixelSize.smallest
                                color: AudioRecorder.lastError.length > 0
                                    ? Appearance.m3colors.m3error
                                    : Appearance.colors.colSubtext
                            }
                        }

                        // Monospace so the digits do not jitter each second.
                        StyledText {
                            visible: AudioRecorder.recording
                            text: AudioRecorder.formatElapsed()
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            font.family: Appearance.font.family.monospace
                            font.bold: true
                            color: Appearance.m3colors.m3error
                        }
                    }
                }
            }

            // ── Master ──────────────────────────────────────────────────
            RowLayout {
                Layout.fillWidth: true
                spacing: 8
                RippleButton {
                    implicitWidth: 32; implicitHeight: 32
                    buttonRadius: 16
                    onClicked: Audio.toggleMute()
                    contentItem: MaterialSymbol {
                        anchors.centerIn: parent
                        text: win.muted ? "volume_off" : "volume_up"
                        iconSize: 18
                        color: win.muted ? Appearance.m3colors.m3error
                                         : Appearance.colors.colOnLayer0
                    }
                }
                StyledText {
                    text: win.muted ? Translation.tr("Muted") : Translation.tr("Output volume")
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: win.muted ? Appearance.m3colors.m3error
                                     : Appearance.colors.colSubtext
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
                    Layout.minimumWidth: 36
                    horizontalAlignment: Text.AlignRight
                    text: Math.round((Audio.sink?.audio?.volume ?? 0) * 100) + "%"
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    font.family: Appearance.font.family.monospace
                    color: Appearance.colors.colOnLayer0
                }
            }

            // ── Per-channel (collapsible) ───────────────────────────────
            Rectangle {   // clickable section header
                Layout.fillWidth: true
                implicitHeight: 30
                radius: Appearance.rounding.small
                color: chHdrHov.hovered ? Appearance.colors.colLayer1Hover : "transparent"
                Behavior on color {
                    animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
                }
                HoverHandler { id: chHdrHov; cursorShape: Qt.PointingHandCursor }
                TapHandler { onTapped: win.channelsOpen = !win.channelsOpen }
                RowLayout {
                    anchors.fill: parent; anchors.leftMargin: 2; anchors.rightMargin: 6; spacing: 6
                    StyledText {
                        text: Translation.tr("Channels")
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        color: Appearance.colors.colSubtext
                    }
                    // Summary so a collapsed foldout still says what's inside,
                    // matching the Apps header's count.
                    StyledText {
                        readonly property string lay: AudioLayout.layoutName(win.channels)
                        visible: lay !== "—"
                        text: lay
                        font.pixelSize: Appearance.font.pixelSize.smallest
                        color: Appearance.colors.colSubtext
                        opacity: 0.7
                    }
                    Item { Layout.fillWidth: true }
                    MaterialSymbol {
                        text: "expand_more"; iconSize: 18
                        color: Appearance.colors.colSubtext
                        rotation: win.channelsOpen ? 180 : 0
                        Behavior on rotation {
                            animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                        }
                    }
                }
            }
            Item {   // collapsible channels body
                Layout.fillWidth: true
                clip: true
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
            Repeater {
                model: win.channels
                delegate: RowLayout {
                    id: chRow
                    required property var modelData
                    required property int index
                    Layout.fillWidth: true
                    spacing: 8
                    StyledText {
                        Layout.minimumWidth: 30
                        text: AudioLayout.labelFor(chRow.modelData)
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        font.family: Appearance.font.family.monospace
                        color: Appearance.colors.colOnLayer0
                    }
                    StyledSlider {
                        Layout.fillWidth: true
                        from: 0; to: 1
                        value: win.volumes[chRow.index] ?? 0
                        onMoved: win.setChannel(chRow.index, value)
                    }
                    StyledText {
                        Layout.minimumWidth: 34
                        horizontalAlignment: Text.AlignRight
                        text: Math.round((win.volumes[chRow.index] ?? 0) * 100) + "%"
                        font.pixelSize: Appearance.font.pixelSize.smallest
                        font.family: Appearance.font.family.monospace
                        color: Appearance.colors.colSubtext
                    }
                }
            }

            // Balance is only a meaningful control for exactly two channels.
            ColumnLayout {
                Layout.fillWidth: true
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

            // ── Output ──────────────────────────────────────────────────
            // Current sink; click to drop down and switch. Every entry carries
            // its own icon so you can see at a glance where sound will go.
            StyledText {
                text: Translation.tr("Output")
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: Appearance.colors.colSubtext
            }
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 3

                // Dropdown header = the selected sink.
                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: 46
                    radius: Appearance.rounding.small
                    color: sinkHdrHov.hovered ? Appearance.colors.colLayer1Hover
                                              : Appearance.colors.colLayer1
                    Behavior on color {
                        animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
                    }
                    HoverHandler { id: sinkHdrHov; cursorShape: Qt.PointingHandCursor }
                    TapHandler { onTapped: win.sinkOpen = !win.sinkOpen }
                    RowLayout {
                        anchors.fill: parent
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
                            model: Audio.outputDevices
                            delegate: Rectangle {
                                id: dev
                                required property var modelData
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
                                        source: AudioLayout.iconFor(dev.modelData)
                                        visible: source.length > 0
                                        color: dev.isDefault ? Appearance.colors.colOnPrimaryContainer
                                                             : Appearance.colors.colOnLayer0
                                    }
                                    MaterialSymbol {
                                        visible: AudioLayout.iconFor(dev.modelData).length === 0
                                        text: AudioLayout.materialSymbolFor(dev.modelData)
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
                                            text: {
                                                const bits = [];
                                                const t = AudioLayout.transportOf(dev.modelData);
                                                if (t.length > 0) bits.push(t);
                                                const lay = AudioLayout.layoutName(dev.modelData?.audio?.channels ?? []);
                                                if (lay !== "—") bits.push(lay);
                                                return bits.length > 0 ? bits.join("  •  ")
                                                                       : Translation.tr("Virtual device");
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

            // ── App routing (collapsible) ───────────────────────────────
            // Each playing app + a link to WHERE it plays: tap its link chip
            // and pick an output to send just that app there (or Automatic).
            Rectangle {   // clickable section header
                Layout.fillWidth: true
                Layout.topMargin: 4
                visible: Audio.outputAppNodes.length > 0
                implicitHeight: 30
                radius: Appearance.rounding.small
                color: appHdrHov.hovered ? Appearance.colors.colLayer1Hover : "transparent"
                Behavior on color {
                    animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
                }
                HoverHandler { id: appHdrHov; cursorShape: Qt.PointingHandCursor }
                TapHandler { onTapped: win.appsOpen = !win.appsOpen }
                RowLayout {
                    anchors.fill: parent; anchors.leftMargin: 2; anchors.rightMargin: 6; spacing: 6
                    StyledText {
                        text: Translation.tr("Apps")
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        color: Appearance.colors.colSubtext
                    }
                    StyledText {
                        text: "(" + Audio.outputAppNodes.length + ")"
                        font.pixelSize: Appearance.font.pixelSize.smallest
                        color: Appearance.colors.colSubtext
                    }
                    Item { Layout.fillWidth: true }
                    MaterialSymbol {
                        text: "expand_more"; iconSize: 18
                        color: Appearance.colors.colSubtext
                        rotation: win.appsOpen ? 180 : 0
                        Behavior on rotation {
                            animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                        }
                    }
                }
            }
            Item {   // collapsible apps body
                Layout.fillWidth: true
                clip: true
                visible: Audio.outputAppNodes.length > 0
                implicitHeight: win.appsOpen ? appBody.implicitHeight : 0
                                ColumnLayout {
                    id: appBody
                    // Slides into the space rather than growing it - see the note
                    // on the parent's height.
                    y: win.appsOpen ? 0 : -appBody.implicitHeight
                    opacity: win.appsOpen ? 1 : 0
                    Behavior on y {
                        animation: Appearance.animation.elementMove.numberAnimation.createObject(this)
                    }
                    Behavior on opacity {
                        animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                    }
                    width: parent.width
                    spacing: 3
            Repeater {
                model: Audio.outputAppNodes
                delegate: ColumnLayout {
                    id: app
                    required property var modelData
                    readonly property string appId: String(app.modelData?.id ?? "")
                    readonly property bool routeOpen: win.routeAppOpen === app.appId
                    Layout.fillWidth: true
                    spacing: 3

                    Rectangle {
                        Layout.fillWidth: true
                        implicitHeight: 42
                        radius: Appearance.rounding.small
                        color: Appearance.colors.colLayer1
                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 10; anchors.rightMargin: 8
                            spacing: 9
                            Image {
                                width: 20; height: 20
                                sourceSize.width: 20; sourceSize.height: 20
                                source: Quickshell.iconPath(
                                    AppSearch.guessIcon(app.modelData?.properties?.["application.name"]
                                                        ?? app.modelData?.name ?? ""),
                                    "multimedia-volume-control")
                            }
                            StyledText {
                                Layout.fillWidth: true
                                text: Audio.appNodeDisplayName(app.modelData)
                                elide: Text.ElideRight
                                font.pixelSize: Appearance.font.pixelSize.smaller
                                color: Appearance.colors.colOnLayer0
                            }
                            // The "link to where" chip.
                            Rectangle {
                                implicitHeight: 26
                                implicitWidth: chipRow.implicitWidth + 14
                                radius: Appearance.rounding.small
                                color: app.routeOpen ? Appearance.colors.colPrimary
                                                     : (appChipHov.hovered ? Appearance.colors.colLayer1Hover
                                                                           : Appearance.colors.colLayer0)
                                Behavior on color {
                                    animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
                                }
                                HoverHandler { id: appChipHov; cursorShape: Qt.PointingHandCursor }
                                TapHandler { onTapped: win.routeAppOpen = app.routeOpen ? "" : app.appId }
                                RowLayout {
                                    id: chipRow
                                    anchors.centerIn: parent
                                    spacing: 4
                                    MaterialSymbol {
                                        text: "link"; iconSize: 15
                                        color: app.routeOpen ? Appearance.colors.colOnPrimary
                                                             : Appearance.colors.colSubtext
                                    }
                                    MaterialSymbol {
                                        text: "expand_more"; iconSize: 15
                                        color: app.routeOpen ? Appearance.colors.colOnPrimary
                                                             : Appearance.colors.colSubtext
                                        rotation: app.routeOpen ? 180 : 0
                                        Behavior on rotation {
                                            animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                                        }
                                    }
                                }
                            }
                        }
                    }
                    // Route targets for this app.
                    Item {
                        Layout.fillWidth: true
                        clip: true
                        implicitHeight: app.routeOpen ? routeList.implicitHeight : 0
                                                ColumnLayout {
                            id: routeList
                            // Slides in; the space is reserved instantly - see the note above.
                            y: app.routeOpen ? 0 : -routeList.implicitHeight
                            opacity: app.routeOpen ? 1 : 0
                            Behavior on y {
                                animation: Appearance.animation.elementMove.numberAnimation.createObject(this)
                            }
                            Behavior on opacity {
                                animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                            }
                            width: parent.width
                            spacing: 3
                            Rectangle {
                                Layout.fillWidth: true
                                implicitHeight: 34
                                radius: Appearance.rounding.small
                                color: autoHov.hovered ? Appearance.colors.colLayer1Hover : Appearance.colors.colLayer1
                                HoverHandler { id: autoHov; cursorShape: Qt.PointingHandCursor }
                                TapHandler { onTapped: win.routeApp(app.modelData, null) }
                                RowLayout {
                                    anchors.fill: parent; anchors.leftMargin: 12; anchors.rightMargin: 12; spacing: 8
                                    MaterialSymbol { text: "auto_mode"; iconSize: 16; color: Appearance.colors.colSubtext }
                                    StyledText {
                                        Layout.fillWidth: true
                                        text: Translation.tr("Automatic")
                                        font.pixelSize: Appearance.font.pixelSize.smallest
                                        color: Appearance.colors.colOnLayer0
                                    }
                                }
                            }
                            Repeater {
                                model: Audio.outputDevices
                                delegate: Rectangle {
                                    id: target
                                    required property var modelData
                                    Layout.fillWidth: true
                                    implicitHeight: 34
                                    radius: Appearance.rounding.small
                                    color: tgtHov.hovered ? Appearance.colors.colLayer1Hover : Appearance.colors.colLayer1
                                    HoverHandler { id: tgtHov; cursorShape: Qt.PointingHandCursor }
                                    TapHandler { onTapped: win.routeApp(app.modelData, target.modelData) }
                                    RowLayout {
                                        anchors.fill: parent; anchors.leftMargin: 12; anchors.rightMargin: 12; spacing: 8
                                        CustomIcon {
                                            width: 16; height: 16; colorize: true
                                            source: AudioLayout.iconFor(target.modelData)
                                            visible: source.length > 0
                                            color: Appearance.colors.colOnLayer0
                                        }
                                        MaterialSymbol {
                                            visible: AudioLayout.iconFor(target.modelData).length === 0
                                            text: AudioLayout.materialSymbolFor(target.modelData); iconSize: 16
                                            color: Appearance.colors.colOnLayer0
                                        }
                                        StyledText {
                                            Layout.fillWidth: true
                                            text: Audio.friendlyDeviceName(target.modelData)
                                            elide: Text.ElideRight
                                            font.pixelSize: Appearance.font.pixelSize.smallest
                                            color: Appearance.colors.colOnLayer0
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
                }   // appBody
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
                TapHandler { onTapped: GlobalStates.audioPluginsOpen = true }
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
        }
    }
}
