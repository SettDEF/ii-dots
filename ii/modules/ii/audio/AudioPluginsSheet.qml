import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import QtQuick
import QtQuick.Layouts

/**
 * Plugin profiles, as a sheet over the audio panel.
 *
 * WHY A SHEET AND NOT A SECTION
 * It was a section, and the picker made the case against it: a hundred entries
 * squeezed between a chain and a "New profile" button, in a panel that is narrow
 * because everything else in it is a row of controls.
 *
 * WHY NOT A FULL-SCREEN MODAL EITHER
 * That covers the thing being configured. StackedSettingsPanel's sheet slot
 * confines this to the audio panel's own card: that panel dims, the rest of the
 * desktop carries on, and the panel keeps its place in the stack.
 *
 * The sheet fills whatever the slot gives it, so no sizing is set here.
 */
Rectangle {
    id: root

    /// Emitted by the close button. The panel hosting the sheet connects this;
    /// reaching up through parents to find closeSheet() would break the moment
    /// the slot's internals changed.
    signal requestClose()

    /// Which profile's chain is expanded. One at a time, so the list stays
    /// scannable when several profiles exist.
    property string openProfileId: ""
    /// Which profile the picker is adding to, "" when closed.
    property string pickerForId: ""
    property string filter: ""

    radius: Appearance.rounding.normal
    // colLayer1Base, not colLayer1. colLayer1 is solved to look correct when
    // composited over colLayer0Base and is therefore SEMI-TRANSPARENT - fine for
    // a card sitting on the panel background, wrong for a sheet sitting on the
    // panel's widgets, which showed straight through it.
    color: Appearance.colors.colLayer1Base
    border.width: 1
    border.color: Appearance.colors.colLayer0Border

    // Plugins may have been installed, or the host built, since this was last
    // opened - both are things someone does and then comes straight here to use.
    Component.onCompleted: AudioPlugins.refresh()

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 14
        spacing: 10

        // Header
        RowLayout {
            Layout.fillWidth: true
            spacing: 8
            MaterialSymbol {
                text: "graphic_eq"
                iconSize: 19
                color: Appearance.colors.colPrimary
            }
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 0
                StyledText {
                    text: Translation.tr("Plugin profiles")
                    font.pixelSize: Appearance.font.pixelSize.normal
                    font.weight: Font.Medium
                    color: Appearance.colors.colOnLayer1
                }
                StyledText {
                    text: Translation.tr("%1 plugins found").arg(AudioPlugins.pluginCount)
                    font.pixelSize: Appearance.font.pixelSize.smallest
                    color: Appearance.colors.colSubtext
                }
            }
            RippleButton {
                implicitWidth: 26
                implicitHeight: 26
                buttonRadius: 13
                onClicked: root.requestClose()
                contentItem: MaterialSymbol {
                    anchors.centerIn: parent
                    text: "close"
                    iconSize: 16
                    color: Appearance.colors.colOnLayer1
                }
            }
        }

        // Host state. Said plainly: without a host a chain cannot be heard, and
        // a UI that lets you build one anyway while silently doing nothing is
        // worse than a warning.
        Rectangle {
            Layout.fillWidth: true
            visible: AudioPlugins.hostChecked && !AudioPlugins.hostAvailable
            implicitHeight: hostWarn.implicitHeight + 14
            radius: Appearance.rounding.small
            color: ColorUtils.transparentize(Appearance.m3colors.m3error, 0.86)
            RowLayout {
                id: hostWarn
                anchors { left: parent.left; right: parent.right
                          verticalCenter: parent.verticalCenter
                          leftMargin: 10; rightMargin: 10 }
                spacing: 7
                MaterialSymbol {
                    text: "warning"; iconSize: 15
                    color: Appearance.m3colors.m3error
                }
                StyledText {
                    Layout.fillWidth: true
                    text: Translation.tr("carla-host is not runnable, so chains cannot be started.")
                    wrapMode: Text.Wrap
                    font.pixelSize: Appearance.font.pixelSize.smallest
                    color: Appearance.colors.colOnLayer1
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
                spacing: 5

                Repeater {
                    model: AudioPlugins.profiles
                    delegate: ColumnLayout {
                        id: prof
                        required property var modelData
                        readonly property string pid: String(prof.modelData?.id ?? "")
                        readonly property bool open: root.openProfileId === prof.pid
                        readonly property int chainLen: prof.modelData?.chain?.length ?? 0
                        Layout.fillWidth: true
                        spacing: 2

                        Rectangle {
                            Layout.fillWidth: true
                            implicitHeight: 38
                            radius: Appearance.rounding.small
                            color: profHov.hovered ? Appearance.colors.colLayer2Hover
                                                   : Appearance.colors.colLayer2
                            HoverHandler { id: profHov; cursorShape: Qt.PointingHandCursor }
                            TapHandler {
                                onTapped: root.openProfileId = prof.open ? "" : prof.pid
                            }
                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: 10; anchors.rightMargin: 8
                                spacing: 8
                                MaterialSymbol {
                                    text: AudioPlugins.isRunning(prof.pid) ? "graphic_eq" : "tune"
                                    iconSize: 17
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
                                        font.pixelSize: Appearance.font.pixelSize.smaller
                                        color: Appearance.colors.colOnLayer2
                                    }
                                    StyledText {
                                        Layout.fillWidth: true
                                        // When it is running, the useful fact is
                                        // WHERE to send audio, not how many
                                        // plugins are in it.
                                        text: AudioPlugins.isRunning(prof.pid)
                                            ? Translation.tr("Running · route apps here")
                                            : Translation.tr("%1 plugins").arg(prof.chainLen)
                                        elide: Text.ElideRight
                                        font.pixelSize: Appearance.font.pixelSize.smallest
                                        color: Appearance.colors.colSubtext
                                    }
                                }
                                MaterialSymbol {
                                    text: AudioPlugins.isRunning(prof.pid) ? "stop_circle" : "play_circle"
                                    iconSize: 21
                                    color: AudioPlugins.isRunning(prof.pid)
                                        ? Appearance.colors.colPrimary
                                        : Appearance.colors.colOnLayer2
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
                                    text: "delete"; iconSize: 17
                                    color: Appearance.colors.colSubtext
                                    TapHandler {
                                        onTapped: {
                                            if (AudioPlugins.isRunning(prof.pid))
                                                AudioPlugins.stopProfile(prof.pid)
                                            if (root.openProfileId === prof.pid) root.openProfileId = ""
                                            AudioPlugins.removeProfile(prof.pid)
                                        }
                                    }
                                }
                            }
                        }

                        // Chain, shown when the profile is expanded.
                        ColumnLayout {
                            id: chainCol
                            // Laid out by profCol directly. It used to sit in a
                            // clipping Item whose height was driven by this
                            // layout's implicitHeight - but a ColumnLayout nested
                            // in a plain Item is never given a height, so it never
                            // laid out, the wrapper stayed 0 tall, and tapping a
                            // profile appeared to do nothing at all.
                            Layout.fillWidth: true
                            visible: prof.open
                            spacing: 2

                            Repeater {
                                model: prof.modelData?.chain ?? []
                                delegate: RowLayout {
                                    required property var modelData
                                    required property int index
                                    Layout.fillWidth: true
                                    Layout.leftMargin: 18
                                    spacing: 7
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
                                        color: Appearance.colors.colOnLayer1
                                    }
                                    // CLAP is shown but marked: this Carla
                                    // build has no PLUGIN_CLAP, so it is
                                    // skipped at launch rather than being
                                    // allowed to fail the whole chain.
                                    StyledText {
                                        text: (modelData?.format ?? "").toUpperCase()
                                        font.pixelSize: Appearance.font.pixelSize.smallest
                                        color: modelData?.format === "clap"
                                            ? Appearance.m3colors.m3error
                                            : Appearance.colors.colSubtext
                                    }
                                    MaterialSymbol {
                                        text: "close"; iconSize: 13
                                        color: Appearance.colors.colSubtext
                                        TapHandler {
                                            onTapped: AudioPlugins.removeFromChain(prof.pid, index)
                                        }
                                    }
                                }
                            }

                            StyledText {
                                visible: prof.chainLen === 0
                                Layout.leftMargin: 18
                                text: Translation.tr("Empty chain")
                                font.pixelSize: Appearance.font.pixelSize.smallest
                                color: Appearance.colors.colSubtext
                            }

                            Rectangle {
                                Layout.fillWidth: true
                                Layout.leftMargin: 18
                                implicitHeight: 24
                                radius: Appearance.rounding.small
                                color: addHov.hovered ? Appearance.colors.colLayer2Hover : "transparent"
                                HoverHandler { id: addHov; cursorShape: Qt.PointingHandCursor }
                                TapHandler {
                                    onTapped: {
                                        root.pickerForId =
                                            root.pickerForId === prof.pid ? "" : prof.pid
                                        root.filter = ""
                                    }
                                }
                                RowLayout {
                                    anchors.fill: parent; spacing: 5
                                    MaterialSymbol {
                                        text: root.pickerForId === prof.pid ? "expand_less" : "add"
                                        iconSize: 14
                                        color: Appearance.colors.colPrimary
                                    }
                                    StyledText {
                                        Layout.fillWidth: true
                                        text: Translation.tr("Add plugin")
                                        font.pixelSize: Appearance.font.pixelSize.smallest
                                        color: Appearance.colors.colPrimary
                                    }
                                }
                            }

                            // Picker, with a filter - ninety entries is a
                            // list, not a menu.
                            ColumnLayout {
                                Layout.fillWidth: true
                                Layout.leftMargin: 18
                                visible: root.pickerForId === prof.pid
                                spacing: 3

                                Rectangle {
                                    Layout.fillWidth: true
                                    implicitHeight: 26
                                    radius: 13
                                    color: Appearance.colors.colLayer2
                                    border.width: 1
                                    border.color: Appearance.colors.colLayer0Border
                                    RowLayout {
                                        anchors.fill: parent
                                        anchors.leftMargin: 9; anchors.rightMargin: 9
                                        spacing: 5
                                        MaterialSymbol {
                                            text: "search"; iconSize: 13
                                            color: Appearance.colors.colSubtext
                                        }
                                        StyledTextInput {
                                            id: filterInput
                                            Layout.fillWidth: true
                                            font.pixelSize: Appearance.font.pixelSize.smallest
                                            onTextChanged: root.filter = text
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
                                    implicitHeight: Math.min(contentHeight, 170)
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
                                                root.filter.length === 0
                                                || pl.name.toLowerCase().includes(root.filter.toLowerCase()))
                                            delegate: Rectangle {
                                                required property var modelData
                                                Layout.fillWidth: true
                                                implicitHeight: 24
                                                radius: Appearance.rounding.small
                                                color: pHov.hovered ? Appearance.colors.colLayer2Hover : "transparent"
                                                HoverHandler { id: pHov; cursorShape: Qt.PointingHandCursor }
                                                TapHandler {
                                                    onTapped: {
                                                        AudioPlugins.addToChain(prof.pid, modelData)
                                                        root.pickerForId = ""
                                                    }
                                                }
                                                RowLayout {
                                                    anchors.fill: parent
                                                    anchors.leftMargin: 7; anchors.rightMargin: 7
                                                    spacing: 7
                                                    StyledText {
                                                        Layout.fillWidth: true
                                                        text: modelData?.name ?? ""
                                                        elide: Text.ElideRight
                                                        font.pixelSize: Appearance.font.pixelSize.smallest
                                                        color: Appearance.colors.colOnLayer1
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

                StyledText {
                    visible: AudioPlugins.profiles.length === 0
                    Layout.fillWidth: true
                    Layout.topMargin: 16
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
            implicitHeight: 32
            radius: Appearance.rounding.small
            color: newHov.hovered ? Appearance.colors.colLayer2Hover
                                  : Appearance.colors.colLayer2
            HoverHandler { id: newHov; cursorShape: Qt.PointingHandCursor }
            TapHandler { onTapped: root.openProfileId = AudioPlugins.addProfile("") }
            RowLayout {
                anchors.centerIn: parent
                spacing: 5
                MaterialSymbol {
                    text: "add_circle"; iconSize: 16
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
