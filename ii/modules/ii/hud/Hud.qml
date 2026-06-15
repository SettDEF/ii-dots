import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import Quickshell.Wayland

Scope {
    id: root

    // Full-screen transparent overlay — no window resizing, no layout recalc
    PanelWindow {
        id: panelWindow
        visible: hudLoader.active

        exclusiveZone: 0
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.layer: WlrLayer.Overlay   // Above bar so the connected look works
        color: "transparent"
        WlrLayershell.namespace: "quickshell:hud"
        // OnDemand keyboard focus — HUD hosts wifi password / rename text
        // inputs and won't receive key events without this.
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand

        // Full screen — so we can position HUD freely with absolute coordinates
        anchors { top: true; bottom: true; left: true; right: true }

        // Limit the layer-shell input region to just the HUD card. Mouse
        // hover and clicks outside that area pass through to whatever is
        // beneath (bar, dock, windows). Click-outside dismissal is handled
        // by GlobalFocusGrab below.
        mask: Region {
            item: hudLoader
            Region { item: subTabTrayHud }
        }

        onVisibleChanged: {
            if (visible)  GlobalFocusGrab.addDismissable(panelWindow)
            else          GlobalFocusGrab.removeDismissable(panelWindow)
        }
        Component.onDestruction: GlobalFocusGrab.removeDismissable(panelWindow)
        Connections {
            target: GlobalFocusGrab
            function onDismissed() { GlobalStates.hudOpen = false }
        }

        // When the active tab has sub-tabs, the HUD card drops by
        // `subTabGap` to clear room for the blob sub-tab tray, which
        // sits in that gap right below the bar.
        // Every main group has two sub-tabs, so the tray is always present.
        readonly property bool subTabsPresent: true
        readonly property int subTabGap: 58

        Loader {
            id: hudLoader
            // Stays active until close animation finishes (via unloadTimer)
            active: GlobalStates.hudOpen

            anchors {
                top: parent.top
                horizontalCenter: parent.horizontalCenter
                // Overlap the bar by `notchR` px so the bar shows through
                // the HUD's top concave bites — that's what creates the
                // "bar dips into the HUD" look at the corners.
                topMargin: Appearance.sizes.baseBarHeight
                           + (Config.options.bar.cornerStyle === 1 ? Appearance.sizes.hyprlandGapsOut : 0)
                           - 10
                           + (panelWindow.subTabsPresent ? panelWindow.subTabGap : 0)
            }
            Behavior on anchors.topMargin {
                NumberAnimation { duration: 240; easing.type: Easing.OutCubic }
            }
            // Scale with monitor: ~70 % of usable bar width on smaller
            // displays, capped so it doesn't stretch absurdly wide on
            // ultrawide / 4K screens. Floor at 760 px so it stays usable
            // on smaller monitors.
            width: {
                const usable = parent.width - (Config.options.bar.cornerStyle === 1 ? Appearance.sizes.hyprlandGapsOut * 2 : 0)
                return Math.max(760, Math.min(usable * 0.7, 1320))
            }

            sourceComponent: Item {
                id: hudPanel
                implicitHeight: hudContent.implicitHeight
                implicitWidth:  hudLoader.width

                property real enterP: 0

                // Animate enterP 0→1 on open
                NumberAnimation {
                    id: enterAnim
                    target: hudPanel; property: "enterP"
                    from: 0; to: 1
                    duration: 320; easing.type: Easing.OutCubic
                    running: false
                }
                // Animate enterP 1→0 on close, then unload
                NumberAnimation {
                    id: exitAnim
                    target: hudPanel; property: "enterP"
                    from: 1; to: 0
                    duration: 200; easing.type: Easing.InCubic
                    running: false
                    onFinished: hudLoader.active = false
                }

                Connections {
                    target: GlobalStates
                    function onHudOpenChanged() {
                        if (!GlobalStates.hudOpen) exitAnim.restart()
                    }
                }
                // Hold the fade-in until the content layout has settled —
                // otherwise the HUD flashes at a stale (too-tall) size and
                // visibly snaps down. It enters already at the right size.
                Connections {
                    target: hudContent
                    function onReadyChanged() {
                        if (hudContent.ready) enterAnim.restart()
                    }
                }

                Component.onCompleted: hudPanel.enterP = 0

                opacity: hudPanel.enterP
                transform: [
                    Scale {
                        xScale: 0.96 + hudPanel.enterP * 0.04
                        yScale: 0.96 + hudPanel.enterP * 0.04
                        origin.x: hudPanel.implicitWidth / 2
                        origin.y: 0
                    },
                    Translate { y: (1 - hudPanel.enterP) * -14 }
                ]

                HudContent {
                    id: hudContent
                    anchors { left: parent.left; right: parent.right; top: parent.top }
                    // Never let the HUD grow past the screen: cap the page
                    // area to the space between the bar and the bottom edge.
                    maxContentHeight: panelWindow.height
                        - hudLoader.anchors.topMargin - 56
                }
            }
        }

        // ── HUD sub-tab tray ─────────────────────────────────────────
        // Rendered in the HUD window itself (topmost layer) and AFTER
        // hudLoader, so it draws OVER the HUD card — the tray expands
        // down out of the bar, on top of the HUD. State lives in
        // GlobalStates, independent of the lazily-loaded HUD content.
        Item {
            id: subTabTrayHud
            anchors.horizontalCenter: parent.horizontalCenter
            // Sit flush under the bar. (Was a full bar-height too low —
            // moved up by baseBarHeight; -4 keeps a tiny overlap so the
            // top edge tucks under the bar with no seam.)
            y: -4
            width: 480

            // 7 pages → 3 groups. The tray shows the pages of the active
            // group; tapping one jumps hudActiveTab to that page.
            //   Home   = {Dashboard 0, Essentials 6, Screen Time 5}
            //   System = {Performance 1, Gaming 2}     (page 1 was "Essentials")
            //   Hub    = {Media 4, Settings 3}
            readonly property int activePage: GlobalStates.hudActiveTab
            readonly property int group: (activePage === 0 || activePage === 5 || activePage === 6) ? 0
                                       : (activePage === 1 || activePage === 2) ? 1 : 2
            readonly property var groupPages: [[0, 6, 5], [1, 2], [4, 3]]
            readonly property bool hasSub: GlobalStates.hudOpen
            height: hasSub ? 60 : 0

            readonly property var subTabModel: {
                if (group === 0) return [
                    { id: "0", icon: "dashboard",  label: "Dashboard"   },
                    { id: "1", icon: "tune",       label: "Essentials"  },
                    { id: "2", icon: "timelapse",  label: "Screen Time" },
                ]
                if (group === 1) return [
                    { id: "0", icon: "monitoring",     label: "Performance" },
                    { id: "1", icon: "sports_esports", label: "Gaming"      },
                ]
                return [
                    { id: "0", icon: "music_note", label: "Media"    },
                    { id: "1", icon: "settings",   label: "Settings" },
                ]
            }
            // Sub-tab index = position of activePage within groupPages[group].
            // indexOf handles 2 or 3 entries uniformly; Home now has 3.
            readonly property int subTabIndex: Math.max(0, groupPages[group].indexOf(activePage))
            function applySubTab(i) {
                GlobalStates.hudActiveTab = groupPages[group][i]
            }

            Loader {
                id: subTabTrayLoader
                anchors.fill: parent
                active: subTabTrayHud.hasSub
                source: Qt.resolvedUrl("SubTabTray.qml")
                opacity: subTabTrayHud.hasSub ? 1 : 0
                Behavior on opacity { NumberAnimation { duration: 200 } }
                onLoaded: {
                    item.tabsModel = Qt.binding(() => subTabTrayHud.subTabModel)
                    item.currentIndex = Qt.binding(() => subTabTrayHud.subTabIndex)
                }
                Connections {
                    target: subTabTrayLoader.item
                    ignoreUnknownSignals: true
                    function onSelected(index) { subTabTrayHud.applySubTab(index) }
                }
            }

            // Fallback plain pill row if the blob plugin failed to load.
            PillTabBar {
                visible: subTabTrayLoader.status === Loader.Error && subTabTrayHud.hasSub
                anchors.horizontalCenter: parent.horizontalCenter
                y: 8
                iconOnly: true
                tabs: subTabTrayHud.subTabModel
                current: String(subTabTrayHud.subTabIndex)
                onTabSelected: id => subTabTrayHud.applySubTab(parseInt(id))
            }
        }
    }

    // IpcHandler + GlobalShortcut moved to panelFamilies/Shortcuts.qml so they
    // stay registered while this panel is unloaded by LazyPanelLoader.
}
