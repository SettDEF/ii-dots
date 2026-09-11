pragma ComponentBehavior: Bound
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import QtQuick
import QtQuick.Layouts
import Quickshell

// The selected wallpaper effect's variables, in a popup beside WallTune.
// Reads/writes through the WallEffect service so the two stay in sync.
Scope {
    id: root

    Loader {
        active: GlobalStates.wallEffectVarsOpen
                && WallEffect.hasVariables

        sourceComponent: StackedSettingsPanel {
            id: win
            panelId: "wallEffect"
            title: WallEffect.currentFx ? WallEffect.currentFx.name : Translation.tr("Effect")
            icon: "tune"
            onRequestClose: GlobalStates.wallEffectVarsOpen = false

            StyledText {
                Layout.fillWidth: true
                text: Translation.tr("Variables of the selected wallpaper effect. "
                    + "Changes apply live and are remembered per effect.")
                wrapMode: Text.WordWrap
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: Appearance.colors.colSubtext
            }

            Repeater {
                model: ScriptModel { values: WallEffect.currentParams }
                delegate: ColumnLayout {
                    id: prm
                    required property var modelData
                    readonly property string effectPath: WallEffect.currentEffect
                    readonly property var cur: WallEffect.effectParam(effectPath, modelData)
                    Layout.fillWidth: true
                    spacing: 3

                    // Float → labelled slider
                    RowLayout {
                        Layout.fillWidth: true
                        visible: prm.modelData.type === "float"
                        StyledText {
                            text: prm.modelData.label
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            color: Appearance.colors.colOnLayer0
                        }
                        Item { Layout.fillWidth: true }
                        StyledText {
                            text: Number(prm.cur).toFixed(2)
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            font.family: Appearance.font.family.monospace
                            color: Appearance.colors.colPrimary
                        }
                    }
                    StyledSlider {
                        Layout.fillWidth: true
                        visible: prm.modelData.type === "float"
                        from: prm.modelData.min ?? 0
                        to: prm.modelData.max ?? 1
                        value: Number(prm.cur)
                        onMoved: WallEffect.setEffectParam(prm.effectPath, prm.modelData.id, value)
                    }

                    // Toggle → switch
                    RowLayout {
                        Layout.fillWidth: true
                        visible: prm.modelData.type === "toggle"
                        StyledText {
                            Layout.fillWidth: true
                            text: prm.modelData.label
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            color: Appearance.colors.colOnLayer0
                        }
                        StyledSwitch {
                            checked: Number(prm.cur) > 0.5
                            onToggled: WallEffect.setEffectParam(prm.effectPath,
                                prm.modelData.id, checked ? 1 : 0)
                        }
                    }

                    // Colour → swatch row
                    RowLayout {
                        Layout.fillWidth: true
                        visible: prm.modelData.type === "color"
                        spacing: 6
                        StyledText {
                            text: prm.modelData.label
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            color: Appearance.colors.colOnLayer0
                        }
                        Item { Layout.fillWidth: true }
                        Repeater {
                            model: ["@primary", "@secondary", "@tertiary",
                                    "#FE5F55", "#FFC500", "#4BC292", "#16171F", "#F4EEE0"]
                            delegate: Rectangle {
                                required property var modelData
                                readonly property bool sel: String(prm.cur) === modelData
                                implicitWidth: 22; implicitHeight: 22
                                radius: 11
                                color: AppDisplay.resolveColor(modelData)
                                border.width: sel ? 2 : 0
                                border.color: Appearance.colors.colOnLayer0
                                HoverHandler { margin: Appearance.sizes.touchSlop; cursorShape: Qt.PointingHandCursor }
                                TapHandler {
                                    margin: Appearance.sizes.touchSlop
                                    onTapped: WallEffect.setEffectParam(prm.effectPath,
                                        prm.modelData.id, modelData)
                                }
                            }
                        }
                    }
                }
            }

            RippleButton {
                Layout.fillWidth: true
                implicitHeight: 34
                colBackground: Appearance.colors.colLayer2
                onClicked: WallEffect.resetEffectParams(WallEffect.currentEffect)
                contentItem: RowLayout {
                    anchors.centerIn: parent
                    spacing: 6
                    MaterialSymbol { text: "restart_alt"; iconSize: 15
                        color: Appearance.colors.colOnLayer2 }
                    StyledText { text: Translation.tr("Reset to defaults")
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        color: Appearance.colors.colOnLayer2 }
                }
            }
        }
    }
}
