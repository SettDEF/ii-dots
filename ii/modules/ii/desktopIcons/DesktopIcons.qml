// Desktop-icons layer-shell panel.
//
// One PanelWindow per monitor on WlrLayer.Background — above the wallpaper
// (which is on the same layer but added earlier so paints under), below
// any normal window. Doesn't request keyboard focus and doesn't claim an
// exclusion zone, so it behaves like a passive overlay on the desktop.
//
// The content (DesktopIconsContent) only inflates while
// Config.options.desktop.icons.enable is true — toggle it off and the
// FolderListModel + delegates tear down completely.
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

            // Stays visible during the exit animation; the inner Loader
            // fades + slides up. We only un-map the layer surface once
            // the animation has finished (contentLoader.active flips
            // false), which both gives the bar-like exit AND lets the
            // freshly-remapped surface restack above the relocated
            // wallpaper on unlock.
            visible: Config.options.desktop.icons.enable
                && (!GlobalStates.screenLocked || contentLoader.active)
            color: "transparent"
            exclusionMode: ExclusionMode.Ignore
            exclusiveZone: 0
            WlrLayershell.namespace: "quickshell:desktopIcons"
            // Bottom (not Background) so we sit above the wallpaper /
            // mpvpaper surfaces — mpvpaper's mpv binding eats pointer
            // events from any layer at-or-below it, killing icon clicks.
            // Bottom is still below normal windows, so the surface only
            // receives events on the empty (non-windowed) desktop area —
            // same behaviour as KDE's Folder View on Plasma 6.
            WlrLayershell.layer: WlrLayer.Bottom
            // OnDemand keyboard focus — needed so the rename TextInput
            // can actually receive characters when the dialog opens.
            // The compositor only grants focus while the cursor is over
            // the surface, so it doesn't steal from real windows.
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand

            anchors {
                top: true
                bottom: true
                left: true
                right: true
            }

            // Everything except the background widgets, which live on the layer
            // below. Without this the empty-space handler here takes every press
            // and those widgets can never be dragged. Four slots covers the
            // widgets anyone actually enables at once; extras keep working, they
            // just stay uncuttable.
            readonly property var widgetRects: DesktopWidgetRegions.forScreen(win.modelData.name)

            // The base area the mask starts from. A Region with no `item` is
            // EMPTY, not "everything" — see LayoutOsd's maskHidden — so the
            // whole-surface base has to be given explicitly.
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

            // Animate up + fade out on lock — mirrors the bar's exit
            // transition. The Loader stays active during the animation
            // so the content can fade gracefully; we tear it down on
            // the next animation finish.
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
