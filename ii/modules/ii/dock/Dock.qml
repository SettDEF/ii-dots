import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Controls
import QtQuick.Effects
import QtQuick.Layouts
import Quickshell.Io
import Quickshell
import Quickshell.Widgets
import Quickshell.Wayland
import Quickshell.Hyprland

Scope { // Scope
    id: root
    property bool pinned: Config.options?.dock.pinnedOnStartup ?? false

    // In the Scope, not the per-screen window: one handler, not one per monitor.
    // One floating window for the shell, not one per monitor. Loader-gated,
    // so nothing exists until a widget is opened and a second click on the
    // same tile destroys it again.
    Loader {
        active: DockWidgetPanel.widgetId.length > 0
        sourceComponent: DockWidgetWindow {}
    }

    IpcHandler {
        target: "dock"
        function editMode(): string {
            GlobalStates.dockEditMode = !GlobalStates.dockEditMode;
            return GlobalStates.dockEditMode ? "editing" : "done";
        }
        function toggle(): string {
            GlobalStates.dockOpen = !GlobalStates.dockOpen;
            return GlobalStates.dockOpen ? "shown" : "hidden";
        }
    }

    Variants {
        // For each monitor
        model: Quickshell.screens

        PanelWindow {
            id: dockRoot
            // Window
            required property var modelData
            screen: modelData
            visible: !GlobalStates.screenLocked

            // Detaches the dock from the screen edge. The window grows by the
            // same amount that dockBackground is pushed up, so everything
            // inside — the card AND the row — keeps its existing geometry and
            // simply sits higher. Growing the window WITHOUT the matching
            // bottom margin is what broke the layout previously.
            readonly property real floatGap: (Config.options?.dock.floating ?? false)
                ? (Config.options?.dock.floatingMargin ?? 8) : 0

            /*
             * Nothing on THIS screen, as opposed to nothing focused anywhere.
             *
             * ToplevelManager.activeToplevel is global, so a focused window on
             * one monitor hid the dock on every monitor — including one sitting
             * on an empty workspace with nothing to cover.
             */
            readonly property bool emptyHere: {
                const mon = (HyprlandData.monitors ?? []).find(m => m?.name === dockRoot.screen?.name);
                const wsId = mon?.activeWorkspace?.id;
                if (wsId === undefined || wsId === null) return false;
                return (HyprlandData.workspaceById?.[wsId]?.windows ?? 0) === 0;
            }

            property bool reveal: root.pinned || (Config.options?.dock.hoverToReveal && dockMouseArea.containsMouse) || dockApps.requestDockShow || dockMedia.requestDockShow || GlobalStates.dockEditMode || (!ToplevelManager.activeToplevel?.activated) || dockRoot.emptyHere || GlobalStates.dockOpen

            anchors {
                bottom: true
                left: true
                right: true
            }

            exclusiveZone: root.pinned ? implicitHeight - (Appearance.sizes.hyprlandGapsOut) - (Appearance.sizes.elevationMargin - Appearance.sizes.hyprlandGapsOut) : 0

            implicitWidth: dockBackground.implicitWidth
            WlrLayershell.namespace: "quickshell:dock"
            color: "transparent"

            implicitHeight: (Config.options?.dock.height ?? 70) + Appearance.sizes.elevationMargin
                + Appearance.sizes.hyprlandGapsOut + dockRoot.floatGap

            mask: Region {
                item: dockMouseArea
            }

            MouseArea {
                id: dockMouseArea
                height: parent.height
                anchors {
                    top: parent.top
                    topMargin: dockRoot.reveal ? 0 : Config.options?.dock.hoverToReveal ? (dockRoot.implicitHeight - Config.options.dock.hoverRegionHeight) : (dockRoot.implicitHeight + 1)
                    horizontalCenter: parent.horizontalCenter
                }
                implicitWidth: dockHoverRegion.implicitWidth + Appearance.sizes.elevationMargin * 2
                hoverEnabled: true

                Behavior on anchors.topMargin {
                    animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                }

                Item {
                    id: dockHoverRegion
                    anchors.fill: parent
                    implicitWidth: dockBackground.implicitWidth

                    Item { // Wrapper for the dock background
                        id: dockBackground
                        anchors {
                            top: parent.top
                            bottom: parent.bottom
                            bottomMargin: dockRoot.floatGap
                            horizontalCenter: parent.horizontalCenter
                        }

                        implicitWidth: dockRow.implicitWidth + 5 * 2
                        height: parent.height - Appearance.sizes.elevationMargin - Appearance.sizes.hyprlandGapsOut

                        StyledRectangularShadow {
                            target: dockVisualBackground
                        }
                        Rectangle { // The real rectangle that is visible
                            id: dockVisualBackground
                            visible: Config.options.dock.showBackground
                            property real margin: Appearance.sizes.elevationMargin
                            anchors.fill: parent
                            anchors.topMargin: Appearance.sizes.elevationMargin
                            anchors.bottomMargin: Appearance.sizes.hyprlandGapsOut
                            color: Appearance.colors.colLayer0
                            border.width: 1
                            border.color: Appearance.colors.colLayer0Border
                            radius: Appearance.rounding.large
                        }

                        MouseArea {
                            anchors.fill: dockVisualBackground
                            acceptedButtons: Qt.RightButton
                            onClicked: GlobalStates.dockEditMode = !GlobalStates.dockEditMode
                        }

                        RowLayout {
                            id: dockRow
                            anchors.top: parent.top
                            anchors.bottom: parent.bottom
                            anchors.horizontalCenter: parent.horizontalCenter
                            spacing: Config.options?.dock.spacing ?? 6
                            property real padding: 5

                            VerticalButtonGroup {
                                Layout.topMargin: Appearance.sizes.hyprlandGapsOut // why does this work
                                visible: Config.options.dock.showPinButton
                                GroupButton {
                                    // Pin button
                                    baseWidth: 35
                                    baseHeight: 35
                                    clickedWidth: baseWidth
                                    clickedHeight: baseHeight + 20
                                    buttonRadius: Appearance.rounding.normal
                                    toggled: root.pinned
                                    onClicked: root.pinned = !root.pinned
                                    contentItem: MaterialSymbol {
                                        text: "keep"
                                        horizontalAlignment: Text.AlignHCenter
                                        iconSize: Appearance.font.pixelSize.larger
                                        color: root.pinned ? Appearance.m3colors.m3onPrimary : Appearance.colors.colOnLayer0
                                    }
                                }
                            }
                            DockSeparator { visible: Config.options.dock.showPinButton }
                            DockApps {
                                id: dockApps
                                buttonPadding: dockRow.padding
                            }
                            // Hidden with the card: the card collapses to zero width
                            // with no track, which left two lines touching.
                            DockSeparator { visible: dockMedia.visible }
                            DockMedia {
                                id: dockMedia
                                visible: Config.options.dock.showMedia && dockMedia.hasTrack
                                Layout.fillHeight: true
                                Layout.topMargin: 12
                                Layout.bottomMargin: 8
                                buttonPadding: dockRow.padding
                            }
                            DockSeparator { visible: dockWidgets.count > 0 }
                            Repeater {
                                id: dockWidgets
                                model: DockWidgets.enabled
                                delegate: DockWidget {
                                    required property var modelData
                                    widgetId: modelData
                                }
                            }

                            DockSeparator { visible: Config.options.dock.showAppsButton }
                            DockButton {
                                visible: Config.options.dock.showAppsButton
                                Layout.fillHeight: true
                                onClicked: GlobalStates.overviewOpen = !GlobalStates.overviewOpen
                                topInset: Appearance.sizes.hyprlandGapsOut + dockRow.padding
                                bottomInset: Appearance.sizes.hyprlandGapsOut + dockRow.padding
                                contentItem: MaterialSymbol {
                                    anchors.fill: parent
                                    horizontalAlignment: Text.AlignHCenter
                                    font.pixelSize: parent.width / 2
                                    text: "apps"
                                    color: Appearance.colors.colOnLayer0
                                }
                            }
                        }

                        DockEditOverlay {
                            anchors.fill: dockVisualBackground
                        }
                    }
                }
            }

            DockTooltipPopup {
                anchorItem: dockHoverRegion
            }


            // Behind a Loader: it is a large panel that only exists while
            // editing, and an eagerly-built popup window costs memory for
            // nothing the rest of the time.
            Loader {
                active: GlobalStates.dockEditMode
                sourceComponent: DockEditPanel {
                    anchorItem: dockHoverRegion
                }
            }
        }
    }
}
