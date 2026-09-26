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
import Quickshell.Hyprland

/**
 * Caption strip.
 *
 * Subtitles for your own machine. Sits low and centred, where film subtitles
 * sit, because that is where eyes already expect them and it keeps the middle
 * of the screen — the game — clear.
 *
 * It takes NO input: `WlrLayershell` exclusion zone none, no keyboard focus,
 * and the surface ignores clicks entirely. Captions appearing over a game must
 * never eat a click or steal focus; that is the whole reason this is a layer
 * surface rather than a window.
 *
 * Only the last few lines are shown. Older ones fade rather than scroll: a
 * caption you have already read moving upward is a distraction, and the
 * scrollback belongs in a panel, not over a game.
 */
Scope {
    id: root

    // The service is a background listener; it must exist before this does.
    Component.onCompleted: Captions.ready

    IpcHandler {
        target: "captions"
        function toggle(): void { Captions.toggle() }
        function start(): void  { Captions.active = true }
        function stop(): void   { Captions.active = false }
        function clear(): void  { Captions.clear() }
        function translate(lang: string): void { Captions.translateTo = lang }
        function status(): string {
            return JSON.stringify({
                active: Captions.active,
                target: Captions.effectiveTarget,
                translateTo: Captions.translateTo,
                lines: Captions.lines.length,
                error: Captions.lastError,
            })
        }
    }

    GlobalShortcut {
        name: "captionsToggle"
        description: "Toggle live captions"
        onPressed: Captions.toggle()
    }

    Variants {
        model: Quickshell.screens

        PanelWindow {
            id: win
            required property var modelData
            screen: win.modelData

            visible: Captions.active && (Captions.lines.length > 0 || Captions.lastError.length > 0)

            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.namespace: "quickshell:captions"
            // Never take focus, never reserve space, never absorb a click.
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
            exclusionMode: ExclusionMode.Ignore
            color: "transparent"

            anchors { left: true; right: true; bottom: true }
            implicitHeight: strip.implicitHeight + 40

            mask: Region {}   // clicks pass straight through to the game

            ColumnLayout {
                id: strip
                anchors {
                    bottom: parent.bottom
                    horizontalCenter: parent.horizontalCenter
                    bottomMargin: 40
                }
                width: Math.min(win.width * 0.7, 1100)
                spacing: 5

                // A failure has to be visible, or the toggle just looks broken.
                Rectangle {
                    visible: Captions.lastError.length > 0
                    Layout.alignment: Qt.AlignHCenter
                    implicitWidth: errText.implicitWidth + 28
                    implicitHeight: errText.implicitHeight + 16
                    radius: Appearance.rounding.small
                    color: Qt.alpha(Appearance.m3colors.m3error, 0.92)
                    StyledText {
                        id: errText
                        anchors.centerIn: parent
                        text: Captions.lastError
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        color: Appearance.m3colors.m3onError
                    }
                }

                Repeater {
                    // Only the tail. `slice` on a plain list is cheap and keeps
                    // the delegate count fixed however long the session runs.
                    model: Captions.lines.slice(-3)
                    delegate: Rectangle {
                        id: lineBox
                        required property var modelData
                        required property int index
                        Layout.alignment: Qt.AlignHCenter
                        Layout.maximumWidth: strip.width
                        implicitWidth: Math.min(lineCol.implicitWidth + 28, strip.width)
                        implicitHeight: lineCol.implicitHeight + 14
                        radius: Appearance.rounding.small
                        // The newest line is the one being read; older ones step
                        // back rather than competing with it.
                        readonly property int fromEnd: Captions.lines.slice(-3).length - 1 - lineBox.index
                        color: Qt.alpha("#000000", lineBox.fromEnd === 0 ? 0.82 : 0.55)

                        ColumnLayout {
                            id: lineCol
                            anchors.centerIn: parent
                            width: parent.width - 28
                            spacing: 2

                            StyledText {
                                Layout.fillWidth: true
                                horizontalAlignment: Text.AlignHCenter
                                wrapMode: Text.WordWrap
                                text: lineBox.modelData.text
                                font.pixelSize: lineBox.fromEnd === 0
                                    ? Appearance.font.pixelSize.normal
                                    : Appearance.font.pixelSize.small
                                color: lineBox.fromEnd === 0 ? "white" : "#c8c8c8"
                            }
                            // The translation is the point when it is on, so it
                            // gets the accent and the original steps down.
                            StyledText {
                                Layout.fillWidth: true
                                visible: String(lineBox.modelData.translation ?? "").length > 0
                                horizontalAlignment: Text.AlignHCenter
                                wrapMode: Text.WordWrap
                                text: lineBox.modelData.translation
                                font.pixelSize: Appearance.font.pixelSize.smaller
                                color: Appearance.colors.colPrimary
                            }
                        }
                    }
                }
            }
        }
    }
}
