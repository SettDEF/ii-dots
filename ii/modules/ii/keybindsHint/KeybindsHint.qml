pragma ComponentBehavior: Bound
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland

Scope {
    id: root

    readonly property var contextMap: ({
        "shelf": [
            { keys: ["Super", "⌫"],          label: qsTr("Close shelf")           },
            { keys: ["Super", "F1"],          label: qsTr("Files tab")             },
            { keys: ["Super", "F2"],          label: qsTr("Battle tab")           },
            { keys: ["Super", "F3"],          label: qsTr("Media tab")             },
            { keys: ["Super", "Shift", "P"],  label: qsTr("Play / pause")          },
            { keys: ["Super", "Shift", "N"],  label: qsTr("Next track")            },
            { keys: ["Super", "Shift", "B"],  label: qsTr("Previous track")        },
            { keys: ["Super", "]"],           label: qsTr("Next player")           },
            { keys: ["Super", "["],           label: qsTr("Previous player")       },
        ],
        "cornerPopup": [
            { keys: ["Super", "`"],           label: qsTr("Close")                 },
            { keys: ["Super", "]"],           label: qsTr("Next player")           },
            { keys: ["Super", "["],           label: qsTr("Previous player")       },
            { keys: ["Super", "Shift", "P"],  label: qsTr("Play / pause")          },
            { keys: ["Super", "Shift", "N"],  label: qsTr("Next track")            },
            { keys: ["Super", "Shift", "B"],  label: qsTr("Previous track")        },
            { keys: ["scroll ↑↓"],            label: qsTr("Switch player")         },
            { keys: ["Super", "M"],           label: qsTr("Media controls")        },
        ],
        "mediaControls": [
            { keys: ["Super", "M"],           label: qsTr("Close media controls")  },
            { keys: ["Super", "Shift", "P"],  label: qsTr("Play / pause")          },
            { keys: ["Super", "Shift", "N"],  label: qsTr("Next track")            },
            { keys: ["Super", "Shift", "B"],  label: qsTr("Previous track")        },
            { keys: ["Super", "]"],           label: qsTr("Next player")           },
            { keys: ["Super", "["],           label: qsTr("Previous player")       },
            { keys: ["Super", "⌫"],          label: qsTr("Shelf")                 },
        ],
        "sidebarRight": [
            { keys: ["Super", "N"],           label: qsTr("Close sidebar")         },
            { keys: ["Super", "A"],           label: qsTr("Left sidebar")          },
            { keys: ["Super", "M"],           label: qsTr("Media controls")        },
            { keys: ["Super", "/"],           label: qsTr("Cheatsheet")            },
            { keys: ["Super", "⌫"],          label: qsTr("Shelf")                 },
        ],
        "sidebarLeft": [
            { keys: ["Super", "A"],           label: qsTr("Close sidebar")         },
            { keys: ["Ctrl", "O"],            label: qsTr("Toggle wide mode")      },
            { keys: ["Ctrl", "D"],            label: qsTr("Detach / attach")       },
            { keys: ["Ctrl", "P"],            label: qsTr("Pin sidebar")           },
            { keys: ["Super", "N"],           label: qsTr("Right sidebar")         },
            { keys: ["Super", "Tab"],         label: qsTr("Overview")              },
        ],
        "overview": [
            { keys: ["Super"],                label: qsTr("Close overview")        },
            { keys: ["Super", "Tab"],         label: qsTr("Workspaces view")       },
            { keys: ["Super", "V"],           label: qsTr("Clipboard history")     },
            { keys: ["Super", "."],           label: qsTr("Emoji picker")          },
            { keys: ["Esc"],                  label: qsTr("Close")                 },
            { keys: ["←", "→"],              label: qsTr("Navigate workspaces")   },
        ],
        "cheatsheet": [
            { keys: ["Super", "/"],           label: qsTr("Close cheatsheet")      },
            { keys: ["Ctrl", "Tab"],          label: qsTr("Next tab")              },
            { keys: ["Ctrl", "Shift", "Tab"], label: qsTr("Previous tab")          },
            { keys: ["Esc"],                  label: qsTr("Close")                 },
        ],
        "wallpaperSelector": [
            { keys: ["Ctrl", "Super", "T"],     label: qsTr("Close selector")      },
            { keys: ["Ctrl", "Super+Alt", "T"], label: qsTr("Random wallpaper")    },
        ],
        "session": [
            { keys: ["Ctrl+Alt", "Del"],      label: qsTr("Close session menu")    },
            { keys: ["Esc"],                  label: qsTr("Close")                 },
        ],
        "default": [
            { keys: ["Super"],                label: qsTr("Search")                },
            { keys: ["Super", "Tab"],         label: qsTr("Overview")              },
            { keys: ["Super", "`"],           label: qsTr("Media popup")           },
            { keys: ["Super", "⌫"],          label: qsTr("Shelf")                 },
            { keys: ["Super", "N"],           label: qsTr("Right sidebar")         },
            { keys: ["Super", "A"],           label: qsTr("Left sidebar")          },
            { keys: ["Super", "M"],           label: qsTr("Media controls")        },
            { keys: ["Super", "Shift", "P"],  label: qsTr("Play / pause")          },
            { keys: ["Super", "/"],           label: qsTr("Cheatsheet")            },
            { keys: ["Super", "Shift", "S"],  label: qsTr("Screen snip")           },
        ],
    })

    readonly property string activeContext: {
        if (GlobalStates.shelfOpen)           return "shelf"
        if (GlobalStates.cornerPopupOpen)     return "cornerPopup"
        if (GlobalStates.mediaControlsOpen)   return "mediaControls"
        if (GlobalStates.sidebarRightOpen)    return "sidebarRight"
        if (GlobalStates.sidebarLeftOpen)     return "sidebarLeft"
        if (GlobalStates.overviewOpen || GlobalStates.searchOpen) return "overview"
        if (GlobalStates.wallpaperSelectorOpen) return "wallpaperSelector"
        if (GlobalStates.sessionOpen)         return "session"
        return "default"
    }

    readonly property var currentKeybinds: contextMap[activeContext] ?? contextMap["default"]

    property bool hintVisible: false
    // Snap to right when left sidebar is open to avoid overlap
    readonly property bool snapRight: GlobalStates.sidebarLeftOpen

    // Smart show: per-context cooldown so same hint doesn't repeat within 60s
    property var lastShownAt: ({})

    onActiveContextChanged: {
        if (activeContext === "default") {
            hideTimer.stop()
            hintVisible = false
            return
        }
        const now = Date.now()
        const last = lastShownAt[activeContext] ?? 0
        if (now - last < 60000) return   // cooldown: skip if shown recently
        lastShownAt[activeContext] = now
        hintVisible = true
        hideTimer.restart()
    }

    Timer {
        id: hideTimer
        interval: 3500
        repeat: false
        onTriggered: root.hintVisible = false
    }

    PanelWindow {
        id: win
        visible: root.hintVisible || hintCard.opacity > 0
        exclusionMode: ExclusionMode.Ignore
        exclusiveZone: 0
        color: "transparent"
        WlrLayershell.namespace: "quickshell:keybindsHint"

        anchors.bottom: true
        anchors.left: true
        anchors.right: true
        margins.bottom: Appearance.sizes.hyprlandGapsOut
        implicitHeight: hintCard.implicitHeight

        mask: Region { item: hintCard }

        HoverHandler {
            onHoveredChanged: {
                if (hovered) hideTimer.stop()
                else if (root.hintVisible) hideTimer.restart()
            }
        }

        Rectangle {
            id: hintCard
            y: 0
            // Slide between left and right edge
            x: root.snapRight
                ? parent.width - width - Appearance.sizes.hyprlandGapsOut
                : Appearance.sizes.hyprlandGapsOut
            Behavior on x { NumberAnimation { duration: 320; easing.type: Easing.OutCubic } }
            implicitWidth: cardCol.implicitWidth + 18
            implicitHeight: cardCol.implicitHeight + 14
            radius: Appearance.rounding.screenRounding - Appearance.sizes.hyprlandGapsOut + 1
            color: Appearance.colors.colLayer0
            border.width: 1
            border.color: Appearance.colors.colLayer0Border

            opacity: root.hintVisible ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }

            transform: Translate {
                y: root.hintVisible ? 0 : 8
                Behavior on y { NumberAnimation { duration: 260; easing.type: Easing.OutCubic } }
            }

            // Context label header
            ColumnLayout {
                id: cardCol
                anchors.centerIn: parent
                spacing: 7

                // Context title
                StyledText {
                    text: {
                        const map = {
                            "shelf": qsTr("Shelf"),
                            "cornerPopup": qsTr("Media popup"),
                            "mediaControls": qsTr("Media controls"),
                            "sidebarRight": qsTr("Right sidebar"),
                            "sidebarLeft": qsTr("Left sidebar"),
                            "overview": qsTr("Overview"),
                            "cheatsheet": qsTr("Cheatsheet"),
                            "wallpaperSelector": qsTr("Wallpaper selector"),
                            "session": qsTr("Session"),
                            "default": qsTr("Shortcuts"),
                        }
                        return map[root.activeContext] ?? qsTr("Shortcuts")
                    }
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    font.weight: Font.Medium
                    color: Appearance.colors.colOnLayer0
                    opacity: 0.5
                    Layout.bottomMargin: 1
                }

                // Divider
                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: 1
                    color: Appearance.colors.colOutlineVariant
                    opacity: 0.5
                }

                // Keybind rows
                Repeater {
                    model: root.currentKeybinds
                    delegate: RowLayout {
                        required property var modelData
                        spacing: 10

                        // Key chips
                        Row {
                            spacing: 3
                            Repeater {
                                model: modelData.keys
                                delegate: Rectangle {
                                    required property string modelData
                                    implicitWidth: keyLabel.implicitWidth + 10
                                    implicitHeight: keyLabel.implicitHeight + 5
                                    radius: Appearance.rounding.small
                                    color: Appearance.colors.colLayer2
                                    border.width: 1
                                    border.color: Appearance.colors.colOutlineVariant

                                    StyledText {
                                        id: keyLabel
                                        anchors.centerIn: parent
                                        text: modelData
                                        font.pixelSize: Appearance.font.pixelSize.smallest
                                        font.weight: Font.Medium
                                        color: Appearance.colors.colOnLayer0
                                    }
                                }
                            }
                        }

                        StyledText {
                            text: modelData.label
                            font.pixelSize: Appearance.font.pixelSize.smallest
                            color: Appearance.colors.colSubtext
                            Layout.fillWidth: true
                        }
                    }
                }
            }
        }
    }
}
