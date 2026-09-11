import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland

/**
 * Audio plugin profiles, as a modal sheet.
 *
 * WHY NOT INLINE IN THE AUDIO PANEL
 * It was inline, and the plugin picker made the case against it: a hundred
 * entries in a list squeezed between a chain and a "New profile" button is not
 * browsable, and the panel is narrow because every other thing in it is a row of
 * controls. A chain is built rarely and deliberately, which is exactly what a
 * modal is for - the same reason the Bluetooth and network lists are their own
 * sheets rather than sections.
 *
 * Built on the AppColors pattern: a per-screen overlay whose scrim takes clicks,
 * so tapping outside dismisses without needing the compositor to report a click
 * that the scrim already swallowed.
 */
Scope {
    id: root

    Variants {
        model: Quickshell.screens

        PanelWindow {
            id: win
            required property var modelData
            screen: win.modelData
            visible: GlobalStates.audioPluginsOpen

            exclusiveZone: 0
            exclusionMode: ExclusionMode.Ignore
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.namespace: "quickshell:audioPlugins"
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand
            color: "transparent"

            anchors { top: true; bottom: true; left: true; right: true }

            mask: Region {
                item: scrim
                Region { item: card; intersection: Intersection.Combine }
            }

            onVisibleChanged: {
                if (win.visible) {
                    GlobalFocusGrab.addDismissable(win)
                    // Plugins may have been installed, or the host built, since
                    // this was last open - both are exactly the kind of thing
                    // someone does and then comes straight here to use.
                    AudioPlugins.refresh()
                } else {
                    GlobalFocusGrab.removeDismissable(win)
                }
            }
            Component.onDestruction: GlobalFocusGrab.removeDismissable(win)

            Connections {
                target: GlobalFocusGrab
                function onDismissed() { GlobalStates.audioPluginsOpen = false }
            }

            Item {
                anchors.fill: parent
                focus: true
                Keys.onEscapePressed: GlobalStates.audioPluginsOpen = false
            }

            Rectangle {
                id: scrim
                anchors.fill: parent
                color: Appearance.colors.colScrim
                opacity: GlobalStates.audioPluginsOpen ? 1 : 0
                visible: opacity > 0.01
                Behavior on opacity {
                    NumberAnimation { duration: 180; easing.type: Easing.OutCubic }
                }
                TapHandler { onTapped: GlobalStates.audioPluginsOpen = false }
            }

            Rectangle {
                id: card

                /// Which profile's chain is expanded. One at a time, so the list
                /// of profiles stays scannable.
                property string openProfileId: ""
                /// Which profile the picker is adding to, "" when it is closed.
                property string pickerForId: ""
                property string filter: ""

                anchors.centerIn: parent
                width: Math.min(520, parent.width - 80)
                height: Math.min(600, parent.height - 100)
                radius: Appearance.rounding.large
                color: Appearance.colors.colLayer0
                border.width: 1
                border.color: Appearance.colors.colLayer0Border
                opacity: GlobalStates.audioPluginsOpen ? 1 : 0
                scale: GlobalStates.audioPluginsOpen ? 1 : 0.96
                visible: opacity > 0.01
                Behavior on opacity { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
                Behavior on scale   { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 20
                    spacing: 12

                    // Header
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 10
                        MaterialSymbol {
                            text: "graphic_eq"
                            iconSize: Appearance.font.pixelSize.huge
                            color: Appearance.colors.colPrimary
                        }
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 0
                            StyledText {
                                text: Translation.tr("Plugin profiles")
                                font.pixelSize: Appearance.font.pixelSize.larger
                                font.weight: Font.Medium
                                color: Appearance.colors.colOnLayer0
                            }
                            StyledText {
                                text: Translation.tr("%1 profiles · %2 plugins found")
                                    .arg(AudioPlugins.profiles.length).arg(AudioPlugins.pluginCount)
                                font.pixelSize: Appearance.font.pixelSize.smaller
                                color: Appearance.colors.colSubtext
                            }
                        }
                        MaterialSymbol {
                            text: "close"
                            iconSize: 20
                            color: Appearance.colors.colSubtext
                            TapHandler { onTapped: GlobalStates.audioPluginsOpen = false }
                        }
                    }

                    // Host warning. Stated plainly: without a host a chain cannot
                    // be heard, and a UI that lets you build one anyway while
                    // silently doing nothing is worse than a warning.
                    Rectangle {
                        Layout.fillWidth: true
                        visible: AudioPlugins.hostChecked && !AudioPlugins.hostAvailable
                        implicitHeight: hostWarn.implicitHeight + 16
                        radius: Appearance.rounding.small
                        color: ColorUtils.transparentize(Appearance.m3colors.m3error, 0.86)
                        RowLayout {
                            id: hostWarn
                            anchors { left: parent.left; right: parent.right
                                      verticalCenter: parent.verticalCenter
                                      leftMargin: 12; rightMargin: 12 }
                            spacing: 8
                            MaterialSymbol {
                                text: "warning"; iconSize: 17
                                color: Appearance.m3colors.m3error
                            }
                            StyledText {
                                Layout.fillWidth: true
                                text: Translation.tr("carla-host is not runnable, so chains cannot be started.")
                                wrapMode: Text.Wrap
                                font.pixelSize: Appearance.font.pixelSize.smaller
                                color: Appearance.colors.colOnLayer0
                            }
                        }
                    }

                    // Profiles
                    StyledFlickable {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        contentWidth: width
                        contentHeight: profCol.implicitHeight
                        clip: true
                        boundsBehavior: Flickable.StopAtBounds

                        ColumnLayout {
                            id: profCol
                            width: parent.width
                            spacing: 6

                            Repeater {
                                model: AudioPlugins.profiles
                                delegate: ColumnLayout {
                                    id: prof
                                    required property var modelData
                                    readonly property string pid: String(prof.modelData?.id ?? "")
                                    readonly property bool open: card.openProfileId === prof.pid
                                    readonly property int chainLen: prof.modelData?.chain?.length ?? 0
                                    Layout.fillWidth: true
                                    spacing: 3

                                    Rectangle {
                                        Layout.fillWidth: true
                                        implicitHeight: 40
                                        radius: Appearance.rounding.small
                                        color: profHov.hovered ? Appearance.colors.colLayer1Hover
                                                               : Appearance.colors.colLayer1
                                        HoverHandler { id: profHov; cursorShape: Qt.PointingHandCursor }
                                        TapHandler {
                                            onTapped: card.openProfileId = prof.open ? "" : prof.pid
                                        }
                                        RowLayout {
                                            anchors.fill: parent
                                            anchors.leftMargin: 12; anchors.rightMargin: 10
                                            spacing: 10
                                            MaterialSymbol {
                                                text: AudioPlugins.isRunning(prof.pid) ? "graphic_eq" : "tune"
                                                iconSize: 18
                                                color: AudioPlugins.isRunning(prof.pid)
                                                    ? Appearance.colors.colPrimary
                                                    : Appearance.colors.colSubtext
                                            }
                                            ColumnLayout {
                                                Layout.fillWidth: true
                                                spacing: 0
                                                StyledText {
                                                    Layout.fillWidth: true
                                                    text: prof.modelData?.name ?? ""
                                                    elide: Text.ElideRight
                                                    font.pixelSize: Appearance.font.pixelSize.small
                                                    color: Appearance.colors.colOnLayer1
                                                }
                                                StyledText {
                                                    Layout.fillWidth: true
                                                    text: AudioPlugins.isRunning(prof.pid)
                                                        ? Translation.tr("Running · route apps to \"%1\"")
                                                              .arg(prof.modelData?.name ?? "")
                                                        : Translation.tr("%1 plugins").arg(prof.chainLen)
                                                    elide: Text.ElideRight
                                                    font.pixelSize: Appearance.font.pixelSize.smallest
                                                    color: Appearance.colors.colSubtext
                                                }
                                            }
                                            MaterialSymbol {
                                                text: AudioPlugins.isRunning(prof.pid) ? "stop_circle" : "play_circle"
                                                iconSize: 22
                                                color: AudioPlugins.isRunning(prof.pid)
                                                    ? Appearance.colors.colPrimary
                                                    : Appearance.colors.colOnLayer1
                                                opacity: (AudioPlugins.hostAvailable && prof.chainLen > 0) ? 1 : 0.35
                                                TapHandler {
                                                    onTapped: {
                                                        if (!AudioPlugins.hostAvailable || prof.chainLen === 0) return
                                                        if (AudioPlugins.isRunning(prof.pid))
                                                            AudioPlugins.stopProfile(prof.pid)
                                                        else
                                                            AudioPlugins.startProfile(prof.pid)
                                                    }
                                                }
                                            }
                                            MaterialSymbol {
                                                text: "delete"; iconSize: 18
                                                color: Appearance.colors.colSubtext
                                                TapHandler {
                                                    onTapped: {
                                                        if (AudioPlugins.isRunning(prof.pid))
                                                            AudioPlugins.stopProfile(prof.pid)
                                                        if (card.openProfileId === prof.pid) card.openProfileId = ""
                                                        AudioPlugins.removeProfile(prof.pid)
                                                    }
                                                }
                                            }
                                        }
                                    }

                                    // Chain. Height is a plain binding and the
                                    // content slides in - the same reason the
                                    // audio panel's sections do: an animated
                                    // height here would resize the surface every
                                    // frame.
                                    Item {
                                        Layout.fillWidth: true
                                        clip: true
                                        implicitHeight: prof.open ? chainCol.implicitHeight : 0
                                        ColumnLayout {
                                            id: chainCol
                                            width: parent.width
                                            spacing: 2
                                            y: prof.open ? 0 : -chainCol.implicitHeight
                                            opacity: prof.open ? 1 : 0
                                            Behavior on y {
                                                animation: Appearance.animation.elementMove.numberAnimation.createObject(this)
                                            }
                                            Behavior on opacity {
                                                animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                                            }

                                            Repeater {
                                                model: prof.modelData?.chain ?? []
                                                delegate: RowLayout {
                                                    required property var modelData
                                                    required property int index
                                                    Layout.fillWidth: true
                                                    Layout.leftMargin: 22
                                                    spacing: 8
                                                    StyledText {
                                                        text: (index + 1) + "."
                                                        font.pixelSize: Appearance.font.pixelSize.smallest
                                                        color: Appearance.colors.colSubtext
                                                    }
                                                    StyledText {
                                                        Layout.fillWidth: true
                                                        text: modelData?.name ?? ""
                                                        elide: Text.ElideRight
                                                        font.pixelSize: Appearance.font.pixelSize.smaller
                                                        color: Appearance.colors.colOnLayer0
                                                    }
                                                    // CLAP is shown but marked: this
                                                    // Carla build has no PLUGIN_CLAP,
                                                    // so it is skipped at launch
                                                    // rather than failing the chain.
                                                    StyledText {
                                                        text: (modelData?.format ?? "").toUpperCase()
                                                        font.pixelSize: Appearance.font.pixelSize.smallest
                                                        color: modelData?.format === "clap"
                                                            ? Appearance.m3colors.m3error
                                                            : Appearance.colors.colSubtext
                                                    }
                                                    MaterialSymbol {
                                                        text: "close"; iconSize: 14
                                                        color: Appearance.colors.colSubtext
                                                        TapHandler {
                                                            onTapped: AudioPlugins.removeFromChain(prof.pid, index)
                                                        }
                                                    }
                                                }
                                            }

                                            StyledText {
                                                visible: prof.chainLen === 0
                                                Layout.leftMargin: 22
                                                text: Translation.tr("Empty chain")
                                                font.pixelSize: Appearance.font.pixelSize.smallest
                                                color: Appearance.colors.colSubtext
                                            }

                                            Rectangle {
                                                Layout.fillWidth: true
                                                Layout.leftMargin: 22
                                                implicitHeight: 26
                                                radius: Appearance.rounding.small
                                                color: addHov.hovered ? Appearance.colors.colLayer1Hover : "transparent"
                                                HoverHandler { id: addHov; cursorShape: Qt.PointingHandCursor }
                                                TapHandler {
                                                    onTapped: {
                                                        card.pickerForId =
                                                            card.pickerForId === prof.pid ? "" : prof.pid
                                                        card.filter = ""
                                                    }
                                                }
                                                RowLayout {
                                                    anchors.fill: parent; spacing: 6
                                                    MaterialSymbol {
                                                        text: card.pickerForId === prof.pid ? "expand_less" : "add"
                                                        iconSize: 15
                                                        color: Appearance.colors.colPrimary
                                                    }
                                                    StyledText {
                                                        Layout.fillWidth: true
                                                        text: Translation.tr("Add plugin")
                                                        font.pixelSize: Appearance.font.pixelSize.smaller
                                                        color: Appearance.colors.colPrimary
                                                    }
                                                }
                                            }

                                            // Picker, with a filter - a hundred
                                            // entries is a list, not a menu.
                                            ColumnLayout {
                                                Layout.fillWidth: true
                                                Layout.leftMargin: 22
                                                visible: card.pickerForId === prof.pid
                                                spacing: 4

                                                Rectangle {
                                                    Layout.fillWidth: true
                                                    implicitHeight: 28
                                                    radius: 14
                                                    color: Appearance.colors.colLayer1
                                                    border.width: 1
                                                    border.color: Appearance.colors.colLayer0Border
                                                    RowLayout {
                                                        anchors.fill: parent
                                                        anchors.leftMargin: 10; anchors.rightMargin: 10
                                                        spacing: 6
                                                        MaterialSymbol {
                                                            text: "search"; iconSize: 14
                                                            color: Appearance.colors.colSubtext
                                                        }
                                                        StyledTextInput {
                                                            id: filterInput
                                                            Layout.fillWidth: true
                                                            font.pixelSize: Appearance.font.pixelSize.smaller
                                                            onTextChanged: card.filter = text
                                                            StyledText {
                                                                anchors.verticalCenter: parent.verticalCenter
                                                                text: Translation.tr("Filter plugins…")
                                                                font.pixelSize: filterInput.font.pixelSize
                                                                color: Appearance.colors.colSubtext
                                                                visible: filterInput.text.length === 0
                                                            }
                                                        }
                                                    }
                                                }

                                                StyledFlickable {
                                                    Layout.fillWidth: true
                                                    implicitHeight: Math.min(contentHeight, 200)
                                                    contentWidth: width
                                                    contentHeight: pickCol.implicitHeight
                                                    clip: true
                                                    boundsBehavior: Flickable.StopAtBounds
                                                    ColumnLayout {
                                                        id: pickCol
                                                        width: parent.width
                                                        spacing: 1
                                                        Repeater {
                                                            model: AudioPlugins.plugins.filter(pl =>
                                                                card.filter.length === 0
                                                                || pl.name.toLowerCase().includes(card.filter.toLowerCase()))
                                                            delegate: Rectangle {
                                                                required property var modelData
                                                                Layout.fillWidth: true
                                                                implicitHeight: 26
                                                                radius: Appearance.rounding.small
                                                                color: pHov.hovered ? Appearance.colors.colLayer1Hover : "transparent"
                                                                HoverHandler { id: pHov; cursorShape: Qt.PointingHandCursor }
                                                                TapHandler {
                                                                    onTapped: {
                                                                        AudioPlugins.addToChain(prof.pid, modelData)
                                                                        card.pickerForId = ""
                                                                    }
                                                                }
                                                                RowLayout {
                                                                    anchors.fill: parent
                                                                    anchors.leftMargin: 8; anchors.rightMargin: 8
                                                                    spacing: 8
                                                                    StyledText {
                                                                        Layout.fillWidth: true
                                                                        text: modelData?.name ?? ""
                                                                        elide: Text.ElideRight
                                                                        font.pixelSize: Appearance.font.pixelSize.smaller
                                                                        color: Appearance.colors.colOnLayer0
                                                                    }
                                                                    StyledText {
                                                                        text: (modelData?.format ?? "").toUpperCase()
                                                                        font.pixelSize: Appearance.font.pixelSize.smallest
                                                                        color: modelData?.format === "clap"
                                                                            ? Appearance.m3colors.m3error
                                                                            : Appearance.colors.colSubtext
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

                            StyledText {
                                visible: AudioPlugins.profiles.length === 0
                                Layout.fillWidth: true
                                Layout.topMargin: 20
                                horizontalAlignment: Text.AlignHCenter
                                text: Translation.tr("No profiles yet.")
                                font.pixelSize: Appearance.font.pixelSize.smaller
                                color: Appearance.colors.colSubtext
                            }
                        }
                    }

                    // New profile
                    Rectangle {
                        Layout.fillWidth: true
                        implicitHeight: 34
                        radius: Appearance.rounding.small
                        color: newHov.hovered ? Appearance.colors.colLayer1Hover
                                              : Appearance.colors.colLayer1
                        HoverHandler { id: newHov; cursorShape: Qt.PointingHandCursor }
                        TapHandler {
                            onTapped: card.openProfileId = AudioPlugins.addProfile("")
                        }
                        RowLayout {
                            anchors.centerIn: parent
                            spacing: 6
                            MaterialSymbol {
                                text: "add_circle"; iconSize: 17
                                color: Appearance.colors.colPrimary
                            }
                            StyledText {
                                text: Translation.tr("New profile")
                                font.pixelSize: Appearance.font.pixelSize.smaller
                                color: Appearance.colors.colPrimary
                            }
                        }
                    }
                }
            }
        }
    }
}
