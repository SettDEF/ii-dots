import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io

/**
 * KinetiX — pointer physics engine control.
 *
 * REBUILT after the original was truncated to zero bytes by a full disk. It is
 * a reconstruction, not the original: the bezier curve EDITOR (draggable nodes
 * and handles on a canvas) is not here. Everything that governs how the pointer
 * actually behaves is.
 *
 * How the engine computes gain (hyper-mouse-rust/src/main.rs, calculate_gain):
 *
 *   linear : gain = sensitivity                          — constant, no accel
 *   bezier : gain = sensitivity * (curve_y / speed)      — speed dependent
 *
 * and the result is clamped to `12 * sensitivity`. That clamp is why a FLAT
 * bezier is catastrophic: constant height divided by a near-zero speed asks for
 * a near-infinite gain and gets the ceiling. "No acceleration" is the linear
 * curve TYPE, never a flat bezier shape.
 *
 * Writes go to /dev/shm/kinetix-config.json (what the daemon watches, reloading
 * within ~50ms) and are mirrored to ~/.config/kinetix-config.json, which
 * kinetix-run restores from at login because /dev/shm does not survive a boot.
 */
Scope {
    id: root

    // ── Live values, adopted from the config file ───────────────────────
    property bool   engineEnabled: true
    property string curveTypeVal: "bezier"
    property real   sensitivityVal: 1.0
    property real   smoothnessVal: 0.0
    property real   frictionVal: 0.0
    property bool   angleSnapVal: false
    property real   snapAngleVal: 6.0
    property bool   kineticInertiaVal: false
    property real   glideFrictionVal: 0.82
    property real   interpolationVal: 0.0
    property real   expPowerVal: 1.0
    property real   sigmoidMidVal: 0.5
    property real   sigmoidSteepVal: 4.0
    property real   velocityCapVal: 0.0
    property real   gforceGainVal: 0.0
    property bool   softEdgeDampVal: false
    property var    curveNodes: []

    // Set while adopting, so the property writes below cannot re-enter
    // saveConfig() and echo the file back at itself.
    property bool adopting: false

    function adoptConfig(text) {
        let c
        try { c = JSON.parse(text || "{}") } catch (e) { return }
        if (!c || typeof c !== "object") return
        root.adopting = true
        if (c.enabled !== undefined)         root.engineEnabled     = !!c.enabled
        if (c.curve_type !== undefined)      root.curveTypeVal      = String(c.curve_type)
        if (c.sensitivity !== undefined)     root.sensitivityVal    = c.sensitivity
        if (c.smoothness !== undefined)      root.smoothnessVal     = c.smoothness
        if (c.tremor_friction !== undefined) root.frictionVal       = c.tremor_friction
        if (c.angle_snapping !== undefined)  root.angleSnapVal      = !!c.angle_snapping
        if (c.snap_angle_deg !== undefined)  root.snapAngleVal      = c.snap_angle_deg
        if (c.kinetic_inertia !== undefined) root.kineticInertiaVal = !!c.kinetic_inertia
        if (c.glide_friction !== undefined)  root.glideFrictionVal  = c.glide_friction
        if (c.interpolation !== undefined)   root.interpolationVal  = c.interpolation
        if (c.exp_power !== undefined)       root.expPowerVal       = c.exp_power
        if (c.sigmoid_mid !== undefined)     root.sigmoidMidVal     = c.sigmoid_mid
        if (c.sigmoid_steep !== undefined)   root.sigmoidSteepVal   = c.sigmoid_steep
        if (c.velocity_cap !== undefined)    root.velocityCapVal    = c.velocity_cap
        if (c.gforce_gain !== undefined)     root.gforceGainVal     = c.gforce_gain
        if (c.soft_edge_damp !== undefined)  root.softEdgeDampVal   = !!c.soft_edge_damp
        if (Array.isArray(c.curve_nodes) && c.curve_nodes.length >= 2)
            root.curveNodes = c.curve_nodes
        root.adopting = false
    }

    // The curve shape is carried through untouched. This panel no longer edits
    // it, and writing a default would silently discard whatever the user drew
    // in the version that had an editor.
    function saveConfig() {
        if (root.adopting) return
        const doc = {
            enabled: root.engineEnabled,
            curve_type: root.curveTypeVal,
            smoothness: root.smoothnessVal,
            sensitivity: root.sensitivityVal,
            tremor_friction: root.frictionVal,
            interpolation: root.interpolationVal,
            angle_snapping: root.angleSnapVal,
            snap_angle_deg: root.snapAngleVal,
            kinetic_inertia: root.kineticInertiaVal,
            glide_friction: root.glideFrictionVal,
            exp_power: root.expPowerVal,
            sigmoid_mid: root.sigmoidMidVal,
            sigmoid_steep: root.sigmoidSteepVal,
            velocity_cap: root.velocityCapVal,
            gforce_gain: root.gforceGainVal,
            soft_edge_damp: root.softEdgeDampVal,
            curve_nodes: root.curveNodes
        }
        Quickshell.execDetached(["bash", "-c",
            "cat > /dev/shm/kinetix-config.json <<'KXEOF'\n"
            + JSON.stringify(doc) + "\nKXEOF\n"
            + "cp -f /dev/shm/kinetix-config.json \"$HOME/.config/kinetix-config.json\" 2>/dev/null"])
    }

    FileView {
        id: configStore
        path: Qt.resolvedUrl(Quickshell.env("HOME") + "/.config/kinetix-config.json")
        // Watched, not just read on open: the Settings page and the profile
        // switcher write this file too, and a panel that only read it at open
        // time sat showing stale values while the engine ran on something else.
        watchChanges: true
        onFileChanged: configStore.reload()
        onLoaded: root.adoptConfig(configStore.text())
    }


    Loader {
        active: GlobalStates.kinetixOpen

        sourceComponent: StackedSettingsPanel {
            panelId: "kinetix"
            title: Translation.tr("Pointer")
            icon: "mouse"
            onRequestClose: GlobalStates.kinetixOpen = false

            // ── Live readout ────────────────────────────────────────────
            Rectangle {
                Layout.fillWidth: true
                implicitHeight: 44
                radius: Appearance.rounding.small
                color: Appearance.colors.colLayer1
                RowLayout {
                    anchors { fill: parent; leftMargin: 12; rightMargin: 12 }
                    spacing: 10
                    MaterialSymbol {
                        text: root.engineEnabled ? "bolt" : "bolt_off"
                        iconSize: 18
                        color: root.engineEnabled ? Appearance.colors.colPrimary
                                                  : Appearance.colors.colSubtext
                    }
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 0
                        StyledText {
                            text: root.curveTypeVal === "linear"
                                ? Translation.tr("Linear — constant gain")
                                : Translation.tr("Bezier — gain follows speed")
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            color: Appearance.colors.colOnLayer1
                        }
                        StyledText {
                            // PointerLink, not a second FileView on the same
                            // file: the Bluetooth card wants these numbers too.
                            text: Translation.tr("%1 px/f · gain %2× · %3")
                                .arg(PointerLink.speed.toFixed(1))
                                .arg(PointerLink.gain.toFixed(2))
                                .arg(PointerLink.hz > 0
                                    ? Translation.tr("%1 Hz").arg(PointerLink.hz)
                                    : Translation.tr("no link"))
                            font.pixelSize: Appearance.font.pixelSize.smallest
                            font.family: Appearance.font.family.numbers
                            color: Appearance.colors.colSubtext
                        }
                    }
                    StyledSwitch {
                        checked: root.engineEnabled
                        onToggled: { root.engineEnabled = checked; root.saveConfig() }
                    }
                }
            }

            // ── Presets ─────────────────────────────────────────────────
            StyledText {
                text: Translation.tr("Presets")
                font.pixelSize: Appearance.font.pixelSize.smaller
                font.weight: Font.Bold
                font.letterSpacing: 1.2
                color: Appearance.colors.colPrimary
            }
            Flow {
                Layout.fillWidth: true
                spacing: 5
                Repeater {
                    model: KinetixProfiles.presets
                    delegate: Rectangle {
                        id: chip
                        required property var modelData
                        readonly property bool sel: modelData.id === "raw"
                            ? root.curveTypeVal === "linear"
                            : (root.curveTypeVal !== "linear"
                               && KinetixProfiles._lastPreset === modelData.id)
                        implicitHeight: 30
                        implicitWidth: chipRow.implicitWidth + 20
                        radius: Appearance.rounding.full
                        color: chip.sel ? Appearance.colors.colPrimary
                            : (chipHov.hovered ? Appearance.colors.colLayer2Hover
                                               : Appearance.colors.colLayer2)
                        Behavior on color { ColorAnimation { duration: 140 } }
                        HoverHandler { id: chipHov; cursorShape: Qt.PointingHandCursor }
                        TapHandler { onTapped: KinetixProfiles.applyPreset(chip.modelData.id) }
                        RowLayout {
                            id: chipRow
                            anchors.centerIn: parent
                            spacing: 6
                            MaterialSymbol {
                                text: chip.modelData.icon
                                iconSize: 15
                                color: chip.sel ? Appearance.colors.colOnPrimary
                                                : Appearance.colors.colOnLayer2
                            }
                            StyledText {
                                text: chip.modelData.name
                                font.pixelSize: Appearance.font.pixelSize.smaller
                                font.weight: Font.DemiBold
                                color: chip.sel ? Appearance.colors.colOnPrimary
                                                : Appearance.colors.colOnLayer2
                            }
                        }
                        StyledToolTip { text: chip.modelData.desc }
                    }
                }
            }

            // ── No curve ────────────────────────────────────────────────
            Rectangle {
                Layout.fillWidth: true
                implicitHeight: 52
                radius: Appearance.rounding.small
                color: Appearance.colors.colLayer1
                RowLayout {
                    anchors { fill: parent; leftMargin: 12; rightMargin: 12 }
                    spacing: 10
                    MaterialSymbol {
                        text: root.curveTypeVal === "linear" ? "linear_scale" : "show_chart"
                        iconSize: 17
                        color: root.curveTypeVal === "linear"
                            ? Appearance.colors.colPrimary : Appearance.colors.colSubtext
                    }
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 0
                        StyledText {
                            text: Translation.tr("No curve (constant gain)")
                            font.pixelSize: Appearance.font.pixelSize.small
                            color: Appearance.colors.colOnLayer1
                        }
                        StyledText {
                            text: root.curveTypeVal === "linear"
                                ? Translation.tr("gain = sensitivity, at every speed")
                                : Translation.tr("gain rises with pointer speed")
                            font.pixelSize: Appearance.font.pixelSize.smallest
                            color: Appearance.colors.colSubtext
                            elide: Text.ElideRight
                            Layout.fillWidth: true
                        }
                    }
                    StyledSwitch {
                        checked: root.curveTypeVal === "linear"
                        onToggled: {
                            root.curveTypeVal = checked ? "linear" : "bezier"
                            root.saveConfig()
                        }
                    }
                }
            }

            // ── Sliders ─────────────────────────────────────────────────
            KinetixSlider {
                label: Translation.tr("Master Sensitivity Gain")
                hint: Translation.tr("In linear mode this IS the gain. 1.00 is neutral.")
                from: 0.20; to: 3.00; suffix: "×"
                value: root.sensitivityVal
                onCommitted: v => { root.sensitivityVal = v; root.saveConfig() }
            }
            KinetixSlider {
                label: Translation.tr("Motion Rawness")
                // Named for what it does. The engine's field is `smoothness`
                // but its sense is inverted: tau = (1 - value) * 40ms, so 1.0
                // is no filter at all and 0.0 is the maximum 40ms lag.
                hint: Translation.tr("1.00 = no filtering (best for aiming). Lower adds lag.")
                from: 0.0; to: 1.0
                value: root.smoothnessVal
                onCommitted: v => { root.smoothnessVal = v; root.saveConfig() }
            }
            // ── Advanced ────────────────────────────────────────────────
            // Collapsed by default: these are the settings that make aiming
            // WORSE if you touch them without knowing why. Keeping them one tap
            // away rather than in the main list is the point.
            ExpandableSection {
                icon: "tune"
                title: Translation.tr("Advanced")
                summary: {
                    const on = [];
                    if (root.frictionVal > 0) on.push(Translation.tr("damping"));
                    if (root.angleSnapVal) on.push(Translation.tr("snapping"));
                    if (root.kineticInertiaVal) on.push(Translation.tr("glide"));
                    if (root.interpolationVal > 0) on.push(Translation.tr("smoothing"));
                    return on.length > 0 ? on.join(", ") : Translation.tr("all off");
                }
                contentComponent: ColumnLayout {
                    spacing: 10

                    KinetixSlider {
                        label: Translation.tr("Report Smoothing")
                        // Only worth anything on a slow link. At 111Hz over
                        // Bluetooth the cursor sits still for 9ms then jumps;
                        // this spreads that movement across the gap instead.
                        hint: Translation.tr("Spreads each report across the gap to the next. "
                            + "Costs up to one report interval of latency. 0 to disable.")
                        from: 0.0; to: 1.0
                        value: root.interpolationVal
                        onCommitted: v => { root.interpolationVal = v; root.saveConfig() }
                    }
                    KinetixSlider {
                        label: Translation.tr("Micro-Tremor Damping")
                        hint: Translation.tr("Below this speed gain is squared away. Eats fine aim.")
                        from: 0.0; to: 5.0; suffix: " px/f"
                        value: root.frictionVal
                        onCommitted: v => { root.frictionVal = v; root.saveConfig() }
                    }
                    KinetixToggle {
                        label: Translation.tr("Angle Snapping")
                        hint: Translation.tr("Straightens near-horizontal motion. Fatal to tracking.")
                        checked: root.angleSnapVal
                        onToggledValue: v => { root.angleSnapVal = v; root.saveConfig() }
                    }
                    KinetixToggle {
                        label: Translation.tr("Kinetic Glide")
                        hint: Translation.tr("The pointer coasts after you stop. Overshoots targets.")
                        checked: root.kineticInertiaVal
                        onToggledValue: v => { root.kineticInertiaVal = v; root.saveConfig() }
                    }
                }
            }

            // ── Connection ──────────────────────────────────────────────
            // The same facts the Bluetooth panel shows, from the same widget —
            // DPI decides how many counts exist for the curve to reshape, so
            // it belongs beside the curve, not only in a Bluetooth menu.
            ExpandableSection {
                icon: "settings_ethernet"
                title: Translation.tr("Connection")
                summary: LogiTune.available && LogiTune.dpi > 0
                    ? `${LogiTune.dpi} dpi` : Translation.tr("unknown")
                contentComponent: ColumnLayout {
                    spacing: 10

                    PointerDeviceInfo {
                        Layout.fillWidth: true
                        transport: Translation.tr("Bluetooth")
                    }

                    Rectangle {
                        Layout.fillWidth: true
                        implicitHeight: 1
                        color: Appearance.colors.colLayer0Border
                    }

                    KinetixSlider {
                        label: Translation.tr("Sensor DPI")
                        // Applied on release only: each change is an HID++
                        // round-trip over Bluetooth taking seconds, so a
                        // per-pixel binding would queue dozens of writes.
                        hint: LogiTune.busy
                            ? Translation.tr("Applying… (HID++ over Bluetooth is slow)")
                            : Translation.tr("Higher = finer resolution, but more counts per "
                                + "report on a slow link. Lower the gain to match.")
                        from: LogiTune.minDpi; to: LogiTune.maxDpi
                        value: LogiTune.dpi > 0 ? LogiTune.dpi : 1000
                        onCommitted: v => LogiTune.setDpi(v)
                    }

                    // Raising DPI without lowering gain makes the pointer
                    // proportionally faster — the single most common way to
                    // make aiming worse while thinking you improved it.
                    RippleButtonWithIcon {
                        Layout.fillWidth: true
                        visible: LogiTune.available && LogiTune.dpi > 0
                        materialIcon: "balance"
                        mainText: Translation.tr("Match gain to 3500 dpi feel")
                        onClicked: {
                            root.sensitivityVal = Math.round(
                                (root.sensitivityVal * 3500 / LogiTune.dpi) * 10000) / 10000;
                            root.saveConfig();
                        }
                        StyledToolTip {
                            text: Translation.tr("Scales the gain so cursor speed stays where it was")
                        }
                    }
                }
            }
        }
    }
}
