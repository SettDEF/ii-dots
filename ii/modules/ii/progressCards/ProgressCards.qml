pragma ComponentBehavior: Bound
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland

/**
 * Jobs in progress (services/Progress) as cards stacked at the bottom right of the focused screen.
 * New cards rise in, finished ones slide out and the rest glide into line. A click shows the output.
 */
Scope {
    id: root
    readonly property bool any: Progress.jobs.length > 0
    Timer { id: linger; interval: 400 }
    onAnyChanged: if (!any) linger.restart()

    LazyLoader {
        active: root.any || linger.running
        PanelWindow {
            screen: Quickshell.screens.find(s => s.name === Hyprland.focusedMonitor?.name) ?? Quickshell.screens[0]
            WlrLayershell.namespace: "quickshell:progress"
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
            exclusionMode: ExclusionMode.Ignore
            color: "transparent"
            anchors { right: true; bottom: true }
            margins { right: 14; bottom: 14 }
            // fixed size (a layer resized per frame stutters); only the cards take clicks
            implicitWidth: 380
            implicitHeight: 560
            mask: Region { item: list.contentItem }

            ListView {
                id: list
                anchors { fill: parent; margins: 10 }
                verticalLayoutDirection: ListView.BottomToTop
                spacing: 10
                interactive: false
                model: ScriptModel { values: Progress.jobs; objectProp: "id" }

                delegate: Item {
                    id: d
                    required property var modelData
                    width: list.width
                    height: card.implicitHeight
                    StyledRectangularShadow { target: card }
                    ProgressCard {
                        id: card
                        anchors.right: parent.right
                        job: d.modelData
                        onOpenRequested: Quickshell.execDetached(["/home/" + Quickshell.env("USER") + "/.local/bin/zash", "--", "less", "-R", "+F", `${Progress.dir}/${d.modelData.id}.log`])
                        onCloseRequested: d.modelData.state === "running" ? Progress.stop(d.modelData) : Progress.dismiss(d.modelData.id)
                    }
                }
                add: Transition {
                    NumberAnimation { property: "opacity"; from: 0; to: 1; duration: 220; easing.type: Easing.OutCubic }
                    NumberAnimation { property: "scale"; from: 0.92; to: 1; duration: 260; easing.type: Easing.OutBack }
                }
                remove: Transition {
                    NumberAnimation { property: "opacity"; to: 0; duration: 220 }
                    NumberAnimation { property: "x"; to: 60; duration: 260; easing.type: Easing.InCubic }
                }
                displaced: Transition {
                    NumberAnimation { properties: "x,y"; duration: 300; easing.type: Easing.OutCubic }
                }
            }
        }
    }
}
