import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell.Io
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland

Scope { // Scope
    id: root
    property bool pinned: (Config.options && Config.options.osk) ? Config.options.osk.pinnedOnStartup : false

    component OskControlButton: GroupButton { // Pin button
        baseWidth: 40
        baseHeight: 40
        clickedWidth: baseWidth
        clickedHeight: baseHeight + 10
        buttonRadius: Appearance.rounding.normal
    }

    Timer {
        id: oskCloseTimer
        interval: 250
        repeat: false
    }

    Connections {
        target: GlobalStates
        function onOskOpenChanged() {
            if (!GlobalStates.oskOpen) {
                oskCloseTimer.start();
            }
        }
    }

    Loader {
        id: oskLoader
        active: GlobalStates.oskOpen || oskCloseTimer.running
        onActiveChanged: {
            if (!oskLoader.active) {
                Ydotool.releaseAllKeys();
            }
        }
        
        sourceComponent: PanelWindow { // Window
            id: oskRoot
            visible: GlobalStates.oskOpen && !GlobalStates.screenLocked

            function hide() {
                GlobalStates.oskOpen = false
            }
            exclusiveZone: root.pinned ? implicitHeight - Appearance.sizes.hyprlandGapsOut : 0
            implicitWidth: oskBackground.width + Appearance.sizes.elevationMargin * 2
            implicitHeight: oskBackground.height + Appearance.sizes.elevationMargin * 2
            WlrLayershell.namespace: "quickshell:osk"
            WlrLayershell.layer: WlrLayer.Overlay
            // Hyprland 0.49: Focus is always exclusive and setting this breaks mouse focus grab
            // WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
            color: "transparent"

            mask: Region {
                item: oskBackground
            }

            // Make it usable with other panels
            Component.onCompleted: {
                GlobalFocusGrab.addPersistent(oskRoot);
                GlobalStates.oskWindow = oskRoot;
            }
            Component.onDestruction: {
                GlobalFocusGrab.removePersistent(oskRoot);
                GlobalStates.oskWindow = null;
            }

            // Background
            StyledRectangularShadow {
                target: oskBackground
            }
            Rectangle {
                id: oskBackground
                anchors.centerIn: parent
                color: Appearance.colors.colLayer0
                radius: Appearance.rounding.windowRounding
                property real padding: 10
                implicitWidth: oskRowLayout.implicitWidth + padding * 2
                implicitHeight: oskRowLayout.implicitHeight + padding * 2

                opacity: 0
                transform: Translate {
                    id: oskTranslate
                    y: 80
                }

                states: [
                    State {
                        name: "visible"
                        when: oskRoot.visible
                        PropertyChanges { target: oskTranslate; y: 0 }
                        PropertyChanges { target: oskBackground; opacity: 1 }
                    },
                    State {
                        name: "hidden"
                        when: !oskRoot.visible
                        PropertyChanges { target: oskTranslate; y: 80 }
                        PropertyChanges { target: oskBackground; opacity: 0 }
                    }
                ]

                transitions: [
                    Transition {
                        from: "hidden"; to: "visible"
                        ParallelAnimation {
                            NumberAnimation { properties: "y"; duration: 250; easing.type: Easing.OutCubic }
                            NumberAnimation { properties: "opacity"; duration: 200; easing.type: Easing.OutCubic }
                        }
                    },
                    Transition {
                        from: "visible"; to: "hidden"
                        ParallelAnimation {
                            NumberAnimation { properties: "y"; duration: 220; easing.type: Easing.InCubic }
                            NumberAnimation { properties: "opacity"; duration: 180; easing.type: Easing.InCubic }
                        }
                    }
                ]

                Keys.onPressed: (event) => { // Esc to close
                    if (event.key === Qt.Key_Escape) {
                        oskRoot.hide()
                    }
                }

                RowLayout {
                    id: oskRowLayout
                    anchors.centerIn: parent
                    spacing: 5

                    ColumnLayout {
                        spacing: 8
                        Layout.alignment: Qt.AlignTop | Qt.AlignHCenter

                        PanelPositioner {
                            window: oskRoot
                            stateObject: Persistent.states.osk
                            defaultAlign: "bottom"
                            vertical: true
                            Layout.alignment: Qt.AlignHCenter
                        }

                        VerticalButtonGroup {
                            OskControlButton { // Pin button
                                toggled: root.pinned
                                downAction: () => root.pinned = !root.pinned
                                contentItem: MaterialSymbol {
                                    text: "keep"
                                    horizontalAlignment: Text.AlignHCenter
                                    iconSize: Appearance.font.pixelSize.larger
                                    color: root.pinned ? Appearance.m3colors.m3onPrimary : Appearance.colors.colOnLayer0
                                }
                            }
                            OskControlButton {
                                onClicked: () => {
                                    oskRoot.hide()
                                }
                                contentItem: MaterialSymbol {
                                    horizontalAlignment: Text.AlignHCenter
                                    text: "keyboard_hide"
                                    iconSize: Appearance.font.pixelSize.larger
                                }
                            }
                            OskControlButton {
                                toggled: GlobalStates.touchpadOpen
                                onClicked: () => GlobalStates.touchpadOpen = !GlobalStates.touchpadOpen
                                contentItem: MaterialSymbol {
                                    horizontalAlignment: Text.AlignHCenter
                                    text: "touchpad_mouse"
                                    iconSize: Appearance.font.pixelSize.larger
                                    color: GlobalStates.touchpadOpen ? Appearance.m3colors.m3onPrimary : Appearance.colors.colOnLayer0
                                }
                            }
                            // Settings — opens the keyboard-settings popup
                            // (repeat rate/delay, numlock, resolve-by-sym).
                            OskControlButton {
                                onClicked: () => GlobalStates.kbSettingsOpen = !GlobalStates.kbSettingsOpen
                                contentItem: MaterialSymbol {
                                    horizontalAlignment: Text.AlignHCenter
                                    text: "tune"
                                    iconSize: Appearance.font.pixelSize.larger
                                }
                            }

                            // ── System keyboard layout (XKB) ────────────────
                            // Below the pin/hide controls: one vertical chip per
                            // configured layout. Active chip = the layout
                            // Hyprland is using right now (live — re-highlights
                            // when Hyprland's activelayout event fires). Click
                            // to switch via `hyprctl switchxkblayout`.
                            Rectangle {
                                visible: KeyboardLayout.availableLayouts.length > 0
                                implicitWidth: 28
                                implicitHeight: 1
                                color: Appearance.colors.colOutlineVariant
                                Layout.topMargin: 6
                                Layout.bottomMargin: 6
                                Layout.alignment: Qt.AlignHCenter
                            }
                            Repeater {
                                model: KeyboardLayout.availableLayouts
                                delegate: Item {
                                    id: kbChip
                                    required property string modelData
                                    required property int index
                                    readonly property bool active: modelData === KeyboardLayout.detectedLayout
                                    readonly property string variant: KeyboardLayout.availableVariants[index] ?? ""

                                    implicitWidth: 40
                                    implicitHeight: kbChipLabel.implicitWidth + 14

                                    StyledText {
                                        id: kbChipLabel
                                        anchors.centerIn: parent
                                        rotation: -90
                                        text: kbChip.modelData.toUpperCase()
                                            + (kbChip.variant ? "·" + kbChip.variant : "")
                                        font.pixelSize: Appearance.font.pixelSize.small
                                        // Active = accent colour + bold; inactive = normal
                                        // foreground — both fully visible, no opacity dim.
                                        font.weight: kbChip.active ? Font.Bold : Font.Medium
                                        color: kbChip.active
                                            ? Appearance.colors.colPrimary
                                            : (kbChipHover.hovered
                                                ? Appearance.colors.colPrimary
                                                : Appearance.colors.colOnLayer0)
                                        Behavior on color { ColorAnimation { duration: 120 } }
                                    }
                                    HoverHandler { id: kbChipHover }
                                    TapHandler {
                                        // Left click → open the full picker.
                                        acceptedButtons: Qt.LeftButton
                                        onTapped: GlobalStates.kbPickerOpen = true
                                    }
                                    TapHandler {
                                        // Right click → context menu (Remove).
                                        acceptedButtons: Qt.RightButton
                                        onTapped: (eventPoint) => {
                                            const pt = kbChip.mapToItem(
                                                oskBackground,
                                                eventPoint.position.x,
                                                eventPoint.position.y)
                                            const label = kbChip.modelData.toUpperCase()
                                                + (kbChip.variant ? " (" + kbChip.variant + ")" : "")
                                            const idx = kbChip.index
                                            chipMenu.popup(pt.x, pt.y, [
                                                { icon: "delete", danger: true, label: qsTr("Remove ") + label, onTriggered: () => {
                                                    if (idx >= 0) KeyboardLayout.removeLayout(idx)
                                                }}
                                            ])
                                        }
                                    }
                                }
                            }
                        }
                    }
                    Rectangle {
                        Layout.topMargin: 20
                        Layout.bottomMargin: 20
                        Layout.fillHeight: true
                        implicitWidth: 1
                        color: Appearance.colors.colOutlineVariant
                    }
                    OskContent {
                        id: oskContent
                        Layout.fillWidth: true
                    }
                }

                // Right-click context menu for the left-side layout chips.
                // Overlays the OSK card; click-outside dismisses.
                PopupContextMenu { id: chipMenu }
            }

        }
    }

    IpcHandler {
        target: "osk"

        function toggle() {
            GlobalStates.oskOpen = !GlobalStates.oskOpen;
        }

        function close() {
            GlobalStates.oskOpen = false
        }

        function open() {
            GlobalStates.oskOpen = true
        }
    }

    GlobalShortcut {
        name: "oskToggle"
        description: "Toggles on screen keyboard on press"

        onPressed: {
            GlobalStates.oskOpen = !GlobalStates.oskOpen;
        }
    }

    GlobalShortcut {
        name: "oskOpen"
        description: "Opens on screen keyboard on press"

        onPressed: {
            GlobalStates.oskOpen = true
        }
    }

    GlobalShortcut {
        name: "oskClose"
        description: "Closes on screen keyboard on press"

        onPressed: {
            GlobalStates.oskOpen = false
        }
    }

}
