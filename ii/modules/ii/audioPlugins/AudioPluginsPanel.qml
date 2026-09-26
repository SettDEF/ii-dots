import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import QtQuick
import QtQuick.Layouts

/**
 * Plugin profiles: a named plugin chain that runs as its own sink.
 *
 * The CONTENT of a sheet, not a panel - see AudioSettings, which hosts it over
 * itself. It was a stacked panel beside Audio, which meant the thing you build
 * a chain for and the thing that routes audio into it were two windows that
 * had to be opened separately and could evict each other from the stack.
 *
 * Everything here is a positioner with explicit sizes. Layout nesting collapsed
 * this UI to zero height three separate ways before it was rewritten, so the
 * chain and the plugin list are Columns whose heights come from their children
 * and nothing else.
 */
ColumnLayout {
    id: win
    Layout.fillWidth: true
    spacing: 10

        /// Which profile's plugin picker is open, "" for none. One at a time:
        /// two open lists of ninety entries is not a panel, it is a wall.
        property string pickerFor: ""
        property string filter: ""
        /// Which profile's "send an app here" list is open, "" for none.
        property string sendFor: ""

        // A plugin may have been installed, or the host built, since this was
        // last open - both are things done immediately before coming here.
        Component.onCompleted: AudioPlugins.refresh()

        // ── Host state ──────────────────────────────────────────────────────
        // Said plainly: without a host a chain cannot be heard, and a UI that
        // lets you build one anyway while silently doing nothing is worse.
        Rectangle {
            Layout.fillWidth: true
            visible: AudioPlugins.hostChecked && !AudioPlugins.hostAvailable
            implicitHeight: hostRow.implicitHeight + 24
            radius: Appearance.rounding.normal
            color: ColorUtils.transparentize(Appearance.m3colors.m3error, 0.86)
            RowLayout {
                id: hostRow
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
                    text: Translation.tr("No plugin host — chains cannot be started.")
                    wrapMode: Text.Wrap
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: Appearance.colors.colOnLayer0
                }
            }
        }

        // ── Profiles ────────────────────────────────────────────────────────
        Repeater {
            model: AudioPlugins.profiles

            delegate: Rectangle {
                id: card
                required property var modelData
                readonly property var profile: modelData
                readonly property string pid: String(modelData?.id ?? "")
                readonly property var chain: modelData?.chain ?? []
                readonly property bool running: AudioPlugins.isRunning(card.pid)
                readonly property bool pickerOpen: win.pickerFor === card.pid

                Layout.fillWidth: true
                implicitHeight: body.implicitHeight + 28
                radius: Appearance.rounding.large
                color: Appearance.colors.colLayer1

                ColumnLayout {
                    id: body
                    anchors { left: parent.left; right: parent.right; top: parent.top
                              leftMargin: 14; rightMargin: 14; topMargin: 14 }
                    spacing: 10

                    // Header: name, state, transport controls
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 8
                        MaterialSymbol {
                            text: "tune"
                            iconSize: 17
                            color: card.running ? Appearance.colors.colPrimary
                                                : Appearance.colors.colSubtext
                        }
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 0
                            StyledText {
                                Layout.fillWidth: true
                                text: card.modelData?.name ?? ""
                                elide: Text.ElideRight
                                font.pixelSize: Appearance.font.pixelSize.small
                                color: Appearance.colors.colOnLayer1
                            }
                            // A running chain reports what is actually going
                            // through it and where it comes out, read from the
                            // same live graph the audio panel's app rows use.
                            // It used to say "route apps to this sink", which
                            // is an instruction, not a state - and gave no way
                            // to tell a working chain from a silent one.
                            StyledText {
                                Layout.fillWidth: true
                                text: {
                                    if (!card.running)
                                        return card.chain.length === 1
                                            ? Translation.tr("1 plugin")
                                            : Translation.tr("%1 plugins").arg(card.chain.length)
                                    const n = AudioPlugins.appsRoutedTo(card.profile).length
                                    const out = AudioPlugins.outputOf(card.profile)
                                    const who = n === 0 ? Translation.tr("No apps routed")
                                              : n === 1 ? Translation.tr("1 app")
                                              : Translation.tr("%1 apps").arg(n)
                                    return out.length > 0 ? who + "  →  " + out : who
                                }
                                elide: Text.ElideRight
                                font.pixelSize: Appearance.font.pixelSize.smallest
                                color: card.running && AudioPlugins.appsRoutedTo(card.profile).length === 0
                                    ? Appearance.m3colors.m3error
                                    : Appearance.colors.colSubtext
                            }
                        }
                        // A chain that is up with nothing feeding it is running
                        // on silence. This is both the warning and the cure: it
                        // opens the card's own app list, where the old version
                        // of this button threw you at a different panel.
                        RippleButton {
                            visible: card.running
                                     && AudioPlugins.appsRoutedTo(card.profile).length === 0
                                     && AudioPlugins.pendingAppFor(card.profile) === null
                            implicitWidth: 30; implicitHeight: 30
                            buttonRadius: Appearance.rounding.full
                            onClicked: win.sendFor = card.pid
                            contentItem: MaterialSymbol {
                                anchors.centerIn: parent
                                text: "call_split"
                                iconSize: 17
                                color: Appearance.m3colors.m3error
                            }
                            StyledToolTip { text: Translation.tr("Nothing routed — send an app here") }
                        }

                        RippleButton {
                            implicitWidth: 30; implicitHeight: 30
                            buttonRadius: Appearance.rounding.full
                            enabled: AudioPlugins.hostAvailable && card.chain.length > 0
                            opacity: enabled ? 1 : 0.35
                            onClicked: card.running ? AudioPlugins.stopProfile(card.pid)
                                                    : AudioPlugins.startProfile(card.pid)
                            contentItem: MaterialSymbol {
                                anchors.centerIn: parent
                                text: card.running ? "stop" : "play_arrow"
                                iconSize: 18
                                color: card.running ? Appearance.colors.colPrimary
                                                    : Appearance.colors.colOnLayer1
                            }
                            StyledToolTip {
                                text: card.running ? Translation.tr("Stop") : Translation.tr("Start")
                            }
                        }
                        RippleButton {
                            implicitWidth: 30; implicitHeight: 30
                            buttonRadius: Appearance.rounding.full
                            onClicked: {
                                if (card.running) AudioPlugins.stopProfile(card.pid)
                                if (win.pickerFor === card.pid) win.pickerFor = ""
                                AudioPlugins.removeProfile(card.pid)
                            }
                            contentItem: MaterialSymbol {
                                anchors.centerIn: parent
                                text: "delete"; iconSize: 17
                                color: Appearance.colors.colSubtext
                            }
                            StyledToolTip { text: Translation.tr("Delete profile") }
                        }
                    }

                    // ── In ────────────────────────────────────────────────
                    // The apps feeding this chain, and how to add one. This was
                    // the missing half of the workflow: you built a chain here
                    // and then went to the audio panel, opened Apps, found the
                    // app and picked the chain - six steps across two panels for
                    // the one thing a chain exists to do. A profile is what goes
                    // in, what it does, and where it comes out; all three belong
                    // on the card.
                    Column {
                        Layout.fillWidth: true
                        spacing: 4

                        Repeater {
                            model: AudioPlugins.appsRoutedTo(card.profile)
                            delegate: Rectangle {
                                id: inRow
                                required property var modelData
                                width: parent.width
                                height: 30
                                radius: Appearance.rounding.small
                                color: Appearance.colors.colPrimaryContainer
                                RowLayout {
                                    anchors { fill: parent; leftMargin: 10; rightMargin: 4 }
                                    spacing: 8
                                    MaterialSymbol {
                                        text: "arrow_downward"; iconSize: 15
                                        color: Appearance.colors.colOnPrimaryContainer
                                    }
                                    StyledText {
                                        Layout.fillWidth: true
                                        text: Audio.appNodeDisplayName(inRow.modelData)
                                        elide: Text.ElideRight
                                        font.pixelSize: Appearance.font.pixelSize.smaller
                                        color: Appearance.colors.colOnPrimaryContainer
                                    }
                                    RippleButton {
                                        implicitWidth: 24; implicitHeight: 24
                                        buttonRadius: Appearance.rounding.full
                                        onClicked: AudioPlugins.unroute(inRow.modelData)
                                        contentItem: MaterialSymbol {
                                            anchors.centerIn: parent
                                            text: "close"; iconSize: 14
                                            color: Appearance.colors.colOnPrimaryContainer
                                        }
                                        StyledToolTip { text: Translation.tr("Send this app back to the default output") }
                                    }
                                }
                            }
                        }

                        // The one on its way in. Same row shape as a routed
                        // app so it does not jump when it lands.
                        Rectangle {
                            readonly property var pending: AudioPlugins.pendingAppFor(card.profile)
                            visible: pending !== null
                            width: parent.width
                            height: 30
                            radius: Appearance.rounding.small
                            color: Appearance.colors.colLayer2
                            RowLayout {
                                anchors { fill: parent; leftMargin: 10; rightMargin: 10 }
                                spacing: 8
                                MaterialSymbol {
                                    text: "hourglass_top"; iconSize: 15
                                    color: Appearance.colors.colSubtext
                                }
                                StyledText {
                                    Layout.fillWidth: true
                                    text: Audio.appNodeDisplayName(parent.parent.pending)
                                    elide: Text.ElideRight
                                    font.pixelSize: Appearance.font.pixelSize.smaller
                                    color: Appearance.colors.colSubtext
                                }
                                StyledText {
                                    text: Translation.tr("starting…")
                                    font.pixelSize: Appearance.font.pixelSize.smallest
                                    color: Appearance.colors.colSubtext
                                }
                            }
                        }

                        // The apps not already on this chain. A chain cannot
                        // feed itself, and neither can another chain's output
                        // without making a loop.
                        Rectangle {
                            width: parent.width
                            height: 30
                            radius: Appearance.rounding.small
                            color: sendHov.hovered ? Appearance.colors.colLayer2Hover
                                                   : Appearance.colors.colLayer2
                            HoverHandler { id: sendHov; cursorShape: Qt.PointingHandCursor }
                            TapHandler {
                                onTapped: win.sendFor = win.sendFor === card.pid ? "" : card.pid
                            }
                            RowLayout {
                                anchors { fill: parent; leftMargin: 10; rightMargin: 10 }
                                spacing: 8
                                MaterialSymbol {
                                    text: "add"; iconSize: 15
                                    color: Appearance.colors.colSubtext
                                }
                                StyledText {
                                    Layout.fillWidth: true
                                    text: Translation.tr("Send an app here")
                                    font.pixelSize: Appearance.font.pixelSize.smaller
                                    color: Appearance.colors.colOnLayer2
                                }
                            }
                        }

                        Repeater {
                            model: win.sendFor === card.pid
                                ? Audio.outputAppNodes.filter(n =>
                                    !AudioPlugins.profiles.some(pr =>
                                        pr.name === Audio.appNodeDisplayName(n))
                                    && Audio.sinkForStream(n.id) !== card.profile.name)
                                : []
                            delegate: Rectangle {
                                id: candidate
                                required property var modelData
                                width: parent.width
                                height: 30
                                radius: Appearance.rounding.small
                                color: candHov.hovered ? Appearance.colors.colLayer1Hover
                                                       : Appearance.colors.colLayer1
                                HoverHandler { id: candHov; cursorShape: Qt.PointingHandCursor }
                                TapHandler {
                                    onTapped: {
                                        AudioPlugins.routeInto(candidate.modelData, card.profile)
                                        win.sendFor = ""
                                    }
                                }
                                RowLayout {
                                    anchors { fill: parent; leftMargin: 26; rightMargin: 10 }
                                    spacing: 8
                                    StyledText {
                                        Layout.fillWidth: true
                                        text: Audio.appNodeDisplayName(candidate.modelData)
                                        elide: Text.ElideRight
                                        font.pixelSize: Appearance.font.pixelSize.smaller
                                        color: Appearance.colors.colOnLayer1
                                    }
                                }
                            }
                        }
                    }

                    // The chain. A Column, so its height is its children's.
                    Column {
                        Layout.fillWidth: true
                        spacing: 4

                        Repeater {
                            model: card.chain
                            delegate: Rectangle {
                                required property var modelData
                                required property int index
                                width: parent.width
                                height: 30
                                radius: Appearance.rounding.small
                                color: rowHov.hovered ? Appearance.colors.colLayer2Hover
                                                      : Appearance.colors.colLayer2
                                HoverHandler { id: rowHov }
                                RowLayout {
                                    anchors { fill: parent; leftMargin: 10; rightMargin: 4 }
                                    spacing: 8
                                    StyledText {
                                        text: (index + 1)
                                        font.family: Appearance.font.family.monospace
                                        font.pixelSize: Appearance.font.pixelSize.smallest
                                        color: Appearance.colors.colSubtext
                                    }
                                    StyledText {
                                        Layout.fillWidth: true
                                        text: modelData?.name ?? ""
                                        elide: Text.ElideRight
                                        font.pixelSize: Appearance.font.pixelSize.smaller
                                        color: Appearance.colors.colOnLayer2
                                    }
                                    // CLAP is marked, not hidden: this Carla build
                                    // has no PLUGIN_CLAP, so it is skipped at launch
                                    // rather than failing the whole chain.
                                    StyledText {
                                        text: (modelData?.format ?? "").toUpperCase()
                                        font.pixelSize: Appearance.font.pixelSize.smallest
                                        color: modelData?.format === "clap"
                                            ? Appearance.m3colors.m3error
                                            : Appearance.colors.colSubtext
                                    }
                                    // The plugin's own editor. Only reachable
                                    // while the profile is running: the window
                                    // is drawn by the host process that loaded
                                    // it, so there is nothing to show until
                                    // that process exists.
                                    RippleButton {
                                        readonly property int hostIndex:
                                            AudioPlugins.hostIndexOf(card.profile, index)
                                        readonly property bool canOpen:
                                            AudioPlugins.isRunning(card.pid) && hostIndex >= 0
                                        implicitWidth: 24; implicitHeight: 24
                                        buttonRadius: Appearance.rounding.full
                                        enabled: canOpen
                                        onClicked: AudioPlugins.showPluginUi(card.pid, hostIndex, true)
                                        contentItem: MaterialSymbol {
                                            anchors.centerIn: parent
                                            text: "open_in_new"; iconSize: 14
                                            color: parent.canOpen ? Appearance.colors.colOnLayer2
                                                                  : Appearance.colors.colSubtext
                                        }
                                        StyledToolTip {
                                            text: parent.canOpen
                                                ? Translation.tr("Open the plugin window")
                                                : (parent.hostIndex < 0
                                                    ? Translation.tr("This Carla build cannot load CLAP")
                                                    : Translation.tr("Start the profile to open its plugins"))
                                        }
                                    }

                                    RippleButton {
                                        implicitWidth: 24; implicitHeight: 24
                                        buttonRadius: Appearance.rounding.full
                                        onClicked: AudioPlugins.removeFromChain(card.pid, index)
                                        contentItem: MaterialSymbol {
                                            anchors.centerIn: parent
                                            text: "close"; iconSize: 14
                                            color: Appearance.colors.colSubtext
                                        }
                                        StyledToolTip { text: Translation.tr("Remove") }
                                    }
                                }
                            }
                        }

                        StyledText {
                            visible: card.chain.length === 0
                            text: Translation.tr("No plugins yet")
                            font.pixelSize: Appearance.font.pixelSize.smallest
                            color: Appearance.colors.colSubtext
                        }
                    }

                    // Add / close the picker
                    RippleButtonWithIcon {
                        Layout.fillWidth: true
                        implicitHeight: 32
                        buttonRadius: Appearance.rounding.small
                        materialIcon: card.pickerOpen ? "expand_less" : "add"
                        mainText: card.pickerOpen
                            ? Translation.tr("Close list")
                            : Translation.tr("Add plugin")
                        onClicked: {
                            win.pickerFor = card.pickerOpen ? "" : card.pid
                            win.filter = ""
                        }
                    }

                    // ── Picker ──────────────────────────────────────────────
                    ColumnLayout {
                        Layout.fillWidth: true
                        visible: card.pickerOpen
                        spacing: 6

                        Rectangle {
                            Layout.fillWidth: true
                            implicitHeight: 32
                            radius: Appearance.rounding.full
                            color: Appearance.colors.colLayer2
                            RowLayout {
                                anchors { fill: parent; leftMargin: 12; rightMargin: 12 }
                                spacing: 6
                                MaterialSymbol {
                                    text: "search"; iconSize: 15
                                    color: Appearance.colors.colSubtext
                                }
                                StyledTextInput {
                                    id: filterField
                                    Layout.fillWidth: true
                                    font.pixelSize: Appearance.font.pixelSize.smaller
                                    color: Appearance.colors.colOnLayer2
                                    onTextChanged: win.filter = text
                                    StyledText {
                                        anchors.verticalCenter: parent.verticalCenter
                                        visible: filterField.text.length === 0
                                        text: Translation.tr("Search %1 plugins…")
                                            .arg(AudioPlugins.pluginCount)
                                        font.pixelSize: filterField.font.pixelSize
                                        color: Appearance.colors.colSubtext
                                    }
                                }
                            }
                        }

                        StyledFlickable {
                            Layout.fillWidth: true
                            // Bounded so one open list cannot push the rest of the
                            // panel off screen.
                            Layout.preferredHeight: Math.min(list.height, 240)
                            contentWidth: width
                            contentHeight: list.height
                            clip: true
                            boundsBehavior: Flickable.StopAtBounds
                            StyledScrollBar.vertical: StyledScrollBar {}

                            Column {
                                id: list
                                width: parent.width
                                spacing: 2

                                Repeater {
                                    model: AudioPlugins.plugins.filter(p =>
                                        win.filter.length === 0
                                        || p.name.toLowerCase().includes(win.filter.toLowerCase()))
                                    delegate: Rectangle {
                                        required property var modelData
                                        width: list.width
                                        height: 30
                                        radius: Appearance.rounding.small
                                        color: entryHov.hovered ? Appearance.colors.colLayer2Hover
                                                                : "transparent"
                                        HoverHandler { id: entryHov; cursorShape: Qt.PointingHandCursor }
                                        TapHandler {
                                            onTapped: {
                                                AudioPlugins.addToChain(card.pid, modelData)
                                                win.pickerFor = ""
                                            }
                                        }
                                        RowLayout {
                                            anchors { fill: parent; leftMargin: 10; rightMargin: 10 }
                                            spacing: 8
                                            StyledText {
                                                Layout.fillWidth: true
                                                text: modelData?.name ?? ""
                                                elide: Text.ElideRight
                                                font.pixelSize: Appearance.font.pixelSize.smaller
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

        // ── New profile ─────────────────────────────────────────────────────
        // RippleButtonWithIcon, not PrimaryActionButton: the latter is a
        // DialogButton variant and takes `buttonText`, not an icon + mainText.
        RippleButtonWithIcon {
            Layout.fillWidth: true
            implicitHeight: 36
            buttonRadius: Appearance.rounding.small
            materialIcon: "add"
            mainText: Translation.tr("New profile")
            onClicked: AudioPlugins.addProfile("")
        }

        StyledText {
            Layout.fillWidth: true
            visible: AudioPlugins.profiles.length === 0
            horizontalAlignment: Text.AlignHCenter
            text: Translation.tr("A profile is a plugin chain apps can be routed through.")
            wrapMode: Text.Wrap
            font.pixelSize: Appearance.font.pixelSize.smallest
            color: Appearance.colors.colSubtext
        }
    }
