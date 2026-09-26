pragma ComponentBehavior: Bound
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland

/**
 * When devices connect.
 *
 * Each automation is a SENTENCE — "When Roland DJ-808 connects → make it the
 * output → hold RØDE NT1 gain at +20 dB" — because that is the thing you are
 * actually deciding. An earlier cut of this was a switch per tool per device:
 * five devices became twenty rows of identical grey text where the one question
 * you have ("what will happen?") was the hardest to answer.
 *
 * Two things earn their space beyond the sentences:
 *   - SUGGESTIONS built from hardware that is plugged in right now, so the
 *     panel is never an empty form asking you to invent something.
 *   - A HISTORY of what actually fired. The whole claim is "this happens on its
 *     own", and that claim is worth nothing without a receipt — the dock
 *     dropped twice today and from the desktop's side devices simply vanished.
 *
 * No animations here on purpose: the expand used to animate an implicitHeight
 * inside a ColumnLayout, which re-runs the layout for every card on every
 * frame, and the panel felt heavy for no gain.
 */
Scope {
    id: root

    // Forces the service into existence at startup — see DeviceRules.ready.
    // Without this the watcher only began after the panel was first opened.
    Component.onCompleted: DeviceRules.ready

    IpcHandler {
        target: "deviceTools"
        function toggle(): void { GlobalStates.deviceToolsOpen = !GlobalStates.deviceToolsOpen }
        function open(): void   { GlobalStates.deviceToolsOpen = true }
        function close(): void  { GlobalStates.deviceToolsOpen = false }
        function run(id: string): void { DeviceRules.run(id) }
    }

    GlobalShortcut {
        name: "deviceToolsToggle"
        description: "Toggle the device automations panel"
        onPressed: GlobalStates.deviceToolsOpen = !GlobalStates.deviceToolsOpen
    }

    StackedPanelLoader {
        isOpen: GlobalStates.deviceToolsOpen

        sourceComponent: StackedSettingsPanel {
            id: win
            panelId: "deviceTools"
            title: Translation.tr("Automations")
            icon: "bolt"
            onRequestClose: GlobalStates.deviceToolsOpen = false

            Component.onCompleted: AudioProfiles.refresh()

            // ── what is true right now ───────────────────────────────────
            // The menu opens with the machine's CONTEXT, not with a rules list.
            // Two reasons it earns the top slot: every automation below is
            // phrased against these signals, so this is the vocabulary; and the
            // recurring question on this machine has been "what is even
            // connected?" — twice today the dock dropped and the answer changed
            // without anything on screen saying so.
            Rectangle {
                Layout.fillWidth: true
                implicitHeight: nowCol.implicitHeight + 20
                radius: Appearance.rounding.normal
                color: Appearance.colors.colLayer1

                ColumnLayout {
                    id: nowCol
                    anchors { left: parent.left; right: parent.right; top: parent.top; margins: 10 }
                    spacing: 6

                    StyledText {
                        text: Translation.tr("Right now")
                        font.pixelSize: Appearance.font.pixelSize.smallest
                        font.letterSpacing: 0.6
                        color: Appearance.colors.colSubtext
                    }

                    Flow {
                        Layout.fillWidth: true
                        spacing: 5
                        Repeater {
                            model: Object.keys(DeviceRules.signals)
                            delegate: Rectangle {
                                id: chip
                                required property string modelData
                                // A chip is lit when something is waiting on it,
                                // so you can see at a glance which parts of the
                                // current context actually do anything.
                                readonly property bool armed: DeviceRules.scenes.some(
                                    sc => sc?.when === chip.modelData && sc?.enabled !== false)
                                implicitWidth: chipRow.implicitWidth + 16
                                implicitHeight: 26
                                radius: Appearance.rounding.full
                                color: chip.armed ? Appearance.colors.colPrimary
                                                  : Appearance.colors.colLayer2
                                RowLayout {
                                    id: chipRow
                                    anchors.centerIn: parent
                                    spacing: 5
                                    MaterialSymbol {
                                        text: DeviceRules.signalIcon(chip.modelData)
                                        iconSize: 14
                                        color: chip.armed ? Appearance.colors.colOnPrimary
                                                          : Appearance.colors.colOnLayer2
                                    }
                                    StyledText {
                                        text: DeviceRules.signalLabel(chip.modelData)
                                        font.pixelSize: Appearance.font.pixelSize.smallest
                                        color: chip.armed ? Appearance.colors.colOnPrimary
                                                          : Appearance.colors.colOnLayer2
                                    }
                                }
                            }
                        }
                    }
                }
            }

            // ── drift ────────────────────────────────────────────────────
            // The panel's sharpest claim: not "I ran your rules once" but
            // "this is where the machine is not how you said it should be".
            Rectangle {
                visible: DeviceRules.drift.length > 0
                Layout.fillWidth: true
                implicitHeight: driftCol.implicitHeight + 20
                radius: Appearance.rounding.normal
                color: Appearance.colors.colLayer1
                border.width: 1
                border.color: Appearance.m3colors.m3error

                ColumnLayout {
                    id: driftCol
                    anchors { left: parent.left; right: parent.right; top: parent.top; margins: 10 }
                    spacing: 5

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 8
                        MaterialSymbol {
                            text: "error"; iconSize: 16
                            color: Appearance.m3colors.m3error
                        }
                        StyledText {
                            Layout.fillWidth: true
                            text: Translation.tr("Drifted from your rules")
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            font.weight: Font.Medium
                            color: Appearance.colors.colOnLayer1
                        }
                        DialogButton {
                            buttonText: Translation.tr("Fix")
                            onClicked: DeviceRules.fixDrift()
                        }
                    }
                    Repeater {
                        model: DeviceRules.drift
                        delegate: StyledText {
                            required property var modelData
                            Layout.fillWidth: true
                            Layout.leftMargin: 24
                            wrapMode: Text.WordWrap
                            text: modelData.what
                            font.pixelSize: Appearance.font.pixelSize.smallest
                            color: Appearance.colors.colSubtext
                        }
                    }
                }
            }

            // ── the automations ──────────────────────────────────────────
            Repeater {
                model: DeviceRules.scenes
                delegate: Rectangle {
                    id: scene
                    required property var modelData
                    readonly property bool live: DeviceRules.isLive(modelData.when)
                    readonly property bool on: modelData.enabled !== false

                    Layout.fillWidth: true
                    implicitHeight: sceneCol.implicitHeight + 24
                    radius: Appearance.rounding.normal
                    color: Appearance.colors.colLayer1
                    border.width: 1
                    border.color: scene.on && scene.live ? Appearance.colors.colPrimary
                                                         : Appearance.colors.colLayer0Border

                    ColumnLayout {
                        id: sceneCol
                        anchors { left: parent.left; right: parent.right; top: parent.top; margins: 12 }
                        spacing: 7

                        // "When <device> connects" — the trigger, stated first
                        // because it is the half you cannot change by tapping.
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 9
                            CustomIcon {
                                readonly property string art: DeviceRules.signalArt(scene.modelData.when)
                                visible: art.length > 0
                                width: 17; height: 17; colorize: true
                                source: art
                                color: scene.live ? Appearance.colors.colPrimary
                                                  : Appearance.colors.colSubtext
                            }
                            MaterialSymbol {
                                visible: DeviceRules.signalArt(scene.modelData.when).length === 0
                                text: DeviceRules.signalIcon(scene.modelData.when)
                                iconSize: 17
                                color: scene.live ? Appearance.colors.colPrimary
                                                  : Appearance.colors.colSubtext
                            }
                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 0
                                StyledText {
                                    Layout.fillWidth: true
                                    elide: Text.ElideRight
                                    // "When the DJ-808 connects" / "When power
                                    // is plugged in" — a power state is not an
                                    // arrival, so it takes no verb.
                                    text: Translation.tr("When %1 %2")
                                            .arg(DeviceRules.signalLabel(scene.modelData.when))
                                            .arg(DeviceRules.edgeVerb(scene.modelData.when,
                                                                      scene.modelData.edge ?? "arrive")).trim()
                                    font.pixelSize: Appearance.font.pixelSize.smaller
                                    font.weight: Font.Medium
                                    color: Appearance.colors.colOnLayer1
                                }
                                StyledText {
                                    Layout.fillWidth: true
                                    text: scene.live ? Translation.tr("true now")
                                                     : Translation.tr("waiting")
                                    font.pixelSize: Appearance.font.pixelSize.smallest
                                    color: Appearance.colors.colSubtext
                                }
                            }
                            StyledSwitch {
                                checked: scene.on
                                onToggled: DeviceRules.setSceneEnabled(scene.modelData.id, checked)
                            }
                        }

                        // The consequences, one per line, each removable.
                        Repeater {
                            model: scene.modelData.actions ?? []
                            delegate: RowLayout {
                                id: act
                                required property var modelData
                                required property int index
                                Layout.fillWidth: true
                                Layout.leftMargin: 4
                                spacing: 8
                                opacity: scene.on ? 1 : 0.45

                                StyledText {
                                    text: "→"
                                    font.pixelSize: Appearance.font.pixelSize.smaller
                                    color: Appearance.colors.colSubtext
                                }
                                MaterialSymbol {
                                    text: DeviceRules.actionKinds[act.modelData.type]?.icon ?? "bolt"
                                    iconSize: 15
                                    color: Appearance.colors.colSubtext
                                }
                                StyledText {
                                    Layout.fillWidth: true
                                    elide: Text.ElideRight
                                    text: DeviceRules.phraseFor(act.modelData, DeviceRules.signalArg(scene.modelData.when))
                                    font.pixelSize: Appearance.font.pixelSize.smaller
                                    color: Appearance.colors.colOnLayer1
                                }
                                MaterialSymbol {
                                    text: "close"
                                    iconSize: 14
                                    color: closeHov.hovered ? Appearance.m3colors.m3error
                                                            : Appearance.colors.colSubtext
                                    HoverHandler { id: closeHov; cursorShape: Qt.PointingHandCursor }
                                    TapHandler {
                                        gesturePolicy: TapHandler.ReleaseWithinBounds
                                        onTapped: DeviceRules.removeAction(scene.modelData.id, act.index)
                                    }
                                }
                            }
                        }

                        // Which edge, and what holds it back. Both are part of
                        // the sentence, so they sit with it rather than behind
                        // a separate editor.
                        RowLayout {
                            Layout.fillWidth: true
                            Layout.topMargin: 4
                            spacing: 5
                            StyledText {
                                text: Translation.tr("Fires when it")
                                font.pixelSize: Appearance.font.pixelSize.smallest
                                color: Appearance.colors.colSubtext
                            }
                            Repeater {
                                model: [
                                    { key: "arrive", label: Translation.tr("arrives") },
                                    { key: "leave",  label: Translation.tr("leaves") },
                                ]
                                delegate: Rectangle {
                                    id: edgeChip
                                    required property var modelData
                                    readonly property bool sel:
                                        (scene.modelData.edge ?? "arrive") === edgeChip.modelData.key
                                    implicitWidth: edgeLabel.implicitWidth + 16
                                    implicitHeight: 22
                                    radius: Appearance.rounding.full
                                    color: edgeChip.sel ? Appearance.colors.colPrimary
                                                        : Appearance.colors.colLayer2
                                    StyledText {
                                        id: edgeLabel
                                        anchors.centerIn: parent
                                        text: edgeChip.modelData.label
                                        font.pixelSize: Appearance.font.pixelSize.smallest
                                        color: edgeChip.sel ? Appearance.colors.colOnPrimary
                                                            : Appearance.colors.colOnLayer2
                                    }
                                    TapHandler {
                                        gesturePolicy: TapHandler.ReleaseWithinBounds
                                        onTapped: DeviceRules.setEdge(scene.modelData.id,
                                                                      edgeChip.modelData.key)
                                    }
                                }
                            }
                            Item { Layout.fillWidth: true }
                        }

                        RowLayout {
                            visible: DeviceRules.conditionKeys.length > 0
                            Layout.fillWidth: true
                            spacing: 5
                            StyledText {
                                text: Translation.tr("unless")
                                font.pixelSize: Appearance.font.pixelSize.smallest
                                color: Appearance.colors.colSubtext
                            }
                            Repeater {
                                model: DeviceRules.conditionKeys
                                delegate: Rectangle {
                                    id: condChip
                                    required property string modelData
                                    readonly property bool sel:
                                        (scene.modelData.unless ?? []).indexOf(condChip.modelData) >= 0
                                    implicitWidth: condLabel.implicitWidth + 16
                                    implicitHeight: 22
                                    radius: Appearance.rounding.full
                                    color: condChip.sel ? Appearance.m3colors.m3error
                                                        : Appearance.colors.colLayer2
                                    StyledText {
                                        id: condLabel
                                        anchors.centerIn: parent
                                        text: DeviceRules.signalLabel(condChip.modelData)
                                        font.pixelSize: Appearance.font.pixelSize.smallest
                                        color: condChip.sel ? Appearance.colors.colOnPrimary
                                                            : Appearance.colors.colOnLayer2
                                    }
                                    TapHandler {
                                        gesturePolicy: TapHandler.ReleaseWithinBounds
                                        onTapped: {
                                            const cur = (scene.modelData.unless ?? []).slice()
                                            const at = cur.indexOf(condChip.modelData)
                                            if (at >= 0) cur.splice(at, 1)
                                            else cur.push(condChip.modelData)
                                            DeviceRules.setUnless(scene.modelData.id, cur)
                                        }
                                    }
                                }
                            }
                            Item { Layout.fillWidth: true }
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            Layout.topMargin: 2
                            spacing: 6
                            Item { Layout.fillWidth: true }
                            DialogButton {
                                visible: scene.live
                                buttonText: Translation.tr("Run now")
                                onClicked: DeviceRules.run(scene.modelData.id)
                            }
                            DialogButton {
                                buttonText: Translation.tr("Delete")
                                onClicked: DeviceRules.removeScene(scene.modelData.id)
                            }
                        }
                    }
                }
            }

            // ── suggestions ──────────────────────────────────────────────
            StyledText {
                visible: DeviceRules.suggestions.length > 0
                Layout.fillWidth: true
                Layout.topMargin: 4
                text: DeviceRules.scenes.length > 0 ? Translation.tr("Add for hardware you have")
                                                    : Translation.tr("Suggested, from this machine right now")
                font.pixelSize: Appearance.font.pixelSize.smallest
                font.letterSpacing: 0.6
                color: Appearance.colors.colSubtext
            }

            Repeater {
                model: DeviceRules.suggestions
                delegate: Rectangle {
                    id: sug
                    required property var modelData
                    Layout.fillWidth: true
                    implicitHeight: sugCol.implicitHeight + 20
                    radius: Appearance.rounding.normal
                    color: sugHov.hovered ? Appearance.colors.colLayer1Hover
                                          : Appearance.colors.colLayer1
                    HoverHandler { id: sugHov; cursorShape: Qt.PointingHandCursor }
                    TapHandler { onTapped: DeviceRules.acceptSuggestion(sug.modelData) }

                    ColumnLayout {
                        id: sugCol
                        anchors { left: parent.left; right: parent.right; top: parent.top; margins: 10 }
                        spacing: 3

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 9
                            CustomIcon {
                                readonly property string art: DeviceRules.signalArt(sug.modelData.when)
                                visible: art.length > 0
                                width: 17; height: 17; colorize: true
                                source: art
                                color: Appearance.colors.colOnLayer1
                            }
                            MaterialSymbol {
                                visible: DeviceRules.signalArt(sug.modelData.when).length === 0
                                text: DeviceRules.signalIcon(sug.modelData.when)
                                iconSize: 17
                                color: Appearance.colors.colOnLayer1
                            }
                            StyledText {
                                Layout.fillWidth: true
                                elide: Text.ElideRight
                                text: Translation.tr("When %1 %2").arg(sug.modelData.name)
                                        .arg(DeviceRules.signalVerb(sug.modelData.when)).trim()
                                font.pixelSize: Appearance.font.pixelSize.smaller
                                color: Appearance.colors.colOnLayer1
                            }
                            MaterialSymbol {
                                text: "add"
                                iconSize: 17
                                color: Appearance.colors.colPrimary
                            }
                        }
                        StyledText {
                            Layout.fillWidth: true
                            Layout.leftMargin: 26
                            wrapMode: Text.WordWrap
                            text: (sug.modelData.actions ?? [])
                                    .map(a => DeviceRules.phraseFor(a, DeviceRules.signalArg(sug.modelData.when))).join(", ")
                            font.pixelSize: Appearance.font.pixelSize.smallest
                            color: Appearance.colors.colSubtext
                        }
                    }
                }
            }

            // ── the receipt ──────────────────────────────────────────────
            Rectangle {
                visible: DeviceRules.history.length > 0
                Layout.fillWidth: true
                Layout.topMargin: 4
                implicitHeight: histCol.implicitHeight + 20
                radius: Appearance.rounding.normal
                color: Appearance.colors.colLayer1

                ColumnLayout {
                    id: histCol
                    anchors { left: parent.left; right: parent.right; top: parent.top; margins: 10 }
                    spacing: 3
                    StyledText {
                        text: Translation.tr("Recently")
                        font.pixelSize: Appearance.font.pixelSize.smallest
                        font.letterSpacing: 0.6
                        color: Appearance.colors.colSubtext
                    }
                    Repeater {
                        model: DeviceRules.history
                        delegate: StyledText {
                            required property var modelData
                            Layout.fillWidth: true
                            elide: Text.ElideRight
                            text: modelData.text
                            font.pixelSize: Appearance.font.pixelSize.smallest
                            font.family: Appearance.font.family.monospace
                            color: Appearance.colors.colOnLayer1
                        }
                    }
                }
            }

            StyledText {
                visible: DeviceRules.scenes.length === 0 && DeviceRules.suggestions.length === 0
                Layout.fillWidth: true
                Layout.topMargin: 12
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.WordWrap
                text: Translation.tr("Plug something in, or connect a display, and it will show up here.")
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: Appearance.colors.colSubtext
            }
        }
    }
}
