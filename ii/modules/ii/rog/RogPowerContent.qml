pragma ComponentBehavior: Bound
import qs
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io

/**
 * ROG Flow Z13 power + fan control. A power slider (PPT watts) and a draggable
 * fan-curve graph. Safety coupling: raising power raises the curve's floor
 * (the dots can't drag below it) — "more power → minimum fan goes up", for
 * summer. Power needs root (pkexec → rog-power.sh via polkit); the fan curve
 * goes through asusctl (no root). Read-only poll for live temp/PPT/RPM.
 */
Rectangle {
    id: root
    readonly property string ctl: Quickshell.shellPath("scripts/rog/rog-power-ctl.sh")

    readonly property int powMin: 10
    readonly property int powMax: 65
    property int watts: 35
    property int liveWatts: 0
    property int liveTemp: 0
    property int liveFan: 0
    property int peakRpm: 8900   // highest RPM seen → the graph's right-axis max

    // Moderate fan-floor coupling: 10W→~15%, 65W→~50%.
    readonly property int fanFloor: Math.round(15 + (watts - powMin) * 35 / (powMax - powMin))
    function fanFloorFor(w) { return Math.round(15 + (w - powMin) * 35 / (powMax - powMin)) }

    // ── Presets: one tap sets both PPT watts AND the fan curve ───────────
    readonly property var builtinPresets: [
        { "name": "Silent",      "watts": 15, "pwms": [0, 8, 16, 26, 38, 55, 75, 100] },
        { "name": "Balanced",    "watts": 35, "pwms": [15, 25, 32, 45, 55, 70, 85, 100] },
        { "name": "Performance", "watts": 50, "pwms": [25, 38, 48, 62, 75, 88, 96, 100] },
        { "name": "Max",         "watts": 65, "pwms": [45, 58, 70, 82, 92, 100, 100, 100] }
    ]
    property var customPresets: []
    // Local source of truth for the highlight + persistence target. Decoupled
    // from Persistent so the UI still works even if the singleton is mid-reload.
    property string activePreset: ""
    readonly property var rogState: Persistent.states.rog ?? null

    function loadCustoms() {
        try { customPresets = JSON.parse((rogState && rogState.presets) || "[]") }
        catch (e) { customPresets = [] }
    }
    // Persist the live state (watts + curve + active preset). Guarded so a flaky
    // singleton can't throw out of an apply.
    function persistLive() {
        if (!rogState) return
        rogState.watts = watts
        rogState.curve = JSON.stringify(graph.pwmValues)
        rogState.activePreset = activePreset
    }
    function applyPreset(p) {
        watts = p.watts
        if (p.temps && p.temps.length === graph.tempPoints.length) graph.tempPoints = p.temps.slice()
        // clamp to the floor for the NEW watts (fanFloor binding hasn't re-evaluated yet)
        const floor = fanFloorFor(p.watts)
        graph.pwmValues = p.pwms.map(v => Math.max(floor, Math.min(100, v)))
        powSlider.value = Qt.binding(() => root.watts)   // re-reflect on the slider
        activePreset = p.name
        applyPower(); applyFan()
        persistLive()
    }
    function savePreset(name) {
        if (!name) return
        let list = (customPresets || []).slice()
        const obj = { "name": name, "watts": watts, "pwms": graph.pwmValues.slice(), "temps": graph.tempPoints.slice() }
        let idx = -1
        for (let i = 0; i < list.length; i++) if (list[i].name === name) { idx = i; break }
        if (idx >= 0) list[idx] = obj; else list.push(obj)
        customPresets = list
        activePreset = name
        if (rogState) rogState.presets = JSON.stringify(list)
        persistLive()
    }
    function deletePreset(name) {
        customPresets = (customPresets || []).filter(x => x.name !== name)
        if (activePreset === name) activePreset = ""
        if (rogState) rogState.presets = JSON.stringify(customPresets)
    }

    Component.onCompleted: {
        loadCustoms()
        // Before the early-return below: this must run even with no saved state.
        refreshFanCurveState()
        if (!rogState) return
        if (rogState.watts > 0) watts = rogState.watts
        activePreset = rogState.activePreset || ""
        try {
            const c = JSON.parse(rogState.curve || "[]")
            if (Array.isArray(c) && c.length === graph.tempPoints.length) graph.pwmValues = c
        } catch (e) {}
    }
    Connections {
        target: root.rogState
        ignoreUnknownSignals: true
        function onPresetsChanged() { root.loadCustoms() }
    }

    // A pill that applies a preset; custom ones carry an inline delete. The
    // single top MouseArea decides apply-vs-delete by click position, so there's
    // no overlapping-MouseArea ambiguity to swallow clicks.
    component PresetChip: Rectangle {
        id: chip
        property string label: ""
        property bool active: false
        property bool custom: false
        signal activated()
        signal removed()
        implicitHeight: 28
        implicitWidth: chipText.implicitWidth + (custom ? 36 : 20)
        radius: Appearance.rounding.small
        color: active ? Appearance.colors.colPrimary : Appearance.colors.colLayer1
        border.width: 1
        border.color: active ? Appearance.colors.colPrimary : Appearance.colors.colLayer0Border
        StyledText {
            id: chipText
            anchors { left: parent.left; leftMargin: 10; verticalCenter: parent.verticalCenter }
            text: chip.label
            color: chip.active ? Appearance.colors.colOnPrimary : Appearance.colors.colOnLayer1
            font.pixelSize: Appearance.font.pixelSize.smaller
        }
        MaterialSymbol {
            visible: chip.custom
            anchors { right: parent.right; rightMargin: 6; verticalCenter: parent.verticalCenter }
            text: "close"; iconSize: 15
            color: chip.active ? Appearance.colors.colOnPrimary : Appearance.colors.colSubtext
        }
        MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: mouse => {
                if (chip.custom && mouse.x > chip.width - 26) chip.removed()
                else chip.activated()
            }
        }
    }

    implicitWidth: 360
    /// Inside another panel: no card of its own and no title row, so it is a
    /// section of that panel rather than a panel pasted into it.
    property bool embedded: false

    implicitHeight: col.implicitHeight + (root.embedded ? 0 : 28)
    radius: Appearance.rounding.windowRounding
    color: root.embedded ? "transparent" : Appearance.colors.colLayer0
    border.width: root.embedded ? 0 : 1
    border.color: Appearance.colors.colLayer0Border

    // ── Processes ────────────────────────────────────────────────────────
    Process { id: setPowerProc }            // pkexec set (on slider release)
    // Applying a curve also enables it (see the script's `fan` branch), so the
    // toggle has to re-read afterwards or it would still show "off".
    Process { id: fanProc; onExited: root.refreshFanCurveState() }
    Process {
        id: pollProc
        command: ["bash", "-c", root.ctl + " get"]
        stdout: StdioCollector { onStreamFinished: {
            const p = text.trim().split("|")
            root.liveWatts = parseInt(p[0]) || 0
            root.liveTemp  = parseInt(p[1]) || 0
            root.liveFan   = Math.max(parseInt(p[2]) || 0, parseInt(p[3]) || 0)
            if (root.liveFan > root.peakRpm) root.peakRpm = root.liveFan
        }}
    }
    Timer { interval: 2000; running: root.visible; repeat: true; triggeredOnStart: true; onTriggered: pollProc.running = true }

    // Whether the fans are following the curve drawn below, or the firmware's
    // own. "mixed" = the two fans disagree, which is a state the machine can
    // genuinely be in, so it is surfaced rather than rounded to on/off.
    property string fanCurveState: "unknown"
    readonly property bool fanCurveOn: fanCurveState === "on"

    Process { id: fanCurveSetProc; onExited: root.refreshFanCurveState() }
    Process {
        id: fanCurveGetProc
        command: ["bash", "-c", root.ctl + " fanstate"]
        stdout: StdioCollector { onStreamFinished: root.fanCurveState = text.trim() || "unknown" }
    }
    function refreshFanCurveState() { fanCurveGetProc.running = true }
    function setFanCurve(on) {
        // Optimistic: the switch must not sit on the old value while asusctl
        // runs. refreshFanCurveState() on exit corrects it if the call failed.
        root.fanCurveState = on ? "on" : "off"
        fanCurveSetProc.exec(["bash", "-c", `${root.ctl} fancurve ${on ? "on" : "off"}`])
    }
    // Re-read whenever the panel is shown: the platform profile (and with it the
    // active curve) can change from asusctl, the lock screen, or a keyboard key.
    onVisibleChanged: if (visible) refreshFanCurveState()

    // …and keep re-reading while it IS shown. asusd drops the curve on AC
    // changes, profile touches and resume, and fan-curve-keeper puts it back —
    // both behind the UI's back. Without this the switch kept whatever it was
    // set to and only corrected itself on the next open, so it could sit on
    // "off" over a curve that was already back on. 5s: this shells out to
    // asusctl, unlike the 2s sysfs poll above.
    Timer {
        interval: 5000
        running: root.visible
        repeat: true
        onTriggered: root.refreshFanCurveState()
    }

    function applyPower() { setPowerProc.exec(["bash", "-c", `${root.ctl} set ${root.watts}`]) }
    function applyFan() {
        const data = graph.tempPoints.map((t, i) => `${t}c:${graph.pwmValues[i]}%`).join(",")
        fanProc.exec(["bash", "-c", `${root.ctl} fan '${data}'`])
    }
    Timer { id: fanDeb; interval: 350; onTriggered: root.applyFan() }

    ColumnLayout {
        id: col
        x: root.embedded ? 0 : 14
        y: root.embedded ? 0 : 14
        width: parent.width - (root.embedded ? 0 : 28)
        spacing: 12

        RowLayout {
            visible: !root.embedded
            Layout.fillWidth: true; spacing: 8
            MaterialSymbol { text: "bolt"; iconSize: Appearance.font.pixelSize.title; color: Appearance.colors.colPrimary }
            StyledText {
                Layout.fillWidth: true; text: qsTr("Power & Fan")
                font.pixelSize: Appearance.font.pixelSize.large; font.weight: Font.Medium
                color: Appearance.colors.colOnLayer0
            }
            StyledText {
                text: `${root.liveWatts}W · ${root.liveTemp}°C · ${Math.round(root.liveFan/100)*100} rpm`
                font.pixelSize: Appearance.font.pixelSize.smaller
                font.family: Appearance.font.family.monospace
                color: root.liveTemp >= 90 ? Appearance.m3colors.m3error : Appearance.colors.colSubtext
            }
        }

        // ── Presets: preconfigured power+fan, plus save your own ──────
        StyledText {
            text: qsTr("Presets"); color: Appearance.colors.colSubtext
            font.pixelSize: Appearance.font.pixelSize.smaller
        }
        Flow {
            Layout.fillWidth: true; spacing: 6
            Repeater {
                model: root.builtinPresets
                delegate: PresetChip {
                    required property var modelData
                    label: modelData.name
                    active: root.activePreset === modelData.name
                    onActivated: root.applyPreset(modelData)
                }
            }
            Repeater {
                model: root.customPresets
                delegate: PresetChip {
                    required property var modelData
                    label: modelData.name
                    custom: true
                    active: root.activePreset === modelData.name
                    onActivated: root.applyPreset(modelData)
                    onRemoved: root.deletePreset(modelData.name)
                }
            }
        }
        RowLayout {
            Layout.fillWidth: true; spacing: 6
            PillTextField {
                id: nameField
                Layout.fillWidth: true
                placeholderText: qsTr("Save current as…")
                leadingIcon: "save"
                showClear: false
                onAccepted: { root.savePreset(text.trim()); text = "" }
            }
            Rectangle {
                Layout.preferredWidth: 34; Layout.preferredHeight: 34
                radius: Appearance.rounding.small
                enabled: nameField.text.trim().length > 0
                opacity: enabled ? 1 : 0.4
                color: Qt.alpha(Appearance.colors.colPrimary, saveMa.containsMouse ? 0.28 : 0.14)
                MaterialSymbol { anchors.centerIn: parent; text: "check"; iconSize: 18; color: Appearance.colors.colPrimary }
                MouseArea {
                    id: saveMa; anchors.fill: parent; hoverEnabled: true
                    enabled: parent.enabled; cursorShape: Qt.PointingHandCursor
                    onClicked: { root.savePreset(nameField.text.trim()); nameField.text = "" }
                }
            }
        }

        // ── Power slider ──────────────────────────────────────────────
        RowLayout {
            Layout.fillWidth: true; spacing: 8
            StyledText { text: qsTr("Power"); color: Appearance.colors.colOnLayer0; Layout.preferredWidth: 46 }
            Slider {
                id: powSlider
                Layout.fillWidth: true
                from: root.powMin; to: root.powMax; stepSize: 1
                value: root.watts
                onMoved: { root.watts = Math.round(value); root.activePreset = "" }
                onPressedChanged: if (!pressed) { root.applyPower(); root.persistLive(); value = Qt.binding(() => root.watts) }
                background: Rectangle {
                    x: powSlider.leftPadding; y: powSlider.topPadding + powSlider.availableHeight/2 - height/2
                    width: powSlider.availableWidth; height: 4; radius: 2
                    color: Qt.alpha(Appearance.colors.colOnLayer0, 0.15)
                    Rectangle { width: powSlider.position * parent.width; height: parent.height; radius: parent.radius; color: Appearance.colors.colPrimary }
                }
                handle: Rectangle {
                    x: powSlider.leftPadding + powSlider.position * (powSlider.availableWidth - width)
                    y: powSlider.topPadding + powSlider.availableHeight/2 - height/2
                    implicitWidth: 16; implicitHeight: 16; radius: 8; color: Appearance.colors.colPrimary
                    scale: powSlider.pressed ? 1.2 : 1; Behavior on scale { NumberAnimation { duration: 90 } }
                }
            }
            StyledText {
                text: root.watts + "W"; Layout.preferredWidth: 42; horizontalAlignment: Text.AlignRight
                color: Appearance.colors.colPrimary; font.family: Appearance.font.family.monospace
            }
        }

        // ── Custom curve vs firmware default ──────────────────────────
        // Without this the graph can be a lie: the firmware keeps its own curve
        // and each fan can independently ignore the one drawn below (they were
        // found in different modes — CPU on firmware default, GPU on custom).
        RowLayout {
            Layout.fillWidth: true; spacing: 8
            MaterialSymbol {
                text: "mode_fan"
                iconSize: 17
                color: root.fanCurveOn ? Appearance.colors.colPrimary : Appearance.colors.colSubtext
            }
            ColumnLayout {
                Layout.fillWidth: true; spacing: 0
                StyledText {
                    text: qsTr("Custom fan curve")
                    color: Appearance.colors.colOnLayer0
                }
                StyledText {
                    text: root.fanCurveState === "mixed"
                        ? qsTr("Fans disagree — toggle to sync them")
                        : (root.fanCurveOn ? qsTr("Following the curve below")
                                           : qsTr("Firmware default curve"))
                    font.pixelSize: Appearance.font.pixelSize.smallest
                    color: root.fanCurveState === "mixed"
                        ? Appearance.m3colors.m3error : Appearance.colors.colSubtext
                }
            }
            StyledSwitch {
                scale: 0.7
                Layout.alignment: Qt.AlignVCenter
                checked: root.fanCurveOn
                onToggled: root.setFanCurve(checked)
            }
        }

        StyledText {
            Layout.fillWidth: true
            text: root.fanCurveOn
                ? qsTr("Fan curve — drag the dots. Minimum locked to %1% by the power level (summer safety).").arg(root.fanFloor)
                : qsTr("The firmware is driving the fans. Turn on the custom curve to use the one below.")
            wrapMode: Text.WordWrap
            font.pixelSize: Appearance.font.pixelSize.smaller
            color: Appearance.colors.colSubtext
        }

        // ── Fan curve graph ───────────────────────────────────────────
        FanCurveGraph {
            id: graph
            Layout.fillWidth: true
            floorPwm: root.fanFloor
            liveTemp: root.liveTemp
            maxRpm: root.peakRpm
            onEdited: { root.activePreset = ""; fanDeb.restart(); root.persistLive() }
        }
    }
}
