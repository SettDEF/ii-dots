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
import Quickshell.Hyprland

/**
 * KeyboardLayoutPicker — full XKB-layout picker opened from the OSK chips.
 *  • lists every installed layout (and variant) from evdev.lst
 *  • live filter by code or name
 *  • click to switch (Hyprland adopts it via `hyprctl keyword` if new,
 *    then `switchxkblayout`)
 *  • Esc / click-outside dismisses
 */
Scope {
    id: root

    Loader {
        id: pickerLoader
        active: GlobalStates.kbPickerOpen

        sourceComponent: PanelWindow {
            id: win
            visible: GlobalStates.kbPickerOpen
            anchors { top: true; bottom: true; left: true; right: true }
            exclusiveZone: 0
            color: "transparent"
            WlrLayershell.namespace: "quickshell:kbPicker"
            WlrLayershell.layer: WlrLayer.Overlay
            // Required for the search TextInput to receive keys — without
            // this the layer surface doesn't get keyboard focus.
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand

            mask: Region { item: card }

            Component.onCompleted: GlobalFocusGrab.addDismissable(win)
            Component.onDestruction: GlobalFocusGrab.removeDismissable(win)
            Connections {
                target: GlobalFocusGrab
                function onDismissed() { GlobalStates.kbPickerOpen = false }
            }

            // Re-assert focus on the search input until it lands — the layer
            // surface + focus grab settle asynchronously, so one call loses
            // the race intermittently (same pattern as Nexus / overview).
            Timer {
                id: focusRetry
                running: true
                interval: 50
                repeat: true
                triggeredOnStart: true
                property int ticks: 0
                onTriggered: {
                    searchInput.forceActiveFocus()
                    ticks++
                    if ((searchInput.activeFocus && ticks >= 3) || ticks >= 14)
                        stop()
                }
            }

            // Filter live by query — matches the code OR the human name.
            property string query: ""
            readonly property var filtered: {
                const q = win.query.toLowerCase().trim()
                if (q === "") return KeyboardLayout.allLayouts
                return (KeyboardLayout.allLayouts ?? []).filter(e =>
                    (e.code || "").toLowerCase().indexOf(q) >= 0
                    || (e.name || "").toLowerCase().indexOf(q) >= 0)
            }

            StyledRectangularShadow { target: card }
            Rectangle {
                id: card
                // Sit ABOVE the on-screen keyboard, not centred (the OSK
                // anchors to the bottom of the screen, so a centred picker
                // ends up partly behind / overlapping it). 320 px of bottom
                // margin clears the OSK; the card grows upward from there.
                anchors.bottom: parent.bottom
                anchors.bottomMargin: 320
                anchors.horizontalCenter: parent.horizontalCenter
                implicitWidth: 540
                implicitHeight: 520
                radius: Appearance.rounding.windowRounding
                color: Appearance.colors.colLayer0
                border.width: 1
                border.color: Appearance.colors.colLayer0Border
                focus: win.visible

                Keys.onPressed: event => {
                    if (event.key === Qt.Key_Escape) {
                        GlobalStates.kbPickerOpen = false
                        event.accepted = true
                    }
                }

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 16
                    spacing: 12

                    // ── Header ─────────────────────────────────────────
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 10
                        MaterialSymbol {
                            text: "keyboard"
                            iconSize: Appearance.font.pixelSize.title
                            color: Appearance.colors.colOnLayer0
                        }
                        StyledText {
                            Layout.fillWidth: true
                            text: qsTr("Choose keyboard layout")
                            font.pixelSize: Appearance.font.pixelSize.large
                            font.weight: Font.Medium
                            color: Appearance.colors.colOnLayer0
                        }
                        StyledText {
                            text: (KeyboardLayout.allLayouts?.length ?? 0)
                                + " · " + qsTr("active: ")
                                + KeyboardLayout.effectiveLayout.toUpperCase()
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            color: Appearance.colors.colOnLayer0
                            opacity: 0.5
                        }
                    }

                    // ── Search ─────────────────────────────────────────
                    Rectangle {
                        Layout.fillWidth: true
                        implicitHeight: 38
                        radius: Appearance.rounding.small
                        color: Appearance.colors.colLayer1
                        border.width: 1
                        border.color: Appearance.colors.colLayer0Border

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 10
                            anchors.rightMargin: 10
                            spacing: 8

                            MaterialSymbol {
                                text: "search"
                                iconSize: Appearance.font.pixelSize.normal
                                color: Appearance.colors.colOnLayer0
                                opacity: 0.55
                            }
                            TextInput {
                                id: searchInput
                                Layout.fillWidth: true
                                clip: true
                                focus: true
                                font.pixelSize: Appearance.font.pixelSize.small
                                color: Appearance.colors.colOnLayer0
                                selectByMouse: true
                                onTextChanged: win.query = text
                                Keys.onEscapePressed: GlobalStates.kbPickerOpen = false
                            }
                            StyledText {
                                visible: searchInput.text === ""
                                anchors.verticalCenter: parent.verticalCenter
                                anchors.left: parent.left
                                anchors.leftMargin: 36
                                text: qsTr("Filter — code or name (de, dvorak, French...)")
                                color: Appearance.colors.colOnLayer0
                                opacity: 0.35
                                font.pixelSize: Appearance.font.pixelSize.small
                            }
                        }
                    }

                    // ── List ───────────────────────────────────────────
                    ListView {
                        id: list
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        clip: true
                        model: win.filtered
                        spacing: 1
                        boundsBehavior: Flickable.StopAtBounds
                        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

                        delegate: Rectangle {
                            id: row
                            required property var modelData
                            // Is this exact (layout, variant) combo currently
                            // present in Hyprland's kb_layout / kb_variant?
                            readonly property bool inConfig: {
                                const layouts = KeyboardLayout.availableLayouts
                                const variants = KeyboardLayout.availableVariants
                                for (let i = 0; i < layouts.length; i++) {
                                    if (layouts[i] === row.modelData.layout
                                        && (variants[i] || "") === row.modelData.variant)
                                        return true
                                }
                                return false
                            }
                            readonly property bool active: row.inConfig
                                && row.modelData.layout === KeyboardLayout.detectedLayout
                            width: list.width
                            implicitHeight: 36
                            radius: Appearance.rounding.small
                            color: hov.hovered ? Appearance.colors.colLayer1
                                : (row.active ? Qt.alpha(Appearance.colors.colPrimary, 0.12)
                                              : "transparent")
                            Behavior on color { ColorAnimation { duration: 100 } }

                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: 12
                                anchors.rightMargin: 12
                                spacing: 10

                                StyledText {
                                    text: row.modelData.code
                                    Layout.preferredWidth: 130
                                    font.family: Appearance.font.family.monospace
                                    font.pixelSize: Appearance.font.pixelSize.small
                                    color: row.active ? Appearance.colors.colPrimary
                                                      : Appearance.colors.colOnLayer0
                                    font.weight: row.active ? Font.Bold : Font.Medium
                                    elide: Text.ElideRight
                                }
                                // "missing" tag — visible for layouts NOT in
                                // your hypr kb_layout. Picking one runs
                                // setLayout() which appends it via
                                // `hyprctl keyword` (session-only).
                                Rectangle {
                                    visible: !row.inConfig
                                    implicitWidth: missingTagText.implicitWidth + 12
                                    implicitHeight: 18
                                    radius: 9
                                    color: Qt.alpha(Appearance.colors.colOnLayer0, 0.08)
                                    border.width: 1
                                    border.color: Qt.alpha(Appearance.colors.colOnLayer0, 0.18)
                                    StyledText {
                                        id: missingTagText
                                        anchors.centerIn: parent
                                        text: qsTr("missing")
                                        font.pixelSize: Appearance.font.pixelSize.smaller
                                        color: Appearance.colors.colOnLayer0
                                        opacity: 0.55
                                    }
                                }
                                StyledText {
                                    Layout.fillWidth: true
                                    text: row.modelData.name
                                    font.pixelSize: Appearance.font.pixelSize.small
                                    color: Appearance.colors.colOnLayer0
                                    opacity: 0.8
                                    elide: Text.ElideRight
                                }
                                MaterialSymbol {
                                    visible: row.active
                                    text: "check"
                                    iconSize: Appearance.font.pixelSize.small
                                    color: Appearance.colors.colPrimary
                                }
                            }

                            HoverHandler { id: hov; cursorShape: Qt.PointingHandCursor }
                            TapHandler {
                                onTapped: {
                                    KeyboardLayout.setLayout(row.modelData.layout, row.modelData.variant)
                                    GlobalStates.kbPickerOpen = false
                                }
                            }
                        }
                    }

                    // ── Footer ─────────────────────────────────────────
                    StyledText {
                        Layout.fillWidth: true
                        horizontalAlignment: Text.AlignHCenter
                        text: qsTr("Esc to close · session-only — add to hypr conf to persist")
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        color: Appearance.colors.colOnLayer0
                        opacity: 0.4
                    }
                }
            }
        }
    }
}
