import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Wayland

LazyLoader {
    id: root

    property Item hoverTarget
    default property Item contentItem
    property real popupBackgroundMargin: 0

    // Hover-out hysteresis + cross-popup exclusion.
    //   • _hovered: cursor is over our target right now.
    //   • _graceActive: short grace window after the cursor leaves so a
    //     1-frame jitter doesn't unload & recreate the layer surface.
    //   • Cross-popup: if ANOTHER StyledPopup is currently hovered,
    //     drop the grace immediately so we don't double-render with it.
    readonly property bool _hovered: hoverTarget && hoverTarget.containsMouse
    property bool _graceActive: false
    active: _hovered || _graceActive
    on_HoveredChanged: {
        if (_hovered) {
            _graceActive = false
            StyledPopupRegistry.claim(root)
        } else {
            _graceActive = true
            graceTick.restart()
        }
    }
    property QtObject graceTick: Timer {
        interval: 70
        repeat: false
        onTriggered: if (!root._hovered) root._graceActive = false
    }
    Connections {
        target: StyledPopupRegistry
        function onCurrentChanged() {
            if (StyledPopupRegistry.current !== root && !root._hovered)
                root._graceActive = false
        }
    }

    component: PanelWindow {
        id: popupWindow
        color: "transparent"

        anchors.left: !Config.options.bar.vertical || (Config.options.bar.vertical && !Config.options.bar.bottom)
        anchors.right: Config.options.bar.vertical && Config.options.bar.bottom
        anchors.top: Config.options.bar.vertical || (!Config.options.bar.vertical && !Config.options.bar.bottom)
        anchors.bottom: !Config.options.bar.vertical && Config.options.bar.bottom

        implicitWidth: popupBackground.implicitWidth + Appearance.sizes.elevationMargin * 2 + root.popupBackgroundMargin
        implicitHeight: popupBackground.implicitHeight + Appearance.sizes.elevationMargin * 2 + root.popupBackgroundMargin

        mask: Region {
            item: popupBackground
        }

        exclusionMode: ExclusionMode.Ignore
        exclusiveZone: 0
        // Centred on the hover target, then clamped so no popup can leave the
        // monitor. Without the clamp a wide popup near an edge is simply cut
        // off — there is no repositioning anywhere else in this path.
        margins {
            left: {
                if (Config.options.bar.vertical) return Appearance.sizes.verticalBarWidth;
                const centred = root.QsWindow?.mapFromItem(
                    root.hoverTarget,
                    (root.hoverTarget.width - popupBackground.implicitWidth) / 2, 0
                ).x ?? 0;
                const room = ScreenFit.logicalWidth(popupWindow) - popupWindow.implicitWidth;
                return Math.max(0, Math.min(centred, room));
            }
            top: {
                if (!Config.options.bar.vertical) return Appearance.sizes.barHeight;
                const centred = root.QsWindow?.mapFromItem(
                    root.hoverTarget,
                    (root.hoverTarget.height - popupBackground.implicitHeight) / 2, 0
                ).y ?? 0;
                const room = ScreenFit.logicalHeight(popupWindow) - popupWindow.implicitHeight;
                return Math.max(0, Math.min(centred, room));
            }
            right: Appearance.sizes.verticalBarWidth
            bottom: Appearance.sizes.barHeight
        }
        WlrLayershell.namespace: "quickshell:popup"
        WlrLayershell.layer: WlrLayer.Overlay
        // No keyboard focus on hover tooltips — the workspace rename
        // TextInput lives inline in Workspaces.qml (hosted by Bar), not
        // in this popup. Requesting focus here caused every hover to do
        // a focus-grab round-trip with Hyprland → visible lag/flicker.

        StyledRectangularShadow {
            target: popupBackground
        }

        Rectangle {
            id: popupBackground
            readonly property real margin: 10
            anchors {
                fill: parent
                leftMargin: Appearance.sizes.elevationMargin + root.popupBackgroundMargin * (!popupWindow.anchors.left)
                rightMargin: Appearance.sizes.elevationMargin + root.popupBackgroundMargin * (!popupWindow.anchors.right)
                topMargin: Appearance.sizes.elevationMargin + root.popupBackgroundMargin * (!popupWindow.anchors.top)
                bottomMargin: Appearance.sizes.elevationMargin + root.popupBackgroundMargin * (!popupWindow.anchors.bottom)
            }
            implicitWidth: root.contentItem.implicitWidth + margin * 2
            implicitHeight: root.contentItem.implicitHeight + margin * 2
            color: Appearance.m3colors.m3surfaceContainer
            radius: Appearance.rounding.small
            children: [root.contentItem]

            border.width: 1
            border.color: Appearance.colors.colLayer0Border
        }
    }
}
