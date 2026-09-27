// Desktop-icons layer-shell panel: one passive, non-exclusive PanelWindow per monitor.
// Content only loads while desktop.icons.enable is true.
import qs
import qs.services
import qs.modules.common
import QtQuick
import Quickshell
import Quickshell.Wayland

Scope {
    id: root

    Variants {
        model: Quickshell.screens

        PanelWindow {
            id: win
            required property ShellScreen modelData
            screen: modelData

            // Stays mapped until the exit animation finishes, so the remapped
            // surface restacks above the relocated wallpaper on unlock.
            visible: Config.options.desktop.icons.enable
                && (!GlobalStates.screenLocked || contentLoader.active)
                && !(GameMode.active && GameMode.fullscreenOn(modelData))
            color: "transparent"
            exclusionMode: ExclusionMode.Ignore
            exclusiveZone: 0
            WlrLayershell.namespace: "quickshell:desktopIcons"
            // Bottom, not Background: mpvpaper eats pointer events from any layer at or
            // below it. Still under normal windows, so only the bare desktop gets input.
            WlrLayershell.layer: WlrLayer.Bottom
            // OnDemand so the rename TextInput gets keys; only granted while hovered.
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand

            anchors {
                top: true
                bottom: true
                left: true
                right: true
            }

            // Cut holes for the background widgets (layer below) so they stay draggable.
            // `?.`: Variants nulls modelData on teardown while this binding is
            // still live, and forScreen("") is an empty list rather than a throw.
            readonly property var widgetRects: DesktopWidgetRegions.forScreen(win.modelData?.name ?? "")

            // A Region with no `item` is EMPTY, not "everything", so the base is explicit.
            Item {
                id: maskBase
                anchors.fill: parent
            }

            component WidgetHole: Region {
                property var rect: null
                intersection: Intersection.Subtract
                x: rect?.x ?? 0
                y: rect?.y ?? 0
                width: rect?.w ?? 0
                height: rect?.h ?? 0
            }

            WidgetHole { id: hole0; rect: win.widgetRects[0] ?? null }
            WidgetHole { id: hole1; rect: win.widgetRects[1] ?? null }
            WidgetHole { id: hole2; rect: win.widgetRects[2] ?? null }
            WidgetHole { id: hole3; rect: win.widgetRects[3] ?? null }

            mask: Region {
                item: maskBase
                regions: [hole0, hole1, hole2, hole3]
            }

            // Slide up + fade out on lock, mirroring the bar.
            Loader {
                id: contentLoader
                anchors.fill: parent
                anchors.topMargin: GlobalStates.screenLocked ? -36 : 0
                opacity: GlobalStates.screenLocked ? 0 : 1
                active: Config.options.desktop.icons.enable
                    && (!GlobalStates.screenLocked || _exitAnim.running)
                asynchronous: true
                sourceComponent: DesktopIconsContent {}
                Behavior on opacity {
                    NumberAnimation {
                        id: _exitAnim
                        duration: 240
                        easing.type: Easing.OutCubic
                    }
                }
                Behavior on anchors.topMargin {
                    NumberAnimation {
                        duration: 240
                        easing.type: Easing.OutCubic
                    }
                }
            }
        }
    }
}
