pragma ComponentBehavior: Bound
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import Quickshell.Widgets

/**
 * Microphone panel.
 *
 * What Windows gives you through RØDE Central and what Discord gives you through
 * four checkboxes, in one surface: input level, hardware gain, mute, the
 * processing chain, and direct monitoring.
 *
 * The panel deliberately shows TWO gain numbers when they disagree. ALSA mixer
 * values live in the driver rather than on disk, so a replug, a USB reset, a card
 * renumbering or a profile switch silently resets the capture gain to the factory
 * value — 60 dB on the NT1, i.e. maximum, which is where "my mic sounds terrible"
 * comes from. Mic.qml puts it back, and this panel says so while it happens
 * rather than letting a slider lie about the hardware underneath it.
 *
 * Chrome lives in StackedSettingsPanel, device and gain logic in the Mic service.
 */
Scope {
    id: root

    /**
     * Touch the service at startup so it actually exists.
     *
     * `Mic` is a Singleton, and QML creates those lazily on first use. Every
     * reference to it here sat inside a lazily-loaded panel, an IpcHandler body
     * or a shortcut handler — none of which run until you interact. So the gain
     * watchdog, which is the entire reason the service exists, only ran while
     * the panel was open: measured `cardIndex: -1, probeRaw: "(never ran)"` with
     * the panel closed, and correct values one second after opening it.
     *
     * A microphone whose gain is restored only while you are looking at the
     * microphone panel is not restored at all.
     */
    Component.onCompleted: Mic.ready

    IpcHandler {
        target: "mic"
        function toggle(): void { GlobalStates.micOpen = !GlobalStates.micOpen }
        function open(): void   { GlobalStates.micOpen = true }
        function close(): void  { GlobalStates.micOpen = false }
        function mute(): void   { Mic.setMuted(!Mic.muted) }

        /// Set the capture gain in dB. Exists because the persisted value lives
        /// in the running service: editing the state file underneath it is
        /// simply overwritten on the next save.
        function filter(which: string, on: string): string {
            const v = (on === "1" || on === "true" || on === "on");
            if (which === "nr") Mic.setNoiseSuppression(v);
            else if (which === "hp") Mic.setHighPass(v);
            else return "usage: filter nr|hp on|off";
            return which + " -> " + v;
        }

        function gain(db: string): string {
            const v = parseFloat(db);
            if (isNaN(v)) return "usage: gain <dB>";
            Mic.setGainDb(v);
            return "gain -> " + Mic.desiredGainDb.toFixed(0) + " dB";
        }

        /// Dump what the service actually resolved. Three wrong guesses in a row
        /// about why the gain control was "missing" is two more than it should
        /// take; the state is cheap to expose and the alternative is inference.
        function status(): string {
            return JSON.stringify({
                device: Mic.deviceName,
                nodeName: Mic.source?.name ?? null,
                preferred: Mic.preferredName,
                cardIndex: Mic.cardIndex,
                probeRaw: Mic.probeRaw,
                rawAlsaCard: Mic.source?.properties?.["alsa.card"] ?? null,
                propsKeys: Object.keys(Mic.source?.properties ?? {}).length,
                gainControl: Mic.gainControl,
                gainAvailable: Mic.gainAvailable,
                desiredGainDb: Mic.desiredGainDb,
                actualGainDb: Mic.actualGainDb,
                levelDb: Mic.levelDb,
                metering: Mic.metering,
                noiseSuppression: Mic.noiseSuppression,
                highPass: Mic.highPass,
                effectiveSource: Mic.effectiveSource,
                recordingStreams: Mic.recordingStreams,
            }, null, 1);
        }
    }

    GlobalShortcut {
        name: "micToggle"
        description: "Toggle the microphone panel"
        onPressed: GlobalStates.micOpen = !GlobalStates.micOpen
    }

    GlobalShortcut {
        name: "micMute"
        description: "Mute or unmute the microphone"
        onPressed: Mic.setMuted(!Mic.muted)
    }

    StackedPanelLoader {
        isOpen: GlobalStates.micOpen
        sourceComponent: StackedSettingsPanel {
            panelId: "mic"
            title: Translation.tr("Microphone")
            icon: "mic"
            onClosed: GlobalStates.micOpen = false

            // The meter is an ffmpeg process. It runs while this panel is on
            // screen and not a second longer.
            Component.onCompleted: Mic.metering = true
            Component.onDestruction: Mic.metering = false

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 14

                /* --- device + level ------------------------------------- */

                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: deviceCol.implicitHeight + 24
                    radius: Appearance.rounding.normal
                    color: Appearance.colors.colLayer1

                    ColumnLayout {
                        id: deviceCol
                        anchors { left: parent.left; right: parent.right; top: parent.top; margins: 12 }
                        spacing: 8

                        RowLayout {
                            spacing: 8
                            MaterialSymbol {
                                text: Mic.muted ? "mic_off" : "mic"
                                iconSize: 17
                                color: Mic.muted ? Appearance.m3colors.m3error : Appearance.colors.colPrimary
                            }
                            // A picker, not a label. Following the system default
                            // meant the panel controlled whatever else had last
                            // claimed it — observed showing a muted onboard input
                            // while the real microphone sat unused.
                            StyledComboBox {
                                id: devicePicker
                                Layout.fillWidth: true
                                model: Mic.sources.map(n => n.description || n.name)
                                currentIndex: Mic.sources.findIndex(n => n === Mic.source)

                                // Guard: only write the choice when a HUMAN picked
                                // it. The device list is rebuilt whenever PipeWire
                                // re-enumerates — which happened repeatedly today
                                // through dock resets and WirePlumber restarts —
                                // and the index shifting under the box was enough
                                // to persist a device nobody selected. It silently
                                // moved the panel onto the onboard card.
                                property bool userPicked: false
                                onPressedChanged: if (pressed) userPicked = true
                                onActivated: index => {
                                    if (!userPicked) return;
                                    userPicked = false;
                                    const pick = Mic.sources[index];
                                    if (pick?.name) Mic.selectSource(pick.name);
                                }
                            }
                            StyledSwitch {
                                checked: !Mic.muted
                                onClicked: { checked = Qt.binding(() => !Mic.muted); Mic.setMuted(!Mic.muted) }
                            }
                        }

                        StyledText {
                            visible: Mic.preferredMissing
                            Layout.fillWidth: true
                            wrapMode: Text.Wrap
                            text: Translation.tr("Your chosen microphone is not connected — using the default.")
                            font.pixelSize: Appearance.font.pixelSize.smallest
                            color: Appearance.m3colors.m3error
                        }

                        // Live input level. The one thing you cannot judge from a
                        // number alone is whether you are hitting the ceiling.
                        Rectangle {
                            Layout.fillWidth: true
                            implicitHeight: 6
                            radius: Appearance.rounding.verysmall
                            color: Appearance.colors.colLayer2

                            Rectangle {
                                anchors { left: parent.left; top: parent.top; bottom: parent.bottom }
                                width: Mic.muted ? parent.width
                                    : parent.width * Math.max(0, Math.min(1, (Mic.levelDb + 60) / 60))
                                radius: parent.radius
                                // Red only where it means something: approaching
                                // the ceiling, not merely "loud".
                                // A full red bar for muted: an empty bar is what
                                // a working-but-quiet mic looks like, so silence
                                // must not be drawn the same way as "off".
                                color: (Mic.muted || Mic.clipping)
                                    ? Appearance.m3colors.m3error
                                    : Appearance.colors.colPrimary
                                opacity: Mic.muted ? 0.35 : 1
                                Behavior on width { NumberAnimation { duration: 60 } }
                            }
                        }

                        // Three different faults used to read as one word.
                        // "silent" looked the same whether the mic was muted,
                        // turned down to 1.8%, or simply in a quiet room — and
                        // all three happened here. Each says its own name now.
                        StyledText {
                            Layout.fillWidth: true
                            wrapMode: Text.Wrap
                            text: Mic.muted
                                ? Translation.tr("MUTED — nothing is being captured")
                                : Mic.volume < 0.15
                                    ? Translation.tr("Input volume is %1% — almost nothing gets through")
                                        .arg(Math.round(Mic.volume * 100))
                                    : Mic.silent
                                        ? Translation.tr("no sound reaching the mic")
                                        : (Mic.levelDb.toFixed(1) + " LUFS")
                            font.family: (Mic.muted || Mic.volume < 0.15)
                                ? Appearance.font.family.main
                                : Appearance.font.family.monospace
                            font.pixelSize: Appearance.font.pixelSize.smallest
                            color: (Mic.muted || Mic.volume < 0.15)
                                ? Appearance.m3colors.m3error
                                : Appearance.colors.colSubtext
                        }

                        // NO separate input-volume slider here.
                        //
                        // Measured: raising the ALSA 'Mic' control 25 -> 45 dB
                        // moved PipeWire's volume 0.26 -> 0.56 on its own, and
                        // setting PipeWire to 60% pushed ALSA back to 25 dB.
                        // They are ONE control on this device; showing both was
                        // the same knob under two names, and the gain watchdog
                        // then "restored" every volume change the user made.
                    }
                }

                /* --- hardware gain --------------------------------------- */

                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: gainCol.implicitHeight + 24
                    radius: Appearance.rounding.normal
                    color: Appearance.colors.colLayer1

                    ColumnLayout {
                        id: gainCol
                        anchors { left: parent.left; right: parent.right; top: parent.top; margins: 12 }
                        spacing: 8

                        RowLayout {
                            spacing: 8
                            MaterialSymbol { text: "tune"; iconSize: 17; color: Appearance.colors.colPrimary }
                            StyledText {
                                Layout.fillWidth: true
                                text: Translation.tr("Hardware gain")
                                font.weight: Font.DemiBold
                                font.pixelSize: Appearance.font.pixelSize.smaller
                            }
                            StyledText {
                                text: `${Mic.desiredGainDb.toFixed(0)} dB`
                                font.family: Appearance.font.family.monospace
                                font.pixelSize: Appearance.font.pixelSize.smallie
                            }
                        }

                        // Writes only while the user is actually dragging.
                        //
                        // Third time this bit: a QML control bound to state it
                        // also writes back will fire its handler when the state
                        // moves underneath it. Here that turned a device change
                        // into a gain change — the value landed on 21.485 dB,
                        // a number nobody chose — and on the device picker it
                        // silently switched the panel to the onboard card.
                        // stepSize 1: the control is in dB and the card's own
                        // range is whole dB, so a continuous slider only ever
                        // produced values like 45.155 which then displayed as
                        // "45". The number shown is now the number stored.
                        StyledSlider {
                            id: gainSlider
                            Layout.fillWidth: true
                            enabled: Mic.gainAvailable
                            from: Mic.minGainDb
                            to: Mic.maxGainDb
                            stepSize: 1
                            snapMode: Slider.SnapAlways
                            value: Mic.desiredGainDb
                            onMoved: Mic.setGainDb(value)
                        }

                        // Fan noise is the reason this panel exists, and gain is
                        // the biggest lever on it: measured here, 45 dB -> 20 dB
                        // dropped the noise floor by about 25 dB, far more than
                        // any filter recovers afterwards. Worth saying out loud
                        // at the point where someone is about to drag it up.
                        StyledText {
                            visible: Mic.desiredGainDb > 35
                            Layout.fillWidth: true
                            wrapMode: Text.Wrap
                            text: Translation.tr("High gain amplifies fan noise as much as your voice — try moving closer instead.")
                            font.pixelSize: Appearance.font.pixelSize.smallest
                            color: Appearance.m3colors.m3error
                        }

                        // Shown only while the hardware disagrees with the slider,
                        // which is exactly the moment the old behaviour was
                        // invisible: the device had reset and nothing said so.
                        StyledText {
                            visible: Mic.gainStuck
                            Layout.fillWidth: true
                            wrapMode: Text.Wrap
                            text: Translation.tr("Gave up restoring the gain — the device keeps refusing it.")
                            font.pixelSize: Appearance.font.pixelSize.smallest
                            color: Appearance.m3colors.m3error
                        }

                        StyledText {
                            visible: Mic.gainDrifted && !Mic.gainStuck
                            Layout.fillWidth: true
                            wrapMode: Text.Wrap
                            text: Translation.tr("Device reset itself to %1 dB — restoring")
                                .arg(Mic.actualGainDb.toFixed(0))
                            font.pixelSize: Appearance.font.pixelSize.smallest
                            color: Appearance.m3colors.m3error
                        }

                        StyledText {
                            visible: !Mic.gainAvailable
                            Layout.fillWidth: true
                            wrapMode: Text.Wrap
                            text: Translation.tr("This device has no hardware gain control.")
                            font.pixelSize: Appearance.font.pixelSize.smallest
                            color: Appearance.colors.colSubtext
                        }
                    }
                }

                /* --- who is listening ------------------------------------ */

                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: appsCol.implicitHeight + 24
                    radius: Appearance.rounding.normal
                    color: Appearance.colors.colLayer1

                    ColumnLayout {
                        id: appsCol
                        anchors { left: parent.left; right: parent.right; top: parent.top; margins: 12 }
                        spacing: 8

                        RowLayout {
                            spacing: 8
                            MaterialSymbol {
                                text: "graphic_eq"
                                iconSize: 17
                                // Lit only while something is actually recording —
                                // this row answers "is anything listening right
                                // now", which is the question you want answered
                                // at a glance.
                                color: Mic.recordingStreams.length > 0
                                    ? Appearance.m3colors.m3error
                                    : Appearance.colors.colSubtext
                            }
                            StyledText {
                                Layout.fillWidth: true
                                text: Translation.tr("Apps recording")
                                font.weight: Font.DemiBold
                                font.pixelSize: Appearance.font.pixelSize.smaller
                            }
                            StyledText {
                                text: String(Mic.recordingStreams.length)
                                font.family: Appearance.font.family.monospace
                                font.pixelSize: Appearance.font.pixelSize.smallie
                                color: Appearance.colors.colSubtext
                            }
                        }

                        StyledText {
                            visible: Mic.recordingStreams.length === 0
                            Layout.fillWidth: true
                            wrapMode: Text.Wrap
                            text: Translation.tr("Nothing is using the microphone.")
                            font.pixelSize: Appearance.font.pixelSize.smallest
                            color: Appearance.colors.colSubtext
                        }

                        Repeater {
                            model: Mic.recordingStreams
                            delegate: RowLayout {
                                required property var modelData
                                Layout.fillWidth: true
                                spacing: 8

                                // An icon and a real name. `application.name` is
                                // whatever the library felt like reporting —
                                // ffmpeg calls itself "Lavf63.1.101" — so the
                                // process binary is the better key for both.
                                // A generic "?" document icon is worse than no
                                // icon at all — it reads as a broken app rather
                                // than as an app with no icon. Fall back to the
                                // house microphone glyph instead.
                                Item {
                                    implicitWidth: 20
                                    implicitHeight: 20
                                    property string iconPath: Quickshell.iconPath(
                                        AppSearch.guessIcon(modelData.binary || modelData.app), true)
                                    IconImage {
                                        anchors.fill: parent
                                        visible: parent.iconPath !== ""
                                        source: parent.iconPath
                                    }
                                    MaterialSymbol {
                                        anchors.centerIn: parent
                                        visible: parent.iconPath === ""
                                        text: "mic"
                                        iconSize: 18
                                        color: Appearance.colors.colSubtext
                                    }
                                }

                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 0
                                    StyledText {
                                        Layout.fillWidth: true
                                        text: modelData.binary || modelData.app
                                        elide: Text.ElideRight
                                        font.pixelSize: Appearance.font.pixelSize.smaller
                                    }
                                    // The device is only worth a line when it is
                                    // NOT the one selected above. Three rows all
                                    // repeating the same device name is noise that
                                    // hides the one row that differs.
                                    StyledText {
                                        Layout.fillWidth: true
                                        visible: modelData.sourceName !== (Mic.source?.name ?? "")
                                        text: modelData.sourceDesc
                                        elide: Text.ElideRight
                                        font.pixelSize: Appearance.font.pixelSize.smallest
                                        color: Appearance.m3colors.m3error
                                    }
                                }

                                // A bare glyph floating at the end of a row does
                                // not read as something you can press. Given the
                                // chip shape the rest of this config uses for
                                // actions, it now looks like the control it is.
                                RippleButton {
                                    implicitHeight: 28
                                    implicitWidth: 34
                                    buttonRadius: Appearance.rounding.full
                                    colBackground: Appearance.colors.colLayer2
                                    colBackgroundHover: Appearance.colors.colLayer2Hover
                                    onClicked: streamMenu.openFor(modelData)
                                    contentItem: MaterialSymbol {
                                        anchors.centerIn: parent
                                        horizontalAlignment: Text.AlignHCenter
                                        text: "swap_horiz"
                                        iconSize: 17
                                        color: Appearance.colors.colOnLayer2
                                    }
                                    StyledToolTip { text: Translation.tr("Move to another microphone") }
                                }
                            }
                        }

                        // One picker shared by every row, rather than one combo
                        // box per app.
                        StyledComboBox {
                            id: streamMenu
                            Layout.fillWidth: true
                            visible: false
                            property var target: null
                            function openFor(row) {
                                target = row;
                                model = Mic.sources.map(n => n.description || n.name);
                                currentIndex = Mic.sources.findIndex(n => n.name === row.sourceName);
                                visible = true;
                                popup.open();
                            }
                            onActivated: index => {
                                Mic.moveStream(target?.index, Mic.sources[index]?.name ?? "");
                                visible = false;
                            }
                        }
                    }
                }

                /* --- processing ------------------------------------------ */

                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: fxCol.implicitHeight + 24
                    radius: Appearance.rounding.normal
                    color: Appearance.colors.colLayer1

                    ColumnLayout {
                        id: fxCol
                        anchors { left: parent.left; right: parent.right; top: parent.top; margins: 12 }
                        spacing: 8

                        RowLayout {
                            spacing: 8
                            MaterialSymbol { text: "graphic_eq"; iconSize: 17; color: Appearance.colors.colPrimary }
                            StyledText {
                                Layout.fillWidth: true
                                text: Translation.tr("Processing")
                                font.weight: Font.DemiBold
                                font.pixelSize: Appearance.font.pixelSize.smaller
                            }
                        }

                        // A switch that cannot act is shown disabled WITH the
                        // reason, not hidden — the same rule the rest of this
                        // config follows for unavailable options.
                        MicToggle {
                            label: Translation.tr("Noise suppression")
                            help: Mic.rnnoiseAvailable
                                ? Translation.tr("Removes steady background noise (fan, hiss).")
                                : Translation.tr("Needs the rnnoise LADSPA plugin — not installed.")
                            checked: Mic.noiseSuppression
                            available: Mic.rnnoiseAvailable
                            onToggled: on => Mic.setNoiseSuppression(on)
                        }

                        MicToggle {
                            label: Translation.tr("Echo cancellation")
                            help: Translation.tr("Stops your speakers being picked up by the mic.")
                            checked: Mic.echoCancel
                            available: Mic.echoCancelAvailable
                            onToggled: on => Mic.setEchoCancel(on)
                        }

                        MicToggle {
                            label: Translation.tr("High-pass filter")
                            help: Translation.tr("Cuts rumble below %1 Hz — desk thumps, handling noise.")
                                .arg(Mic.highPassHz.toFixed(0))
                            checked: Mic.highPass
                            available: true
                            onToggled: on => Mic.setHighPass(on)
                        }

                        MicToggle {
                            label: Translation.tr("Hear myself")
                            help: Translation.tr("Direct monitoring through your headphones.")
                            checked: Mic.monitoring
                            available: true
                            onToggled: on => Mic.setMonitoring(on)
                        }
                    }
                }
            }
        }
    }
}
