pragma ComponentBehavior: Bound
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

/**
 * KeyboardSettings — small panel opened from the OSK's "tune" button.
 * Exposes the Hyprland input{} keyboard knobs (repeat delay/rate, numlock,
 * resolve-binds-by-sym). Live-applies via `hyprctl keyword`, session-only —
 * footer warns you to copy to the hypr conf if you want persistence.
 */
Scope {
    id: root

    Loader {
        active: GlobalStates.kbSettingsOpen
        sourceComponent: PanelWindow {
            id: win
            visible: GlobalStates.kbSettingsOpen
            anchors { top: true; bottom: true; left: true; right: true }
            exclusiveZone: 0
            color: "transparent"
            WlrLayershell.namespace: "quickshell:kbSettings"
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand

            mask: Region { item: card }

            Component.onCompleted: GlobalFocusGrab.addDismissable(win)
            Component.onDestruction: GlobalFocusGrab.removeDismissable(win)
            Connections {
                target: GlobalFocusGrab
                function onDismissed() { GlobalStates.kbSettingsOpen = false }
            }

            // Current values — read from hyprctl on open, written back on edit.
            property int  repeatDelay:     600
            property int  repeatRate:      25
            property bool numlockDefault:  false
            property bool resolveBySym:    true

            Process {
                id: loadProc
                running: true
                command: ["bash", "-c",
                    "hyprctl getoption input:repeat_delay -j; echo '<S>';"
                    + " hyprctl getoption input:repeat_rate -j; echo '<S>';"
                    + " hyprctl getoption input:numlock_by_default -j; echo '<S>';"
                    + " hyprctl getoption input:resolve_binds_by_sym -j"]
                stdout: StdioCollector { onStreamFinished: {
                    const parts = text.split("<S>")
                    try { win.repeatDelay = JSON.parse(parts[0]).int ?? 600 }      catch (e) {}
                    try { win.repeatRate  = JSON.parse(parts[1]).int ?? 25 }       catch (e) {}
                    try { win.numlockDefault = JSON.parse(parts[2]).int === 1 }    catch (e) {}
                    try { win.resolveBySym   = JSON.parse(parts[3]).int === 1 }    catch (e) {}
                }}
            }

            // Apply live AND persist. `hyprctl keyword` takes effect now; the
            // upsert into hyprland/shellOverrides/keyboard.conf (sourced after
            // general.conf) makes it survive a reboot. Idempotent: rewrites the
            // key's line if present, else appends it.
            function setOpt(key, value) {
                const v = String(value)
                Quickshell.execDetached(["bash", "-c",
                      `hyprctl keyword input:${key} '${v}' >/dev/null 2>&1; `
                    + `f="$HOME/.config/hypr/hyprland/shellOverrides/keyboard.conf"; `
                    + `mkdir -p "$(dirname "$f")"; touch "$f"; `
                    + `if grep -qE '^input:${key} =' "$f"; then `
                    +   `sed -i 's|^input:${key} =.*|input:${key} = ${v}|' "$f"; `
                    + `else printf 'input:%s = %s\\n' '${key}' '${v}' >> "$f"; fi`
                ])
            }

            StyledRectangularShadow { target: card }
            Rectangle {
                id: card
                anchors.bottom: parent.bottom
                anchors.bottomMargin: 320       // sit above the OSK
                anchors.horizontalCenter: parent.horizontalCenter
                implicitWidth: 460
                implicitHeight: contentCol.implicitHeight + 32
                radius: Appearance.rounding.windowRounding
                color: Appearance.colors.colLayer0
                border.width: 1
                border.color: Appearance.colors.colLayer0Border
                focus: win.visible

                Keys.onPressed: event => {
                    if (event.key === Qt.Key_Escape) {
                        GlobalStates.kbSettingsOpen = false
                        event.accepted = true
                    }
                }

                ColumnLayout {
                    id: contentCol
                    anchors.fill: parent
                    anchors.margins: 16
                    spacing: 14

                    // ── Header ─────────────────────────────────────────
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 10
                        MaterialSymbol {
                            text: "tune"
                            iconSize: Appearance.font.pixelSize.title
                            color: Appearance.colors.colOnLayer0
                        }
                        StyledText {
                            Layout.fillWidth: true
                            text: qsTr("Keyboard settings")
                            font.pixelSize: Appearance.font.pixelSize.large
                            font.weight: Font.Medium
                            color: Appearance.colors.colOnLayer0
                        }
                    }

                    // ── Repeat delay ───────────────────────────────────
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 4
                        RowLayout {
                            Layout.fillWidth: true
                            StyledText {
                                text: qsTr("Repeat delay")
                                color: Appearance.colors.colOnLayer0
                                Layout.fillWidth: true
                            }
                            StyledText {
                                text: win.repeatDelay + " ms"
                                color: Appearance.colors.colPrimary
                                font.family: Appearance.font.family.monospace
                                font.pixelSize: Appearance.font.pixelSize.small
                            }
                        }
                        Slider {
                            Layout.fillWidth: true
                            from: 100; to: 2000; stepSize: 50
                            value: win.repeatDelay
                            // Apply on release only — avoids spamming hyprctl while dragging.
                            onPressedChanged: if (!pressed) win.setOpt("repeat_delay", Math.round(value))
                            onMoved: win.repeatDelay = Math.round(value)
                        }
                    }

                    // ── Repeat rate ────────────────────────────────────
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 4
                        RowLayout {
                            Layout.fillWidth: true
                            StyledText {
                                text: qsTr("Repeat rate")
                                color: Appearance.colors.colOnLayer0
                                Layout.fillWidth: true
                            }
                            StyledText {
                                text: win.repeatRate + " Hz"
                                color: Appearance.colors.colPrimary
                                font.family: Appearance.font.family.monospace
                                font.pixelSize: Appearance.font.pixelSize.small
                            }
                        }
                        Slider {
                            Layout.fillWidth: true
                            from: 5; to: 100; stepSize: 1
                            value: win.repeatRate
                            onPressedChanged: if (!pressed) win.setOpt("repeat_rate", Math.round(value))
                            onMoved: win.repeatRate = Math.round(value)
                        }
                    }

                    // ── Numlock on by default ──────────────────────────
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 10
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 2
                            StyledText {
                                text: qsTr("Numlock on by default")
                                color: Appearance.colors.colOnLayer0
                            }
                            StyledText {
                                text: qsTr("Applies to newly attached keyboards")
                                color: Appearance.colors.colOnLayer0
                                opacity: 0.5
                                font.pixelSize: Appearance.font.pixelSize.smaller
                            }
                        }
                        Switch {
                            checked: win.numlockDefault
                            onToggled: {
                                win.numlockDefault = checked
                                win.setOpt("numlock_by_default", checked ? "true" : "false")
                            }
                        }
                    }

                    // ── Resolve binds by sym ───────────────────────────
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 10
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 2
                            StyledText {
                                text: qsTr("Resolve binds by keysym")
                                color: Appearance.colors.colOnLayer0
                            }
                            StyledText {
                                text: qsTr("Off → keybinds use physical positions (keycodes)")
                                color: Appearance.colors.colOnLayer0
                                opacity: 0.5
                                font.pixelSize: Appearance.font.pixelSize.smaller
                            }
                        }
                        Switch {
                            checked: win.resolveBySym
                            onToggled: {
                                win.resolveBySym = checked
                                win.setOpt("resolve_binds_by_sym", checked ? "true" : "false")
                            }
                        }
                    }

                    // ── Footer ─────────────────────────────────────────
                    StyledText {
                        Layout.fillWidth: true
                        horizontalAlignment: Text.AlignHCenter
                        text: qsTr("Esc to close · changes are saved and persist across reboots")
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        color: Appearance.colors.colOnLayer0
                        opacity: 0.4
                    }
                }
            }
        }
    }
}
