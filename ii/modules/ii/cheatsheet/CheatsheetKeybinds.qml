pragma ComponentBehavior: Bound

import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts

Item {
    id: root
    readonly property var keybinds: HyprlandKeybinds.keybinds
    property real spacing: 20
    property real titleSpacing: 7
    property real padding: 4
    implicitWidth: contentCol.implicitWidth + padding * 2
    implicitHeight: contentCol.implicitHeight + padding * 2
    // Excellent symbol explaination and source :
    // http://xahlee.info/comp/unicode_computing_symbols.html
    // https://www.nerdfonts.com/cheat-sheet
    property var macSymbolMap: ({
        "Ctrl": "󰘴",
        "Alt": "󰘵",
        "Shift": "󰘶",
        "Space": "󱁐",
        "Tab": "↹",
        "Equal": "󰇼",
        "Minus": "",
        "Print": "",
        "BackSpace": "󰭜",
        "Delete": "⌦",
        "Return": "󰌑",
        "Period": ".",
        "Escape": "⎋"
      })
    property var functionSymbolMap: ({
        "F1":  "󱊫",
        "F2":  "󱊬",
        "F3":  "󱊭",
        "F4":  "󱊮",
        "F5":  "󱊯",
        "F6":  "󱊰",
        "F7":  "󱊱",
        "F8":  "󱊲",
        "F9":  "󱊳",
        "F10": "󱊴",
        "F11": "󱊵",
        "F12": "󱊶",
    })

    property var mouseSymbolMap: ({
        "mouse_up": "󱕐",
        "mouse_down": "󱕑",
        "mouse:272": "L󰍽",
        "mouse:273": "R󰍽",
        "Scroll ↑/↓": "󱕒",
        "Page_↑/↓": "⇞/⇟",
    })

    property var keyBlacklist: ["Super_L"]
    property var keySubstitutions: Object.assign({
        "Super": "",
        "mouse_up": "Scroll ↓",    // ikr, weird
        "mouse_down": "Scroll ↑",  // trust me bro
        "mouse:272": "LMB",
        "mouse:273": "RMB",
        "mouse:275": "MouseBack",
        "Slash": "/",
        "Hash": "#",
        "Return": "Enter",
        // "Shift": "",
      },
      !!Config.options.cheatsheet.superKey ? {
          "Super": Config.options.cheatsheet.superKey,
      }: {},
      Config.options.cheatsheet.useMacSymbol ? macSymbolMap : {},
      Config.options.cheatsheet.useFnSymbol ? functionSymbolMap : {},
      Config.options.cheatsheet.useMouseSymbol ? mouseSymbolMap : {},
    )

    // Layout-aware: resolve a raw key (notably `code:NN`) to the label of
    // the active/selected keyboard layout, then apply the substitutions.
    function displayKey(raw) {
        const resolved = KeyboardLayout.resolveKey(raw)
        return keySubstitutions[resolved] || resolved
    }

    Column {
        id: contentCol
        anchors.centerIn: parent
        spacing: 14

        // ── Keyboard-layout badge ─────────────────────────────────────
        // Click to cycle: Auto → each configured layout → Auto.
        Rectangle {
            id: layoutChip
            readonly property bool switchable: KeyboardLayout.availableLayouts.length > 1
            readonly property int layoutIndex: KeyboardLayout.availableLayouts.indexOf(KeyboardLayout.effectiveLayout)
            readonly property string variantSuffix: (layoutIndex >= 0
                && KeyboardLayout.availableVariants[layoutIndex])
                ? " (" + KeyboardLayout.availableVariants[layoutIndex] + ")" : ""
            implicitWidth: chipRow.implicitWidth + 22
            implicitHeight: chipRow.implicitHeight + 12
            radius: Appearance.rounding.full
            color: chipArea.containsMouse && layoutChip.switchable
                ? Appearance.colors.colLayer2 : Appearance.colors.colLayer1
            border.width: 1
            border.color: Appearance.colors.colLayer0Border

            Row {
                id: chipRow
                anchors.centerIn: parent
                spacing: 7

                MaterialSymbol {
                    anchors.verticalCenter: parent.verticalCenter
                    text: "keyboard"
                    font.pixelSize: Appearance.font.pixelSize.normal
                    color: Appearance.colors.colOnLayer0
                }
                StyledText {
                    anchors.verticalCenter: parent.verticalCenter
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: Appearance.colors.colOnLayer0
                    text: (KeyboardLayout.isAuto ? qsTr("Auto · ") : "")
                        + KeyboardLayout.effectiveLayout.toUpperCase()
                        + layoutChip.variantSuffix
                }
                StyledText {
                    visible: layoutChip.switchable
                    anchors.verticalCenter: parent.verticalCenter
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: Appearance.colors.colOnLayer0
                    opacity: 0.5
                    text: "▾"
                }
            }

            MouseArea {
                id: chipArea
                anchors.fill: parent
                enabled: layoutChip.switchable
                hoverEnabled: true
                cursorShape: layoutChip.switchable ? Qt.PointingHandCursor : Qt.ArrowCursor
                onClicked: KeyboardLayout.cycleLayout()
            }
        }

        Row { // Keybind columns
            id: row
            spacing: root.spacing

            Repeater {
                model: root.keybinds.children

                delegate: Column { // Keybind sections
                    spacing: root.spacing
                    required property var modelData
                    anchors.top: row.top

                    Repeater {
                        model: modelData.children

                        delegate: Item { // Section with real keybinds
                            id: keybindSection
                            required property var modelData
                            implicitWidth: sectionColumn.implicitWidth
                            implicitHeight: sectionColumn.implicitHeight

                            Column {
                                id: sectionColumn
                                anchors.centerIn: parent
                                spacing: root.titleSpacing

                                StyledText {
                                    id: sectionTitle
                                    font {
                                        family: Appearance.font.family.title
                                        pixelSize: Appearance.font.pixelSize.title
                                        variableAxes: Appearance.font.variableAxes.title
                                    }
                                    color: Appearance.colors.colOnLayer0
                                    text: keybindSection.modelData.name
                                }

                                GridLayout {
                                    id: keybindGrid
                                    columns: 2
                                    columnSpacing: 4
                                    rowSpacing: 4

                                    Repeater {
                                        model: {
                                            // Touch codeToKey so the grid rebuilds
                                            // when the keyboard layout changes.
                                            void KeyboardLayout.codeToKey;
                                            var result = [];
                                            for (var i = 0; i < keybindSection.modelData.keybinds.length; i++) {
                                                const keybind = keybindSection.modelData.keybinds[i];
                                                const showKey = !root.keyBlacklist.includes(keybind.key);

                                                if (!Config.options.cheatsheet.splitButtons) {
                                                    var mods = [];
                                                    for (var j = 0; j < keybind.mods.length; j++) {
                                                        mods.push(root.displayKey(keybind.mods[j]));
                                                    }
                                                    var joined = mods.join(' ');
                                                    if (showKey && joined.length) joined += ' ';
                                                    if (showKey) joined += root.displayKey(keybind.key);
                                                    result.push({
                                                        "type": "keys",
                                                        "mods": [joined],
                                                        "key": keybind.key,
                                                    });
                                                } else {
                                                    result.push({
                                                        "type": "keys",
                                                        "mods": keybind.mods,
                                                        "key": keybind.key,
                                                    });
                                                }
                                                result.push({
                                                    "type": "comment",
                                                    "comment": keybind.comment,
                                                });
                                            }
                                            return result;
                                        }
                                        delegate: Item {
                                            required property var modelData
                                            implicitWidth: keybindLoader.implicitWidth
                                            implicitHeight: keybindLoader.implicitHeight

                                            Loader {
                                                id: keybindLoader
                                                sourceComponent: (modelData.type === "keys") ? keysComponent : commentComponent
                                            }

                                            Component {
                                                id: keysComponent
                                                Row {
                                                    spacing: 4
                                                    Repeater {
                                                        model: modelData.mods
                                                        delegate: KeyboardKey {
                                                            required property var modelData
                                                            key: root.displayKey(modelData)
                                                            pixelSize: Config.options.cheatsheet.fontSize.key
                                                        }
                                                    }
                                                    StyledText {
                                                        id: keybindPlus
                                                        visible: Config.options.cheatsheet.splitButtons && !root.keyBlacklist.includes(modelData.key) && modelData.mods.length > 0
                                                        text: "+"
                                                    }
                                                    KeyboardKey {
                                                        id: keybindKey
                                                        visible: Config.options.cheatsheet.splitButtons && !root.keyBlacklist.includes(modelData.key)
                                                        key: root.displayKey(modelData.key)
                                                        pixelSize: Config.options.cheatsheet.fontSize.key
                                                        color: Appearance.colors.colOnLayer0
                                                    }
                                                }
                                            }

                                            Component {
                                                id: commentComponent
                                                Item {
                                                    id: commentItem
                                                    implicitWidth: commentText.implicitWidth + 8 * 2
                                                    implicitHeight: commentText.implicitHeight

                                                    StyledText {
                                                        id: commentText
                                                        anchors.centerIn: parent
                                                        font.pixelSize: Config.options.cheatsheet.fontSize.comment || Appearance.font.pixelSize.smaller
                                                        text: modelData.comment
                                                    }
                                                }
                                            }
                                        }

                                    }
                                }
                            }
                        }

                    }
                }

            }
        }
    }
}
