// The confirm-or-it-comes-back dialog for turning a display off.
//
// Shown on EVERY screen that is still lit, via Variants over
// Quickshell.screens: a display Hyprland has disabled drops out of that list,
// so the dialog can never render only on the monitor that just went dark.
// That is the whole point — the question has to reach your eyes, and the shell
// cannot know which panel you are actually looking at.
//
// Nothing here is load-bearing on its own. If this window fails to appear, is
// covered by a fullscreen game, or is on a screen you are not looking at, the
// countdown in MonitorSafety still puts the display back by itself.
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

Scope {
    id: root

    // Escape hatch that does not need this window, a mouse, or a visible
    // screen — `qs -c ii ipc call monitors recover` from a TTY or a keybind.
    // MonitorManager.enableAll() existed but nothing ever called it, so the
    // documented last-resort recovery had no way to be invoked.
    IpcHandler {
        target: "monitors"

        function recover(): string {
            MonitorSafety.keep();          // stop any countdown fighting us
            MonitorManager.enableAll();
            return "enabling every connected monitor at preferred mode";
        }
        function undo(): string {
            const n = MonitorSafety.undo();
            return n.length > 0 ? ("re-enabled " + n) : "nothing was pending";
        }
        function keep(): string {
            if (!MonitorSafety.confirmPending) return "nothing was pending";
            const n = MonitorSafety.pendingName;
            MonitorSafety.keep();
            return "kept " + n + " off";
        }
        function status(): string {
            return MonitorSafety.confirmPending
                ? (MonitorSafety.pendingName + " off, reverting in "
                   + MonitorSafety.secondsLeft + "s")
                : (MonitorSafety.activeCount + " active monitor(s), nothing pending");
        }
    }

    Variants {
        model: Quickshell.screens

        PanelWindow {
            id: win
            required property var modelData
            screen: win.modelData

            visible: MonitorSafety.confirmPending
            color: "transparent"
            WlrLayershell.namespace: "quickshell:monitorSafety"
            WlrLayershell.layer: WlrLayer.Overlay
            // OnDemand, not Exclusive: this window exists on several screens at
            // once and an exclusive grab from each would fight over the seat.
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand
            exclusionMode: ExclusionMode.Ignore

            implicitWidth: card.implicitWidth + Appearance.sizes.elevationMargin * 2
            implicitHeight: card.implicitHeight + Appearance.sizes.elevationMargin * 2

            StyledRectangularShadow { target: card }

            Rectangle {
                id: card
                anchors.centerIn: parent
                implicitWidth: 380
                implicitHeight: col.implicitHeight + 32
                radius: Appearance.rounding.large
                color: Appearance.m3colors.m3surfaceContainerHigh
                border.width: 1
                border.color: Appearance.colors.colLayer0Border

                focus: win.visible
                Keys.onEscapePressed: event => { MonitorSafety.undo(); event.accepted = true }
                Keys.onReturnPressed: event => { MonitorSafety.keep(); event.accepted = true }

                ColumnLayout {
                    id: col
                    anchors { left: parent.left; right: parent.right; top: parent.top; margins: 16 }
                    spacing: 12

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 9
                        MaterialSymbol {
                            text: "desktop_access_disabled"
                            iconSize: 22
                            color: Appearance.m3colors.m3error
                        }
                        StyledText {
                            Layout.fillWidth: true
                            text: Translation.tr("Keep %1 turned off?").arg(MonitorSafety.pendingName)
                            font.pixelSize: Appearance.font.pixelSize.larger
                            font.bold: true
                            color: Appearance.colors.colOnLayer0
                            wrapMode: Text.WordWrap
                        }
                    }

                    StyledText {
                        Layout.fillWidth: true
                        text: Translation.tr("If you can read this, that display is off and the rest still work. Do nothing and it comes back on by itself.")
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        color: Appearance.colors.colSubtext
                        wrapMode: Text.WordWrap
                    }

                    // The countdown is the actual safety mechanism, so it is
                    // shown as a draining bar rather than a number you have to
                    // read — visible at a glance from across a desk.
                    ColumnLayout {
                        Layout.fillWidth: true
                        Layout.topMargin: 2
                        spacing: 5

                        StyledText {
                            text: Translation.tr("Turning back on in %1s").arg(MonitorSafety.secondsLeft)
                            font.pixelSize: Appearance.font.pixelSize.smallest
                            font.family: Appearance.font.family.monospace
                            color: Appearance.colors.colSubtext
                        }
                        Rectangle {
                            Layout.fillWidth: true
                            implicitHeight: 4
                            radius: 2
                            color: Appearance.colors.colLayer2
                            Rectangle {
                                anchors { left: parent.left; top: parent.top; bottom: parent.bottom }
                                radius: 2
                                width: parent.width * (MonitorSafety.revertSeconds > 0
                                    ? Math.max(0, MonitorSafety.secondsLeft / MonitorSafety.revertSeconds)
                                    : 0)
                                color: Appearance.colors.colPrimary
                                Behavior on width { NumberAnimation { duration: 950; easing.type: Easing.Linear } }
                            }
                        }
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        Layout.topMargin: 4
                        spacing: 8

                        Item { Layout.fillWidth: true }

                        // Undo first and styled as the calm default: the whole
                        // design assumes the person who needs this dialog is
                        // the one who made a mistake.
                        DialogButton {
                            buttonText: Translation.tr("Turn it back on")
                            onClicked: MonitorSafety.undo()
                        }
                        DialogButton {
                            buttonText: Translation.tr("Keep it off")
                            colBackground: Appearance.colors.colPrimary
                            colText: Appearance.colors.colOnPrimary
                            onClicked: MonitorSafety.keep()
                        }
                    }
                }
            }
        }
    }
}
