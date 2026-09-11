import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland

Scope {
    id: root
    property string protectionMessage: ""
    property var focusedScreen: Quickshell.screens.find(s => s.name === Hyprland.focusedMonitor?.name)
    property bool capslockActive: false

    property string currentIndicator: "volume"
    property var indicators: [
        {
            id: "volume",
            sourceUrl: "indicators/VolumeIndicator.qml"
        },
        {
            id: "brightness",
            sourceUrl: "indicators/BrightnessIndicator.qml"
        },
        {
            id: "capslock",
            sourceUrl: "indicators/CapsLockIndicator.qml"
        },
    ]

    function triggerOsd() {
        GlobalStates.osdVolumeOpen = true;
        osdTimeout.restart();
    }

    Timer {
        id: osdTimeout
        interval: Config.options.osd.timeout
        repeat: false
        running: false
        onTriggered: {
            GlobalStates.osdVolumeOpen = false;
            root.protectionMessage = "";
        }
    }

    Connections {
        target: Brightness
        function onBrightnessChanged() {
            root.protectionMessage = "";
            root.currentIndicator = "brightness";
            root.triggerOsd();
        }
    }

    Connections {
        // Listen to volume changes
        target: Audio.sink?.audio ?? null
        function onVolumeChanged() {
            if (!Audio.ready)
                return;
            root.currentIndicator = "volume";
            root.triggerOsd();
        }
        function onMutedChanged() {
            if (!Audio.ready)
                return;
            root.currentIndicator = "volume";
            root.triggerOsd();
        }
    }

    Connections {
        // Listen to protection triggers
        target: Audio
        function onSinkProtectionTriggered(reason) {
            root.protectionMessage = reason;
            root.currentIndicator = "volume";
            root.triggerOsd();
        }
    }

    Loader {
        id: osdLoader
        active: GlobalStates.osdVolumeOpen

        sourceComponent: PanelWindow {
            id: osdRoot
            color: "transparent"

            Connections {
                target: root
                function onFocusedScreenChanged() {
                    osdRoot.screen = root.focusedScreen;
                }
            }

            WlrLayershell.namespace: "quickshell:onScreenDisplay"
            WlrLayershell.layer: WlrLayer.Overlay
            anchors {
                top: !Config.options.bar.bottom
                bottom: Config.options.bar.bottom
            }
            mask: Region {
                item: osdValuesWrapper
            }

            exclusionMode: ExclusionMode.Ignore
            exclusiveZone: 0
            margins {
                top: Appearance.sizes.barHeight
                bottom: Appearance.sizes.barHeight
            }

            implicitWidth: columnLayout.implicitWidth
            implicitHeight: columnLayout.implicitHeight
            visible: osdLoader.active

            ColumnLayout {
                id: columnLayout
                anchors.horizontalCenter: parent.horizontalCenter

                Item {
                    id: osdValuesWrapper
                    // Extra space for shadow
                    implicitHeight: contentColumnLayout.implicitHeight
                    implicitWidth: contentColumnLayout.implicitWidth
                    clip: true

                    MouseArea {
                        anchors.fill: parent
                        hoverEnabled: true
                        onEntered: GlobalStates.osdVolumeOpen = false
                    }

                    Column {
                        id: contentColumnLayout
                        anchors {
                            top: parent.top
                            left: parent.left
                            right: parent.right
                        }
                        spacing: 0

                        Loader {
                            id: osdIndicatorLoader
                            source: root.indicators.find(i => i.id === root.currentIndicator)?.sourceUrl
                        }

                        Item {
                            id: protectionMessageWrapper
                            anchors.horizontalCenter: parent.horizontalCenter
                            implicitHeight: protectionMessageBackground.implicitHeight
                            implicitWidth: protectionMessageBackground.implicitWidth
                            opacity: root.protectionMessage !== "" ? 1 : 0

                            StyledRectangularShadow {
                                target: protectionMessageBackground
                            }
                            Rectangle {
                                id: protectionMessageBackground
                                anchors.centerIn: parent
                                color: Appearance.m3colors.m3error
                                property real padding: 10
                                implicitHeight: protectionMessageRowLayout.implicitHeight + padding * 2
                                implicitWidth: protectionMessageRowLayout.implicitWidth + padding * 2
                                radius: Appearance.rounding.normal

                                RowLayout {
                                    id: protectionMessageRowLayout
                                    anchors.centerIn: parent
                                    MaterialSymbol {
                                        id: protectionMessageIcon
                                        text: "dangerous"
                                        iconSize: Appearance.font.pixelSize.hugeass
                                        color: Appearance.m3colors.m3onError
                                    }
                                    StyledText {
                                        id: protectionMessageTextWidget
                                        horizontalAlignment: Text.AlignHCenter
                                        color: Appearance.m3colors.m3onError
                                        wrapMode: Text.Wrap
                                        text: root.protectionMessage
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    IpcHandler {
        target: "osdVolume"

        function trigger() {
            root.triggerOsd();
        }

        function hide() {
            GlobalStates.osdVolumeOpen = false;
        }

        function toggle() {
            GlobalStates.osdVolumeOpen = !GlobalStates.osdVolumeOpen;
        }
    }
    GlobalShortcut {
        name: "osdVolumeTrigger"
        description: "Triggers volume OSD on press"

        onPressed: {
            root.triggerOsd();
        }
    }
    GlobalShortcut {
        name: "osdVolumeHide"
        description: "Hides volume OSD on press"

        onPressed: {
            GlobalStates.osdVolumeOpen = false;
        }
    }

    // Reads the real LED state. Two things this must get right:
    //
    //  1. OR across EVERY *::capslock LED, not `head -n 1` of the glob.
    //     Glob order puts input2 (the phantom "AT Translated Set 2
    //     keyboard") ahead of input55 (the actual GZ302EA keyboard),
    //     so head -n 1 always read the wrong device.
    //  2. Emit only "0" or "1". A failed/empty read must NOT be
    //     interpreted, or a transient miss silently forces OFF.
    Process {
        id: capslockReadProc
        running: true
        command: ["bash", "-c",
            "s=0; for f in /sys/class/leds/*::capslock/brightness; do [ -r \"$f\" ] || continue; v=$(cat \"$f\" 2>/dev/null); [ -n \"$v\" ] && [ \"$v\" != \"0\" ] && s=1; done; echo $s"]
        stdout: StdioCollector {
            onStreamFinished: {
                const v = text.trim();
                // Ignore anything that isn't a clean 0/1 — better to keep
                // the current guess than to flip on a failed read.
                if (v === "0" || v === "1")
                    root.capslockActive = (v === "1");
            }
        }
    }

    // Re-read shortly after a press. The flip in trigger() is what makes
    // the OSD feel instant; this is what stops it drifting. Without it the
    // state was pure dead reckoning: ONE missed or extra event (IPC
    // dropped while the shell was busy, the on-screen keyboard setting
    // caps via Ydotool, the detachable keyboard re-enumerating) left the
    // indicator inverted until the next shell reload.
    Timer {
        id: capslockVerify
        interval: 150
        repeat: false
        onTriggered: {
            // false→true, not a bare true: if a previous read is still in
            // flight, assigning true again is a no-op and the verification
            // would silently never happen.
            capslockReadProc.running = false;
            capslockReadProc.running = true;
        }
    }

    IpcHandler {
        target: "capslock"

        function trigger() {
            // Flip immediately so the OSD is instant and rapid presses each
            // get their own indicator instead of being eaten by a debounce.
            // This is a GUESS: it assumes every press reaches us exactly once.
            // capslockVerify below is what makes a wrong guess self-correct.
            root.capslockActive = !root.capslockActive;
            // ...then confirm against the hardware and correct if we guessed wrong.
            capslockVerify.restart();
            root.currentIndicator = "capslock";
            root.triggerOsd();
            KeyTracker.flashKey(root.capslockActive ? "CAPS ON" : "CAPS OFF");
            KeyTracker.addXp(1);
        }
    }
}
