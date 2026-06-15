import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

Rectangle {
    id: root
    implicitHeight: rows.implicitHeight + pad * 2
    radius: Appearance.rounding.normal
    color: Appearance.colors.colLayer1

    readonly property real gap:    6
    readonly property real btnH:   56
    readonly property real pad:    6
    readonly property real smallW: btnH

    // ── Android-style wide toggle ──────────────────────────────────────────────
    component WideBtn: Rectangle {
        id: wb
        property string iconName:   ""
        property string label:      ""
        property string statusText: ""
        property bool   toggled:    false
        property bool   isOpen:     false
        signal tap()

        implicitHeight: root.btnH
        radius: (toggled || isOpen) ? Appearance.rounding.large : height / 2
        // Outer pill stays gray — only the inner icon block carries the accent.
        color: Appearance.colors.colLayer2
        Behavior on radius { animation: Appearance.animation.elementMove.numberAnimation.createObject(this) }

        HoverHandler { id: wbHov }
        TapHandler   { onTapped: wb.tap() }
        Rectangle {
            anchors.fill: parent; radius: parent.radius
            color: wbHov.hovered ? Appearance.colors.colLayer2Hover : "transparent"
            Behavior on color { animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this) }
        }

        RowLayout {
            anchors { fill: parent; margins: root.pad }
            spacing: root.pad

            Rectangle {
                implicitWidth:  parent.height
                implicitHeight: parent.height
                radius: wb.radius - root.pad
                color: (wb.toggled || wb.isOpen) ? Appearance.colors.colPrimary : Appearance.colors.colLayer3
                Behavior on color  { animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this) }
                Behavior on radius { animation: Appearance.animation.elementMove.numberAnimation.createObject(this) }
                MaterialSymbol {
                    anchors.centerIn: parent
                    text: wb.iconName
                    fill: (wb.toggled || wb.isOpen) ? 1 : 0
                    iconSize: 22
                    color: (wb.toggled || wb.isOpen) ? Appearance.colors.colOnPrimary : Appearance.colors.colOnLayer3
                    Behavior on color { animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this) }
                }
            }

            Column {
                Layout.fillWidth: true
                spacing: -2
                StyledText {
                    width: parent.width
                    text: wb.label
                    font.pixelSize: Appearance.font.pixelSize.smallie
                    font.weight: 600
                    elide: Text.ElideRight
                    color: Appearance.colors.colOnLayer2
                }
                StyledText {
                    width: parent.width
                    visible: wb.statusText !== ""
                    text: wb.statusText
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    font.weight: 100
                    elide: Text.ElideRight
                    color: Appearance.colors.colSubtext
                }
            }

            MaterialSymbol {
                visible: !wb.toggled
                text: wb.isOpen ? "expand_less" : "expand_more"
                iconSize: 14
                color: Appearance.colors.colSubtext
            }
        }
    }

    // ── Small icon-only toggle ─────────────────────────────────────────────────
    component SmallToggle: Rectangle {
        id: st
        property string iconName: ""
        property bool   toggled:  false
        signal tap()

        implicitWidth:  root.smallW
        implicitHeight: root.btnH
        radius: height / 2
        // Outer always gray.
        color: Appearance.colors.colLayer2

        HoverHandler { id: stHov }
        TapHandler   { onTapped: st.tap() }
        Rectangle {
            anchors.fill: parent; radius: parent.radius
            color: stHov.hovered ? Appearance.colors.colLayer2Hover : "transparent"
            Behavior on color { animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this) }
        }

        // Inner colored button — gets the accent only when toggled.
        Rectangle {
            anchors.centerIn: parent
            width: parent.width - root.pad * 2
            height: parent.height - root.pad * 2
            radius: st.toggled ? Appearance.rounding.normal : height / 2
            Behavior on radius { animation: Appearance.animation.elementMove.numberAnimation.createObject(this) }
            color: st.toggled ? Appearance.colors.colPrimary : Appearance.colors.colLayer3
            Behavior on color { animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this) }
            MaterialSymbol {
                anchors.centerIn: parent
                text: st.iconName
                fill: st.toggled ? 1 : 0
                iconSize: 22
                color: st.toggled ? Appearance.colors.colOnPrimary : Appearance.colors.colOnLayer3
                Behavior on color { animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this) }
            }
        }
    }

    // ── Option chip ────────────────────────────────────────────────────────────
    component OptionChip: Rectangle {
        id: chip
        property string label:      ""
        property bool   isSelected: false
        signal chosen()
        implicitHeight: 34
        radius: Appearance.rounding.full
        color: isSelected ? Appearance.colors.colPrimary : Appearance.colors.colLayer1
        Behavior on color { animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this) }
        HoverHandler { id: chipHov }
        TapHandler   { onTapped: chip.chosen() }
        Rectangle {
            anchors.fill: parent; radius: parent.radius
            color: chipHov.hovered
                ? (chip.isSelected ? Appearance.colors.colPrimaryHover : Appearance.colors.colLayer1Hover)
                : "transparent"
            Behavior on color { animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this) }
        }
        StyledText {
            anchors.centerIn: parent
            text: chip.label
            font.pixelSize: Appearance.font.pixelSize.small
            font.weight: chip.isSelected ? Font.SemiBold : Font.Normal
            color: chip.isSelected ? Appearance.colors.colOnPrimary : Appearance.colors.colOnLayer1
            Behavior on color { animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this) }
        }
    }

    // ── RogPicker popup ────────────────────────────────────────────────────────
    component RogPicker: Popup {
        id: pk
        property string pickerType: ""

        padding: root.pad
        background: Rectangle {
            radius: Appearance.rounding.large
            color: Appearance.colors.colLayer0
            border.width: 1
            border.color: Appearance.colors.colLayer0Border
        }
        closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
        onClosed: {}

        enter: Transition {
            NumberAnimation { property: "opacity"; from: 0; to: 1; duration: 150 }
            NumberAnimation { property: "scale";   from: 0.93; to: 1; duration: Appearance.animation.elementMove.duration; easing.type: Appearance.animation.elementMove.type }
        }
        exit: Transition {
            NumberAnimation { property: "opacity"; from: 1; to: 0; duration: 120 }
        }

        contentItem: ColumnLayout {
            spacing: root.gap

            // GPU pending action warning
            Rectangle {
                visible: pk.pickerType === "gpu" && Rog.gpuPendingAction !== ""
                Layout.fillWidth: true
                implicitHeight: wRow.implicitHeight + 10
                radius: Appearance.rounding.small
                color: Appearance.colors.colLayer1
                RowLayout {
                    id: wRow
                    anchors { fill: parent; margins: 8 }
                    spacing: 6
                    MaterialSymbol { text: "warning"; iconSize: 14; color: Appearance.colors.colOnLayer1 }
                    StyledText {
                        Layout.fillWidth: true
                        text: Rog.gpuPendingAction
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        color: Appearance.colors.colSubtext
                        wrapMode: Text.WordWrap
                    }
                }
            }

            // Chips for profile / gpu / charge
            RowLayout {
                visible: pk.pickerType !== "battery"
                Layout.fillWidth: true
                spacing: root.gap
                Repeater {
                    model: {
                        if (pk.pickerType === "profile") return Rog.profiles
                        if (pk.pickerType === "gpu")     return ["Integrated", "Hybrid", "AsusMuxDiscreet"]
                        if (pk.pickerType === "charge")  return ["Default", "Balanced", "Full"]
                        return []
                    }
                    delegate: OptionChip {
                        required property string modelData
                        required property int    index
                        Layout.fillWidth: true
                        implicitWidth: 0
                        label: modelData === "AsusMuxDiscreet" ? "dGPU" : modelData
                        isSelected: {
                            if (pk.pickerType === "profile") return Rog.profile === modelData
                            if (pk.pickerType === "gpu")     return Rog.gpuMode === modelData
                            if (pk.pickerType === "charge")  return Rog.chargeMode === index
                            return false
                        }
                        onChosen: {
                            if      (pk.pickerType === "profile") Rog.setProfile(modelData)
                            else if (pk.pickerType === "gpu")     Rog.setGpuMode(modelData)
                            else if (pk.pickerType === "charge")  Rog.setChargeMode(index)
                            pk.close()
                        }
                    }
                }
            }

            // Battery slider
            Loader {
                visible: pk.pickerType === "battery"
                active:  pk.pickerType === "battery"
                Layout.fillWidth: true
                Layout.preferredWidth: rows.width - root.pad * 2
                sourceComponent: StyledSlider {
                    id: batSlider
                    from: 20; to: 100
                    value: Rog.batteryLimit
                    configuration: StyledSlider.Configuration.M
                    stopIndicatorValues: [0.5, 0.75, 1.0]
                    usePercentTooltip: false
                    tooltipContent: `${Math.round(value)}%`
                    onMoved: Rog.setBatteryLimit(Math.round(value))

                    MaterialSymbol {
                        anchors {
                            verticalCenter: parent.verticalCenter
                            right: batSlider.value >= 95 ? batSlider.handle.right : parent.right
                            rightMargin: batSlider.value >= 95 ? 14 : 8
                        }
                        iconSize: 20
                        color: batSlider.value >= 95
                            ? Appearance.colors.colOnPrimary
                            : Appearance.colors.colOnSecondaryContainer
                        text: "battery_saver"
                        Behavior on color { animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this) }
                        Behavior on anchors.rightMargin { animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this) }
                    }
                }
            }
        }
    }

    // ── Picker instances (one per button) ─────────────────────────────────────
    RogPicker {
        id: gpuPicker
        pickerType: "gpu"
        onClosed: gpuBtn.forceActiveFocus()
    }
    RogPicker {
        id: batteryPicker
        pickerType: "battery"
        onClosed: batteryBtn.forceActiveFocus()
    }
    RogPicker {
        id: chargePicker
        pickerType: "charge"
        onClosed: chargeBtn.forceActiveFocus()
    }

    // ── 2 rows of buttons ──────────────────────────────────────────────────────
    ColumnLayout {
        id: rows
        anchors { left: parent.left; right: parent.right; top: parent.top; margins: root.pad }
        spacing: root.gap

        RowLayout {
            Layout.fillWidth: true
            spacing: root.gap

            // Profile — two states sharing the SAME thumb.
            //  • Default: thumb on the left, "Profile / <name>" text to the right, no dots.
            //  • Slider:  thumb slides along X to active profile's dot, dots fade in, text fades out.
            // Tap the thumb to switch states; the slide is smooth via a single Behavior on x.
            Rectangle {
                id: profileTrack
                Layout.fillWidth: true
                implicitHeight: root.btnH
                radius: root.btnH / 2
                // Outer track always gray — only the thumb gets the accent.
                color: Appearance.colors.colLayer2

                readonly property int  profileIndex: Rog.profiles.indexOf(Rog.profile)
                readonly property bool isPerf: Rog.profile === "Performance"
                readonly property color colFg: Appearance.colors.colOnLayer2
                property bool selectMode: false

                function iconFor(name) {
                    if (name === "Quiet") return "bedtime"
                    if (name === "Balanced") return "balance"
                    if (name === "Performance") return "speed"
                    return "speed"
                }

                readonly property real thumbDiameter: height - root.pad * 2
                readonly property real availW: width - root.pad * 2 - thumbDiameter
                readonly property real leftRestX: root.pad
                readonly property var stops: {
                    const n = Rog.profiles.length
                    if (n <= 1) return [leftRestX + thumbDiameter / 2]
                    const out = []
                    for (let i = 0; i < n; i++) out.push(leftRestX + thumbDiameter / 2 + availW * (i / (n - 1)))
                    return out
                }

                // ── Default-state label (Profile / <name>) — visible only when not in slider mode ──
                ColumnLayout {
                    anchors {
                        left: profileThumb.right
                        leftMargin: 10
                        right: parent.right
                        rightMargin: root.pad + 4
                        verticalCenter: parent.verticalCenter
                    }
                    spacing: -2
                    opacity: profileTrack.selectMode ? 0 : 1
                    visible: opacity > 0.01
                    Behavior on opacity { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
                    StyledText {
                        text: Translation.tr("Profile")
                        font.pixelSize: Appearance.font.pixelSize.smallie
                        font.weight: Font.DemiBold
                        elide: Text.ElideRight
                        color: profileTrack.colFg
                    }
                    StyledText {
                        text: Rog.profile
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        elide: Text.ElideRight
                        color: ColorUtils.transparentize(Appearance.colors.colOnLayer2, 0.25)
                    }
                }

                // ── Slider-state dots — only visible in select mode ──
                Repeater {
                    model: Rog.profiles
                    delegate: Rectangle {
                        required property int index
                        required property string modelData
                        readonly property bool isActive: Rog.profile === modelData
                        x: profileTrack.stops[index] - width / 2
                        anchors.verticalCenter: parent.verticalCenter
                        width: 8; height: 8; radius: 4
                        color: profileTrack.colFg
                        opacity: profileTrack.selectMode && !isActive ? 0.45 : 0
                        Behavior on opacity { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
                        MouseArea {
                            anchors.fill: parent
                            anchors.margins: -12
                            enabled: profileTrack.selectMode
                            onClicked: {
                                Rog.setProfile(modelData)
                                profileTrack.selectMode = false
                            }
                            cursorShape: Qt.PointingHandCursor
                        }
                    }
                }

                // ── The thumb — single element, slides between left rest and active stop ──
                Rectangle {
                    id: profileThumb
                    width: profileTrack.thumbDiameter; height: width
                    radius: width / 2
                    anchors.verticalCenter: parent.verticalCenter

                    readonly property real restX: profileTrack.leftRestX
                    readonly property real targetX: profileTrack.stops[profileTrack.profileIndex] - width / 2
                    property real dragOffset: 0

                    x: profileTrack.selectMode
                        ? (dragHandler.active
                            ? Math.max(profileTrack.stops[0] - width / 2,
                                Math.min(profileTrack.stops[Rog.profiles.length - 1] - width / 2,
                                    targetX + dragOffset))
                            : targetX)
                        : restX
                    Behavior on x {
                        enabled: !dragHandler.active
                        NumberAnimation {
                            duration: Appearance.animation.elementMove.duration
                            easing.type: Appearance.animation.elementMove.type
                            easing.bezierCurve: Appearance.animation.elementMove.bezierCurve
                        }
                    }
                    color: profileTrack.isPerf ? Appearance.colors.colPrimary : Appearance.colors.colLayer3
                    Behavior on color { animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this) }

                    readonly property int snapIndex: {
                        const center = x + width / 2
                        let bestI = 0, bestD = Infinity
                        for (let i = 0; i < Rog.profiles.length; i++) {
                            const d = Math.abs(center - profileTrack.stops[i])
                            if (d < bestD) { bestD = d; bestI = i }
                        }
                        return bestI
                    }

                    HoverHandler { id: thumbHov }
                    Rectangle {
                        anchors.fill: parent; radius: parent.radius
                        color: thumbHov.hovered && !dragHandler.active
                            ? (profileTrack.isPerf ? Appearance.colors.colPrimaryHover : Appearance.colors.colLayer2Hover)
                            : "transparent"
                        Behavior on color { animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this) }
                    }

                    DragHandler {
                        id: dragHandler
                        target: null
                        enabled: profileTrack.selectMode
                        xAxis.enabled: true
                        yAxis.enabled: false
                        onTranslationChanged: profileThumb.dragOffset = translation.x
                        onActiveChanged: {
                            if (!active) {
                                Rog.setProfile(Rog.profiles[profileThumb.snapIndex])
                                profileThumb.dragOffset = 0
                                profileTrack.selectMode = false
                            }
                        }
                    }
                    TapHandler {
                        // Default: tap → enter slider mode. In slider: tap thumb → leave.
                        onTapped: profileTrack.selectMode = !profileTrack.selectMode
                    }

                    MaterialSymbol {
                        anchors.centerIn: parent
                        text: profileTrack.iconFor(Rog.profile)
                        iconSize: 20
                        fill: 1
                        color: profileTrack.isPerf ? Appearance.colors.colOnPrimary : Appearance.colors.colOnLayer3
                        Behavior on color { animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this) }
                    }
                }
            }
            // (continues with WideBtn buttons below)
            WideBtn {
                id: gpuBtn
                Layout.fillWidth: true
                iconName:   "memory"
                label:      "GPU"
                statusText: Rog.gpuMode === "AsusMuxDiscreet" ? "dGPU" : Rog.gpuMode
                toggled:    Rog.gpuMode !== "Integrated"
                isOpen:     gpuPicker.opened
                onTap: {
                    gpuPicker.x = gpuBtn.mapToItem(rows, 0, 0).x
                    gpuPicker.y = gpuBtn.mapToItem(rows, 0, 0).y + gpuBtn.height + root.gap
                    gpuPicker.width = gpuBtn.width
                    gpuPicker.open()
                }
            }
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: root.gap

            WideBtn {
                id: batteryBtn
                Layout.fillWidth: true
                iconName:   "battery_saver"
                label:      "Battery"
                statusText: Rog.batteryLimit + "%"
                toggled:    Rog.batteryLimit < 100
                isOpen:     batteryPicker.opened
                onTap: {
                    batteryPicker.x = batteryBtn.mapToItem(rows, 0, 0).x
                    batteryPicker.y = batteryBtn.mapToItem(rows, 0, 0).y + batteryBtn.height + root.gap
                    batteryPicker.width = rows.width
                    batteryPicker.open()
                }
            }
            WideBtn {
                id: chargeBtn
                Layout.fillWidth: true
                iconName:   "bolt"
                label:      "Charge"
                statusText: (["Default", "Balanced", "Full"][Rog.chargeMode]) ?? "Default"
                toggled:    Rog.chargeMode > 0
                isOpen:     chargePicker.opened
                onTap: {
                    chargePicker.x = chargeBtn.mapToItem(rows, 0, 0).x
                    chargePicker.y = chargeBtn.mapToItem(rows, 0, 0).y + chargeBtn.height + root.gap
                    chargePicker.width = chargeBtn.width
                    chargePicker.open()
                }
            }
            SmallToggle {
                Layout.preferredWidth: root.smallW
                iconName: "display_settings"
                toggled:  Rog.panelOverdrive
                onTap:    Rog.setPanelOverdrive(!Rog.panelOverdrive)
            }
            SmallToggle {
                Layout.preferredWidth: root.smallW
                iconName: "volume_up"
                toggled:  Rog.bootSound
                onTap:    Rog.setBootSound(!Rog.bootSound)
            }
        }
    }
}
