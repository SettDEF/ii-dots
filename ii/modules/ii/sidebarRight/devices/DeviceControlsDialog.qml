import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Bluetooth

/**
 * Per-device controls, as a second dialog over the device list.
 *
 * WHY A SEPARATE DIALOG
 * The device row can say what a thing IS and whether it is connected. It cannot
 * also carry a light show, an EQ and a pointer DPI without becoming a wall, and
 * inlining them made every row as tall as the most complicated device in the
 * list.
 *
 * WHY IT IS DATA-DRIVEN
 * Sections come from Devices.capabilitiesFor(name), not from a chain of name
 * comparisons here. Supporting a new device is an entry in Devices.vendorControls
 * plus a section below - the list, the button and the routing already work. Every
 * device resolves to at least "info", so the control button is never a dead end.
 */
WindowDialog {
    id: root

    // This one dialog opens ON TOP of another, and a scrim tuned for dimming
    // the sidebar is not enough to settle the device list behind it - its
    // header and its Details/Done row read straight through and turn the
    // bottom of this dialog into clutter. Deeper, only here.
    color: root.show
        ? Qt.rgba(Appearance.colors.colScrim.r, Appearance.colors.colScrim.g,
                  Appearance.colors.colScrim.b,
                  Math.min(1, Appearance.colors.colScrim.a * 1.9))
        : ColorUtils.transparentize(Appearance.colors.colScrim)

    /// The BluetoothDevice this is about. Set by whoever opens the dialog.
    property var device: null
    readonly property string devName: root.device?.name ?? ""
    readonly property var groups: Devices.capabilitiesFor(root.devName)

    readonly property int battery: Devices.batteryFor(root.devName)
    readonly property bool onUsb: Devices.isOnUsb(root.devName)

    RowLayout {
        Layout.fillWidth: true
        Layout.bottomMargin: 4
        spacing: 14

        Rectangle {
            implicitWidth: 52
            implicitHeight: 52
            radius: Appearance.rounding.full
            color: Appearance.colors.colPrimaryContainer
            MaterialSymbol {
                anchors.centerIn: parent
                text: Icons.getBluetoothDeviceMaterialSymbol(root.device?.icon || "")
                iconSize: 26
                color: Appearance.colors.colOnPrimaryContainer
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 3

            StyledText {
                Layout.fillWidth: true
                elide: Text.ElideRight
                text: root.devName.length > 0 ? root.devName : Translation.tr("Device")
                font.pixelSize: Appearance.font.pixelSize.larger
                font.weight: Font.Medium
                color: Appearance.colors.colOnLayer0
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 6

                StyledText {
                    text: root.onUsb ? Translation.tr("Connected by USB")
                        : (root.device?.connected ? Translation.tr("Connected")
                                                  : Translation.tr("Paired"))
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: Appearance.colors.colSubtext
                }

                // Charge as a pill rather than a row in a table at the bottom:
                // it is the thing people open this for and then close again.
                Rectangle {
                    visible: root.battery >= 0
                    implicitWidth: batteryRow.implicitWidth + 14
                    implicitHeight: 20
                    radius: Appearance.rounding.full
                    color: root.battery <= 20
                        ? ColorUtils.transparentize(Appearance.m3colors.m3error, 0.82)
                        : Appearance.colors.colLayer2
                    RowLayout {
                        id: batteryRow
                        anchors.centerIn: parent
                        spacing: 3
                        MaterialSymbol {
                            text: root.battery <= 20 ? "battery_alert" : "battery_full"
                            iconSize: 13
                            color: root.battery <= 20 ? Appearance.m3colors.m3error
                                                      : Appearance.colors.colOnLayer2
                        }
                        StyledText {
                            text: root.battery + "%"
                            font.pixelSize: Appearance.font.pixelSize.smallest
                            font.family: Appearance.font.family.monospace
                            color: root.battery <= 20 ? Appearance.m3colors.m3error
                                                      : Appearance.colors.colOnLayer2
                        }
                    }
                }

                Item { Layout.fillWidth: true }
            }
        }
    }

    /// The PipeWire node behind this device, when there is one. Resolved once
    /// here rather than inside a delegate: a section is a Component loaded into
    /// a list delegate, where `parent` is whatever the view happened to build.
    readonly property var node: (Devices.rows.find(r => r.name === root.devName) ?? {}).node ?? null

    // A list, not a Column: the JBL has six sections and the dialog grew past
    // the bottom of the screen, because WindowDialog sizes itself to its content
    // and nothing was capping that content.
    StyledListView {
        Layout.fillWidth: true
        // Sized to fit, capped so it scrolls instead of running off-screen.
        // The cap lands mid-card by design - a card sliced by the edge is the
        // only honest signal that there is more below, and the alternative
        // (snapping to whole cards) hides the fact entirely.
        Layout.preferredHeight: Math.min(contentHeight, 430)
        ScrollBar.vertical.policy: contentHeight > height ? ScrollBar.AlwaysOn
                                                          : ScrollBar.AlwaysOff
        Layout.leftMargin: -4
        Layout.rightMargin: -4
        clip: true
        spacing: 12
        animateAppearance: false

        model: ScriptModel { values: root.groups }

        delegate: Rectangle {
            required property var modelData
            anchors { left: parent?.left; right: parent?.right; leftMargin: 4; rightMargin: 4 }
            implicitHeight: section.implicitHeight + 28
            radius: Appearance.rounding.large
            color: Appearance.colors.colLayer1

            ColumnLayout {
                id: section
                anchors { left: parent.left; right: parent.right; top: parent.top
                          leftMargin: 14; rightMargin: 14; topMargin: 14 }
                spacing: 10

                // A caption, not a title bar. Six bold headings with coloured
                // icons competed with the controls they were labelling; the
                // control is the thing you came for.
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 6
                    MaterialSymbol {
                        text: modelData.icon
                        iconSize: 15
                        color: Appearance.colors.colSubtext
                    }
                    StyledText {
                        Layout.fillWidth: true
                        text: modelData.label
                        font.pixelSize: Appearance.font.pixelSize.smallest
                        font.weight: Font.Medium
                        font.letterSpacing: 0.6
                        color: Appearance.colors.colSubtext
                    }
                }

                // One loader per group id. Unknown ids fall through to a
                // stated "not available" rather than an empty card, so a
                // half-supported device still explains itself.
                Loader {
                    Layout.fillWidth: true
                    sourceComponent: {
                        switch (modelData.id) {
                            case "volume":  return volumeSection
                            case "profile": return profileSection
                            case "connection": return connectionSection
                            case "pointer": return pointerSection
                            case "lights":  return lightsSection
                            case "eq":      return eqSection
                            case "info":    return infoSection
                        }
                        return unsupportedSection
                    }
                }
            }
        }
    }

    WindowDialogSeparator {}
    WindowDialogButtonRow {
        Item { Layout.fillWidth: true }
        DialogButton {
            buttonText: Translation.tr("Done")
            onClicked: root.dismiss()
        }
    }

    // ── Sections ────────────────────────────────────────────────────────────

    Component {
        id: volumeSection
        StyledSlider {
            value: root.node?.audio?.volume ?? 0
            onMoved: if (root.node?.audio) root.node.audio.volume = value
        }
    }

    Component {
        id: pointerSection
        ColumnLayout {
            spacing: 4
            StyledText {
                Layout.fillWidth: true
                wrapMode: Text.Wrap
                text: LogiTune.available
                    ? Translation.tr("DPI and scroll settings are read from LogiTune.")
                    : Translation.tr("Pointer settings need solaar or LogiTune.")
                font.pixelSize: Appearance.font.pixelSize.smallest
                color: Appearance.colors.colSubtext
            }
        }
    }

    Component {
        id: lightsSection
        ColumnLayout {
            spacing: 8

            readonly property var l: Devices.featureValues(root.devName, "lights")
            readonly property bool live: l !== null

            // Read on open. Cheap to say, and the alternative is a panel that
            // shows nothing until someone finds a refresh button.
            Component.onCompleted: if (!Devices.featureData(root.devName, "lights"))
                                       Devices.refreshFeature(root.devName, "lights")

            component LightSlider: ColumnLayout {
                property string key: ""
                property string label: ""
                property int value: 0
                property int from: 0
                property int to: 100
                Layout.fillWidth: true
                spacing: 0
                RowLayout {
                    Layout.fillWidth: true
                    StyledText {
                        Layout.fillWidth: true
                        text: label
                        font.pixelSize: Appearance.font.pixelSize.smallest
                        color: Appearance.colors.colSubtext
                    }
                    StyledText {
                        text: String(value)
                        font.family: Appearance.font.family.monospace
                        font.pixelSize: Appearance.font.pixelSize.smallest
                        color: Appearance.colors.colOnLayer1
                    }
                }
                StyledSlider {
                    Layout.fillWidth: true
                    from: parent.from
                    to: parent.to
                    value: parent.value
                    stepSize: 1
                    // onPressedChanged rather than onMoved: each write is a
                    // BLE round trip, and firing one per pixel of drag queues
                    // up seconds of radio traffic behind the finger.
                    onPressedChanged: if (!pressed) Devices.setFeature(root.devName, "lights", parent.key, Math.round(value))
                }
            }

            LightSlider {
                visible: parent.live
                key: "brightness"; label: Translation.tr("Brightness")
                value: parent.l?.brightness?.value ?? 0
            }
            LightSlider {
                visible: parent.live
                key: "speed"; label: Translation.tr("Speed")
                value: parent.l?.speed?.value ?? 0
                to: 10
            }
            LightSlider {
                visible: parent.live
                key: "temperature"; label: Translation.tr("Warmth")
                value: parent.l?.temperature?.value ?? 0
            }

            // Colour. The speaker takes any RGB, so a row of swatches is a
            // shortcut rather than the whole range - and the active one is
            // whatever it currently reports.
            ColumnLayout {
                visible: parent.live
                Layout.fillWidth: true
                spacing: 4
                StyledText {
                    text: Translation.tr("Colour")
                    font.pixelSize: Appearance.font.pixelSize.smallest
                    color: Appearance.colors.colSubtext
                }
                Flow {
                    Layout.fillWidth: true
                    spacing: 6
                    Repeater {
                        model: ["#ff0000", "#ff8000", "#ffff00", "#00ff00",
                                "#00ffff", "#0080ff", "#8000ff", "#ffffff"]
                        delegate: Rectangle {
                            required property string modelData
                            readonly property bool sel:
                                (Devices.featureValues(root.devName, "lights")?.colormode?.color ?? "") === modelData
                            width: 26
                            height: 26
                            radius: Appearance.rounding.full
                            color: modelData
                            border.width: sel ? 3 : 0
                            border.color: Appearance.colors.colOnLayer1
                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: Devices.setFeature(root.devName, "lights", "colormode", parent.modelData)
                            }
                        }
                    }
                }
            }

            // Not reachable. Says why, because the reason is not guessable and
            // the answer is a thing the user can actually do.
            StyledText {
                visible: !parent.live
                Layout.fillWidth: true
                wrapMode: Text.Wrap
                text: Devices.featureBusy(root.devName, "lights")
                    ? Translation.tr("Reading the light settings…")
                    : Translation.tr("The speaker only accepts its control link while it is not connected over Bluetooth — disconnect it, or use its USB-C cable, then read again.")
                font.pixelSize: Appearance.font.pixelSize.smallest
                color: Appearance.colors.colSubtext
            }

            RippleButtonWithIcon {
                Layout.alignment: Qt.AlignRight
                enabled: !Devices.featureBusy(root.devName, "lights")
                materialIcon: "refresh"
                mainText: Translation.tr("Read again")
                onClicked: Devices.refreshFeature(root.devName, "lights")
            }
        }
    }

    Component {
        id: profileSection
        ColumnLayout {
            spacing: 5

            // Chips rather than a combo box: the list is three or four entries
            // and the active one should be readable without opening anything.
            Flow {
                Layout.fillWidth: true
                spacing: 5
                Repeater {
                    model: Devices.cardFor(root.device?.address ?? "")?.profiles ?? []
                    delegate: RippleButton {
                        required property var modelData
                        readonly property bool sel: modelData.name === (Devices.cardFor(root.device?.address ?? "")?.active ?? "")
                        implicitHeight: 30
                        implicitWidth: chipText.implicitWidth + 24
                        buttonRadius: Appearance.rounding.full
                        colBackground: sel ? Appearance.colors.colPrimary : Appearance.colors.colLayer2
                        colBackgroundHover: sel ? Appearance.colors.colPrimary : Appearance.colors.colLayer2Hover
                        onClicked: Devices.setCardProfile(root.device?.address ?? "", modelData.name)
                        contentItem: StyledText {
                            id: chipText
                            anchors.centerIn: parent
                            // The descriptions are sentences ("High Fidelity
                            // Playback (A2DP Sink, codec AAC)"); the codec in
                            // the parentheses is the part worth reading.
                            text: {
                                const d = modelData.description ?? modelData.name
                                const m = d.match(/codec ([^)]+)\)/)
                                if (m) return m[1]
                                if (/^off$/i.test(modelData.name)) return Translation.tr("Off")
                                if (/headset|handsfree/i.test(modelData.name)) return Translation.tr("Headset")
                                if (/a2dp/i.test(modelData.name)) return Translation.tr("High fidelity")
                                return d
                            }
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            color: parent.sel ? Appearance.colors.colOnPrimary : Appearance.colors.colOnLayer2
                        }
                    }
                }
            }
            StyledText {
                Layout.fillWidth: true
                wrapMode: Text.Wrap
                // Worth stating once: people go looking for this setting after
                // their music turns to mud the moment something opens the mic.
                text: Translation.tr("A headset profile enables the microphone and drops playback to telephone quality.")
                font.pixelSize: Appearance.font.pixelSize.smallest
                color: Appearance.colors.colSubtext
            }
        }
    }

    Component {
        id: connectionSection
        RowLayout {
            spacing: 6
            PrimaryActionButton {
                buttonText: root.device?.connected ? Translation.tr("Disconnect") : Translation.tr("Connect")
                onClicked: {
                    if (root.device?.connected) root.device.disconnect()
                    else root.device.connect()
                }
            }
            Item { Layout.fillWidth: true }
            PrimaryActionButton {
                visible: root.device?.paired ?? false
                colBackground: Appearance.colors.colError
                colBackgroundHover: Appearance.colors.colErrorHover
                colRipple: Appearance.colors.colErrorActive
                colText: Appearance.colors.colOnError
                buttonText: Translation.tr("Forget")
                onClicked: root.device?.forget()
            }
        }
    }

    Component {
        id: eqSection
        ColumnLayout {
            spacing: 8

            readonly property var eq: Devices.featureValues(root.devName, "eq")
            readonly property bool live: eq !== null

            Component.onCompleted: if (!Devices.featureData(root.devName, "eq"))
                                       Devices.refreshFeature(root.devName, "eq")

            // Bass boost is the one EQ feature whose encoding is the same
            // single-byte, 0x80-offset level the light features use, so it is
            // the one that can be driven rather than only reported.
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 0
                visible: parent.live && parent.eq?.bassboost !== undefined
                RowLayout {
                    Layout.fillWidth: true
                    StyledText {
                        Layout.fillWidth: true
                        text: Translation.tr("Bass boost")
                        font.pixelSize: Appearance.font.pixelSize.smallest
                        color: Appearance.colors.colSubtext
                    }
                    StyledText {
                        text: String(parent.parent.eq?.bassboost?.value ?? 0)
                        font.family: Appearance.font.family.monospace
                        font.pixelSize: Appearance.font.pixelSize.smallest
                        color: Appearance.colors.colOnLayer1
                    }
                }
                StyledSlider {
                    Layout.fillWidth: true
                    from: 0
                    to: 100
                    stepSize: 1
                    value: parent.eq?.bassboost?.value ?? 0
                    // One write per gesture, not per pixel: each is a BLE
                    // round trip on a link that takes one occupant.
                    onPressedChanged: if (!pressed)
                        Devices.setFeature(root.devName, "eq", "bassboost", Math.round(value))
                }
            }

            // The band layout is not established, so the bands are reported
            // rather than drawn as a curve this file invented. Once a real
            // reading exists, this is where the curve goes.
            StyledText {
                visible: parent.live
                Layout.fillWidth: true
                wrapMode: Text.Wrap
                text: {
                    const e = parent.eq
                    if (!e) return ""
                    const parts = []
                    for (const k of ["preset", "current", "custom"])
                        if (e[k]?.bytes > 0)
                            parts.push(`${k} ${e[k].bytes}B`)
                    return parts.length > 0
                        ? Translation.tr("Speaker EQ present: ") + parts.join(" · ")
                        : Translation.tr("The speaker reported no EQ data.")
                }
                font.pixelSize: Appearance.font.pixelSize.smallest
                font.family: Appearance.font.family.monospace
                color: Appearance.colors.colSubtext
            }

            StyledText {
                visible: !parent.live
                Layout.fillWidth: true
                wrapMode: Text.Wrap
                text: Devices.featureBusy(root.devName, "eq")
                    ? Translation.tr("Reading the equaliser…")
                    : Translation.tr("The speaker only accepts its control link while it is not connected over Bluetooth — disconnect it, or use its USB-C cable, then read again.")
                font.pixelSize: Appearance.font.pixelSize.smallest
                color: Appearance.colors.colSubtext
            }

            RippleButtonWithIcon {
                Layout.alignment: Qt.AlignRight
                enabled: !Devices.featureBusy(root.devName, "eq")
                materialIcon: "refresh"
                mainText: Translation.tr("Read again")
                onClicked: Devices.refreshFeature(root.devName, "eq")
            }
        }
    }

    Component {
        id: infoSection
        ColumnLayout {
            spacing: 3
            component InfoRow: RowLayout {
                property string k: ""
                property string v: ""
                Layout.fillWidth: true
                visible: v.length > 0
                StyledText {
                    text: k
                    font.pixelSize: Appearance.font.pixelSize.smallest
                    color: Appearance.colors.colSubtext
                }
                Item { Layout.fillWidth: true }
                StyledText {
                    text: v
                    font.family: Appearance.font.family.monospace
                    font.pixelSize: Appearance.font.pixelSize.smallest
                    color: Appearance.colors.colOnLayer1
                }
            }
            // Battery and transport moved to the hero, where they are read at a
            // glance rather than looked up. What is left here is what you only
            // ever want when something is wrong.
            InfoRow { k: Translation.tr("Address");  v: root.device?.address ?? "" }
            InfoRow { k: Translation.tr("Firmware"); v: Devices.firmwareFor(root.devName) }
            InfoRow {
                k: Translation.tr("Codec")
                v: {
                    const card = Devices.cardFor(root.device?.address ?? "")
                    if (!card) return ""
                    const m = String(card.active).match(/sbc_xq|sbc|aac|aptx\w*|ldac/i)
                    return m ? m[0].toUpperCase().replace("_", "-") : ""
                }
            }
        }
    }

    Component {
        id: unsupportedSection
        StyledText {
            text: Translation.tr("Not available for this device.")
            font.pixelSize: Appearance.font.pixelSize.smallest
            color: Appearance.colors.colSubtext
        }
    }
}
