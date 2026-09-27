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
        // Clear of the screen's rounded corner, not just of its edge: at the
        // gap size the card's own corner sat inside the screen's and the two
        // curves read as a misalignment.
        margins.bottom: Appearance.rounding.screenRounding
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
            // One duration and one curve for everything this card does. It
            // used to fade at 220ms, rise at 260 and slide at 320, all on
            // OutCubic — three clocks for one gesture, which is what made it
            // look busy rather than quick.
            readonly property int animDuration: Appearance.animation.elementMoveFast.duration

            Behavior on x {
                NumberAnimation {
                    duration: hintCard.animDuration
                    easing.type: Easing.BezierSpline
                    easing.bezierCurve: Appearance.animationCurves.expressiveFastSpatial
                }
            }
            implicitWidth: cardCol.implicitWidth + 18
            implicitHeight: cardCol.implicitHeight + 14
            radius: Appearance.rounding.screenRounding - Appearance.sizes.hyprlandGapsOut + 1
            color: Appearance.colors.colLayer0
            border.width: 1
            border.color: Appearance.colors.colLayer0Border

            opacity: root.hintVisible ? 1 : 0
            Behavior on opacity {
                NumberAnimation {
                    duration: hintCard.animDuration
                    easing.type: Easing.BezierSpline
                    easing.bezierCurve: Appearance.animationCurves.expressiveFastSpatial
                }
            }

            transform: Translate {
                y: root.hintVisible ? 0 : 6
                Behavior on y {
                    NumberAnimation {
                        duration: hintCard.animDuration
                        easing.type: Easing.BezierSpline
                        easing.bezierCurve: Appearance.animationCurves.expressiveFastSpatial
                    }
                }
            }

            // Context label header
            ColumnLayout {
                id: cardCol
                anchors.centerIn: parent
                spacing: 7

                /// Width of the key column, i.e. the widest key group here.
                property real keyColumnWidth: 0
                function noteKeyWidth(w) {
                    if (w > cardCol.keyColumnWidth) cardCol.keyColumnWidth = w;
                }
                // Reset on a context change, or the column keeps the widest
                // value some earlier context happened to need and every later
                // card is padded out to it.
                Connections {
                    target: root
                    function onActiveContextChanged() { cardCol.keyColumnWidth = 0 }
                }

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

                // Keybind rows.
                //
                // Every row used to size its own key area, so "Super" and
                // "Super Tab" pushed their labels to different places and no
                // two lines started at the same x. The widest key group now
                // sets the column for all of them.
                Repeater {
                    model: root.currentKeybinds
                    delegate: RowLayout {
                        required property var modelData
                        spacing: 10

                        Row {
                            id: keyRow
                            spacing: 3
                            // Row's implicitWidth comes from its children, so
                            // widening the cell cannot feed back into it.
                            Layout.preferredWidth: Math.max(cardCol.keyColumnWidth, implicitWidth)
                            onImplicitWidthChanged: cardCol.noteKeyWidth(implicitWidth)
                            Component.onCompleted: cardCol.noteKeyWidth(implicitWidth)

                            Repeater {
                                model: modelData.keys
                                // The cheatsheet's key widget, dressed down.
                                // Its defaults draw a bright full-bleed border
                                // and a raised bottom edge, which works on the
                                // cheatsheet's own large surface and reads as a
                                // row of white boxes on a small dark card.
                                delegate: KeyboardKey {
                                    required property string modelData
                                    key: modelData
                                    pixelSize: Appearance.font.pixelSize.smallest
                                    borderColor: Appearance.colors.colOutlineVariant
                                    keyColor: Appearance.colors.colLayer2
                                    extraBottomBorderWidth: 0
                                    borderRadius: 6
                                    horizontalPadding: 5
                                    verticalPadding: 2
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
