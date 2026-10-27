pragma ComponentBehavior: Bound
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.walltune
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Widgets

/**
 * Per-app firewall (OpenSnitch) — apps and their connections, incoming ports,
 * and a log. Data and commands go through services/Firewall.qml.
 */
Scope {
    id: root

    component Caption: StyledText {
        Layout.fillWidth: true
        Layout.leftMargin: 4
        Layout.bottomMargin: -6
        font.pixelSize: Appearance.font.pixelSize.smallest
        font.weight: Font.Medium
        color: Appearance.colors.colSubtext
    }

    // Small segmented chooser: [{ id, label }]
    component Chips: RowLayout {
        id: chips
        property var items: []
        property string current: ""
        signal picked(string id)
        Layout.fillWidth: true
        spacing: 4
        Repeater {
            model: chips.items
            delegate: RippleButton {
                required property var modelData
                readonly property bool sel: chips.current === modelData.id
                Layout.fillWidth: true
                Layout.preferredWidth: 1   // equal widths
                implicitHeight: 32
                buttonRadius: Appearance.rounding.verysmall
                colBackground: sel ? Appearance.colors.colPrimary : Qt.alpha(Appearance.colors.colOnLayer1, 0.07)
                colBackgroundHover: sel ? Appearance.colors.colPrimary : Qt.alpha(Appearance.colors.colOnLayer1, 0.12)
                onClicked: chips.picked(modelData.id)
                contentItem: StyledText {
                    text: modelData.label
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    font.weight: Font.Medium
                    color: parent.sel ? Appearance.colors.colOnPrimary : Appearance.colors.colOnLayer1
                }
            }
        }
    }

    readonly property var actionColor: ({
        allow: Appearance.m3colors.m3primary,
        ask: Appearance.m3colors.m3tertiary,
        block: Appearance.m3colors.m3error,
    })

    IpcHandler {
        target: "firewall"
        function toggle(): void { GlobalStates.firewallOpen = !GlobalStates.firewallOpen }
        function open(): void   { GlobalStates.firewallOpen = true }
        function close(): void  { GlobalStates.firewallOpen = false }
        /// apps | conns | rules | stats | incoming
        function tab(name: string): void { Firewall.panelTab = name }
    }

    StackedPanelLoader {
        isOpen: GlobalStates.firewallOpen

        sourceComponent: StackedSettingsPanel {
            id: win
            panelId: "firewall"
            title: Translation.tr("Firewall")
            icon: "shield"
            onRequestClose: GlobalStates.firewallOpen = false

            // Vitals has apps only: no connection log, rules, stats or ports
            readonly property string tab: Firewall.vitalsEngine ? "apps" : Firewall.panelTab
            property string expanded: ""

            Component.onCompleted: Firewall.watching = true
            Component.onDestruction: Firewall.watching = false

            // ── Status ───────────────────────────────────────────────────
            PaletteCard {
                // Vitals filtering while OpenSnitch is stopped
                PaletteRow {
                    visible: Firewall.vitalsEngine
                    glyph: "shield_lock"
                    title: Translation.tr("Firewall on · Vitals")
                    subtitle: Translation.tr("%1 apps · %2 blocked · loopback stays open").arg(Firewall.apps.length).arg(Firewall.apps.filter(a => a.action === "block").length)
                    trailing: ""
                    lit: true
                }
                PaletteDivider { visible: Firewall.vitalsEngine }
                PaletteRow {
                    visible: Firewall.vitalsEngine
                    glyph: "swap_horiz"
                    title: Translation.tr("Use OpenSnitch instead")
                    subtitle: Translation.tr("Prompts, rules, a connection log and stats")
                    trailing: "switch"
                    isOn: false
                    enabled: Firewall.busy === ""
                    onSwitched: Firewall.startEngine()
                }
                PaletteRow {
                    readonly property bool ok: Firewall.engineRunning && !Firewall.stalled
                    visible: !Firewall.vitalsEngine
                    glyph: !Firewall.engineRunning ? "remove_moderator" : Firewall.stalled ? "gpp_maybe" : "shield_lock"
                    title: Firewall.busy ? Translation.tr("Working…")
                        : !Firewall.engineRunning ? Translation.tr("Firewall off")
                        : Firewall.stalled ? Translation.tr("Not connected")
                        : Translation.tr("Firewall on")
                    subtitle: !Firewall.engineRunning ? Translation.tr("Engine stopped — nothing is filtered")
                        : Firewall.stalled ? Translation.tr("Engine runs without this panel")
                        : Translation.tr("%1 apps · %2 blocked today").arg(Firewall.apps.length).arg(Firewall.blockedToday)
                    trailing: "switch"
                    isOn: Firewall.engineRunning
                    lit: ok
                    enabled: Firewall.busy === ""
                    onSwitched: isOn ? Firewall.stopEngine() : Firewall.startEngine()
                }

                // Running but not connected: new connections wait for a UI that
                // never answers — games can stall or crash while loading.
                Rectangle {
                    visible: Firewall.stalled
                    Layout.fillWidth: true
                    Layout.leftMargin: 10
                    Layout.rightMargin: 10
                    Layout.bottomMargin: 6
                    implicitHeight: warnCol.implicitHeight + 20
                    radius: Appearance.rounding.small
                    color: Qt.alpha(Appearance.m3colors.m3error, 0.12)
                    border.width: 1
                    border.color: Qt.alpha(Appearance.m3colors.m3error, 0.35)
                    ColumnLayout {
                        id: warnCol
                        anchors { left: parent.left; right: parent.right; top: parent.top; margins: 10 }
                        spacing: 8
                        RowLayout {
                            spacing: 8
                            MaterialSymbol { text: "warning"; iconSize: 18; color: Appearance.m3colors.m3error }
                            StyledText {
                                Layout.fillWidth: true
                                wrapMode: Text.Wrap
                                font.pixelSize: Appearance.font.pixelSize.smaller
                                color: Appearance.colors.colOnLayer1
                                text: Firewall.addressOk
                                    ? Translation.tr("The engine cannot reach this panel. New connections wait for an answer, so games may stall or crash while loading.")
                                    : Translation.tr("The engine still points to its old address. New connections wait for an answer, so games may stall or crash while loading.")
                            }
                        }
                        RowLayout {
                            spacing: 6
                            RippleButton {
                                implicitHeight: 30
                                implicitWidth: fixLabel.implicitWidth + 24
                                buttonRadius: Appearance.rounding.verysmall
                                colBackground: Appearance.colors.colPrimary
                                colBackgroundHover: Appearance.colors.colPrimaryHover
                                enabled: Firewall.busy === ""
                                onClicked: Firewall.fixAddress()
                                contentItem: StyledText {
                                    id: fixLabel
                                    text: Translation.tr("Fix connection")
                                    horizontalAlignment: Text.AlignHCenter
                                    verticalAlignment: Text.AlignVCenter
                                    font.pixelSize: Appearance.font.pixelSize.smaller
                                    color: Appearance.colors.colOnPrimary
                                }
                            }
                            RippleButton {
                                implicitHeight: 30
                                implicitWidth: stopLabel.implicitWidth + 24
                                buttonRadius: Appearance.rounding.verysmall
                                colBackground: Qt.alpha(Appearance.colors.colOnLayer1, 0.08)
                                colBackgroundHover: Qt.alpha(Appearance.colors.colOnLayer1, 0.14)
                                enabled: Firewall.busy === ""
                                onClicked: Firewall.stopEngine()
                                contentItem: StyledText {
                                    id: stopLabel
                                    text: Translation.tr("Stop engine")
                                    horizontalAlignment: Text.AlignHCenter
                                    verticalAlignment: Text.AlignVCenter
                                    font.pixelSize: Appearance.font.pixelSize.smaller
                                    color: Appearance.colors.colOnLayer1
                                }
                            }
                        }
                    }
                }
                PaletteDivider { visible: !Firewall.vitalsEngine }
                PaletteRow {
                    visible: !Firewall.vitalsEngine
                    glyph: "power_settings_new"
                    title: Translation.tr("Start with the system")
                    subtitle: Translation.tr("Engine starts at boot")
                    trailing: "switch"
                    isOn: Firewall.engineAutostart
                    lit: isOn
                    enabled: Firewall.busy === ""
                    onSwitched: Firewall.setAutostart(!isOn)
                }
                PaletteDivider { visible: !Firewall.vitalsEngine }
                ColumnLayout {
                    visible: !Firewall.vitalsEngine
                    Layout.fillWidth: true
                    Layout.margins: 10
                    spacing: 6
                    Chips {
                        items: [
                            { id: "learn", label: Translation.tr("Learn") },
                            { id: "ask", label: Translation.tr("Ask") },
                            { id: "block", label: Translation.tr("Block new") },
                        ]
                        current: Firewall.mode
                        onPicked: id => Firewall.setMode(id)
                    }
                    StyledText {
                        Layout.fillWidth: true
                        wrapMode: Text.Wrap
                        font.pixelSize: Appearance.font.pixelSize.smallest
                        color: Appearance.colors.colSubtext
                        text: Firewall.mode === "learn" ? Translation.tr("Everything is allowed and recorded. Nothing is blocked.")
                            : Firewall.mode === "ask" ? Translation.tr("A new app asks before its first connection. No answer within 30 s = allow.")
                            : Translation.tr("New apps are blocked until you allow them. Known apps keep their rule.")
                    }
                }
            }

            // Sample data until the engine is connected.
            Rectangle {
                visible: Firewall.demo
                Layout.fillWidth: true
                implicitHeight: demoText.implicitHeight + 14
                radius: Appearance.rounding.small
                color: Qt.alpha(Appearance.m3colors.m3tertiary, 0.12)
                StyledText {
                    id: demoText
                    anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter; margins: 10 }
                    wrapMode: Text.Wrap
                    font.pixelSize: Appearance.font.pixelSize.smallest
                    color: Appearance.colors.colOnLayer1
                    text: Translation.tr("PREVIEW — sample data below. Your real apps, connections and rules appear once the engine is running and connected.")
                }
            }

            // ── Traffic ──────────────────────────────────────────────────
            PaletteCard {
                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.margins: 12
                    spacing: 10

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 8
                        Repeater {
                            model: [
                                { label: Translation.tr("DOWN"), value: Firewall.fmtRate(Firewall.totalDown), c: Appearance.m3colors.m3primary },
                                { label: Translation.tr("UP"), value: Firewall.fmtRate(Firewall.totalUp), c: Appearance.m3colors.m3tertiary },
                                { label: Translation.tr("CONN"), value: String(Firewall.totalConns), c: Appearance.colors.colOnLayer1 },
                                { label: Translation.tr("BLOCKED"), value: String(Firewall.blockedToday), c: Appearance.m3colors.m3error },
                            ]
                            delegate: ColumnLayout {
                                required property var modelData
                                Layout.fillWidth: true
                                Layout.preferredWidth: 1
                                spacing: 0
                                StyledText {
                                    text: modelData.label
                                    font.pixelSize: 9
                                    font.weight: Font.DemiBold
                                    font.letterSpacing: 1.2
                                    color: Appearance.colors.colSubtext
                                }
                                StyledText {
                                    text: modelData.value
                                    font.family: Appearance.font.family.monospace
                                    font.pixelSize: Appearance.font.pixelSize.normal
                                    font.weight: Font.Medium
                                    color: modelData.c
                                }
                            }
                        }
                    }

                    // 60 s of down (filled) and up (line), shared scale.
                    Canvas {
                        id: graph
                        Layout.fillWidth: true
                        implicitHeight: 64
                        readonly property var h: Firewall.history
                        readonly property color cDown: Appearance.m3colors.m3primary
                        readonly property color cUp: Appearance.m3colors.m3tertiary
                        readonly property color cGrid: Qt.alpha(Appearance.colors.colOnLayer1, 0.08)
                        onHChanged: requestPaint()
                        onWidthChanged: requestPaint()
                        onPaint: {
                            const ctx = getContext("2d");
                            ctx.reset();
                            const w = width, ht = height;
                            ctx.strokeStyle = cGrid;
                            ctx.lineWidth = 1;
                            for (let i = 1; i < 4; i++) {
                                const y = Math.round(ht * i / 4) + 0.5;
                                ctx.beginPath(); ctx.moveTo(0, y); ctx.lineTo(w, y); ctx.stroke();
                            }
                            if (h.length < 2) return;
                            const max = Math.max(1, ...h.map(p => Math.max(p.down, p.up))) * 1.15;
                            const x = i => w - (h.length - 1 - i) * (w / 59);
                            const y = v => ht - v / max * ht;
                            ctx.beginPath();
                            ctx.moveTo(x(0), ht);
                            h.forEach((p, i) => ctx.lineTo(x(i), y(p.down)));
                            ctx.lineTo(x(h.length - 1), ht);
                            ctx.closePath();
                            ctx.fillStyle = Qt.alpha(cDown, 0.22);
                            ctx.fill();
                            ctx.beginPath();
                            h.forEach((p, i) => i ? ctx.lineTo(x(i), y(p.down)) : ctx.moveTo(x(i), y(p.down)));
                            ctx.strokeStyle = cDown; ctx.lineWidth = 1.5; ctx.stroke();
                            ctx.beginPath();
                            h.forEach((p, i) => i ? ctx.lineTo(x(i), y(p.up)) : ctx.moveTo(x(i), y(p.up)));
                            ctx.strokeStyle = cUp; ctx.lineWidth = 1.2; ctx.stroke();
                        }
                    }
                    StyledText {
                        Layout.alignment: Qt.AlignRight
                        Layout.topMargin: -6
                        text: Translation.tr("last 60 s")
                        font.pixelSize: 9
                        color: Appearance.colors.colSubtext
                    }
                }
            }

            // ── Tabs ─────────────────────────────────────────────────────
            Chips {
                items: [
                    { id: "apps", label: Translation.tr("Apps") },
                    { id: "conns", label: Translation.tr("Conns") },
                    { id: "rules", label: Translation.tr("Rules") },
                    { id: "stats", label: Translation.tr("Stats") },
                    { id: "incoming", label: Translation.tr("Ports") },
                ]
                current: win.tab
                onPicked: id => Firewall.panelTab = id
            }

            // ── Apps ─────────────────────────────────────────────────────
            PaletteCard {
                visible: win.tab === "apps"
                Repeater {
                    model: win.tab === "apps" ? Firewall.apps : []
                    delegate: ColumnLayout {
                        id: app
                        required property var modelData
                        required property int index
                        readonly property bool open: win.expanded === modelData.path
                        Layout.fillWidth: true
                        spacing: 0

                        PaletteDivider { visible: app.index > 0 }
                        RippleButton {
                            Layout.fillWidth: true
                            implicitHeight: 48
                            buttonRadius: Appearance.rounding.small
                            colBackground: "transparent"
                            colBackgroundHover: Appearance.colors.colLayer1Hover
                            onClicked: win.expanded = app.open ? "" : app.modelData.path

                            contentItem: RowLayout {
                                spacing: 10
                                IconImage {
                                    Layout.leftMargin: 10
                                    implicitSize: 22
                                    source: Quickshell.iconPath(app.modelData.icon || "application-x-executable", "application-x-executable")
                                }
                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 0
                                    StyledText {
                                        Layout.fillWidth: true
                                        elide: Text.ElideRight
                                        text: app.modelData.name
                                        font.pixelSize: Appearance.font.pixelSize.small
                                        color: Appearance.m3colors.m3onSurface
                                    }
                                    StyledText {
                                        Layout.fillWidth: true
                                        elide: Text.ElideRight
                                        font.family: Appearance.font.family.monospace
                                        font.pixelSize: Appearance.font.pixelSize.smallest
                                        color: Appearance.colors.colSubtext
                                        text: `↓ ${Firewall.fmtRate(app.modelData.down)}  ↑ ${Firewall.fmtRate(app.modelData.up)}  · ${app.modelData.conns} conn`
                                    }
                                    Rectangle {
                                        Layout.fillWidth: true
                                        Layout.topMargin: 3
                                        implicitHeight: 2
                                        radius: 1
                                        color: Qt.alpha(Appearance.colors.colOnLayer1, 0.08)
                                        Rectangle {
                                            readonly property real share: Firewall.share(app.modelData)
                                            width: parent.width * Math.min(1, share)
                                            height: parent.height
                                            radius: 1
                                            color: root.actionColor[app.modelData.action] ?? Appearance.colors.colSubtext
                                            Behavior on width { NumberAnimation { duration: 400; easing.type: Easing.OutCubic } }
                                        }
                                    }
                                }
                                // allow → ask → block (Vitals: allow ↔ block, and only for your own apps)
                                RippleButton {
                                    visible: !Firewall.vitalsEngine || app.modelData.own !== false
                                    Layout.rightMargin: 8
                                    implicitWidth: 64
                                    implicitHeight: 26
                                    buttonRadius: Appearance.rounding.verysmall
                                    readonly property color c: root.actionColor[app.modelData.action] ?? Appearance.colors.colSubtext
                                    colBackground: Qt.alpha(c, 0.16)
                                    colBackgroundHover: Qt.alpha(c, 0.26)
                                    onClicked: {
                                        const next = Firewall.vitalsEngine ? (app.modelData.action === "block" ? "allow" : "block")
                                            : { allow: "ask", ask: "block", block: "allow" }[app.modelData.action] ?? "allow";
                                        Firewall.setAppAction(app.modelData.path, next);
                                    }
                                    contentItem: StyledText {
                                        text: ({ allow: Translation.tr("allow"), ask: Translation.tr("ask"), block: Translation.tr("block") })[app.modelData.action] ?? app.modelData.action
                                        horizontalAlignment: Text.AlignHCenter
                                        verticalAlignment: Text.AlignVCenter
                                        font.pixelSize: Appearance.font.pixelSize.smaller
                                        font.weight: Font.Medium
                                        color: parent.c
                                    }
                                }
                            }
                        }
                        // Destinations
                        ColumnLayout {
                            visible: app.open
                            Layout.fillWidth: true
                            Layout.leftMargin: 42
                            Layout.rightMargin: 10
                            Layout.bottomMargin: 8
                            spacing: 2
                            Repeater {
                                model: app.modelData.hosts
                                delegate: StyledText {
                                    required property string modelData
                                    Layout.fillWidth: true
                                    elide: Text.ElideMiddle
                                    text: modelData
                                    font.family: Appearance.font.family.monospace
                                    font.pixelSize: Appearance.font.pixelSize.smallest
                                    color: Appearance.colors.colSubtext
                                }
                            }
                            StyledText {
                                Layout.topMargin: 2
                                elide: Text.ElideMiddle
                                Layout.fillWidth: true
                                text: app.modelData.path
                                font.family: Appearance.font.family.monospace
                                font.pixelSize: Appearance.font.pixelSize.smallest
                                color: Qt.alpha(Appearance.colors.colSubtext, 0.7)
                            }
                        }
                    }
                }
            }

            // ── Connections ──────────────────────────────────────────────
            ToolbarTextField {
                id: connFilter
                visible: win.tab === "conns"
                Layout.fillWidth: true
                placeholderText: Translation.tr("Filter: app, host, IP, port, uid, pid, allow/block…")
            }
            PaletteCard {
                visible: win.tab === "conns"
                Repeater {
                    model: {
                        if (win.tab !== "conns") return [];
                        const q = connFilter.text.trim().toLowerCase();
                        if (!q) return Firewall.events;
                        const terms = q.split(/\s+/);
                        return Firewall.events.filter(e => {
                            const hay = `${e.app} ${e.path} ${e.host} ${e.dst} ${e.dport} ${e.src} ${e.sport} ${e.proto} uid${e.uid} ${e.uid} pid${e.pid} ${e.pid} ${e.verdict} ${e.rule}`.toLowerCase();
                            return terms.every(t => hay.includes(t));
                        });
                    }
                    delegate: ColumnLayout {
                        id: ev
                        required property var modelData
                        required property int index
                        readonly property bool open: win.expanded === "ev" + index
                        Layout.fillWidth: true
                        spacing: 0
                        PaletteDivider { visible: ev.index > 0 }
                        RippleButton {
                            Layout.fillWidth: true
                            implicitHeight: evCol.implicitHeight + 12
                            buttonRadius: Appearance.rounding.small
                            colBackground: "transparent"
                            colBackgroundHover: Appearance.colors.colLayer1Hover
                            onClicked: win.expanded = ev.open ? "" : "ev" + ev.index
                            contentItem: ColumnLayout {
                                id: evCol
                                spacing: 1
                                RowLayout {
                                    Layout.leftMargin: 10
                                    Layout.rightMargin: 10
                                    spacing: 6
                                    Rectangle { implicitWidth: 6; implicitHeight: 6; radius: 3; color: root.actionColor[ev.modelData.verdict] ?? Appearance.colors.colSubtext }
                                    StyledText { text: ev.modelData.t; font.family: Appearance.font.family.monospace; font.pixelSize: Appearance.font.pixelSize.smallest; color: Appearance.colors.colSubtext }
                                    StyledText { text: String(ev.modelData.proto).toUpperCase(); font.family: Appearance.font.family.monospace; font.pixelSize: Appearance.font.pixelSize.smallest; color: Appearance.colors.colSubtext }
                                    StyledText { Layout.fillWidth: true; elide: Text.ElideRight; text: ev.modelData.app; font.pixelSize: Appearance.font.pixelSize.smaller; color: Appearance.m3colors.m3onSurface }
                                    StyledText { text: `uid ${ev.modelData.uid} · pid ${ev.modelData.pid}`; font.family: Appearance.font.family.monospace; font.pixelSize: Appearance.font.pixelSize.smallest; color: Appearance.colors.colSubtext }
                                }
                                StyledText {
                                    Layout.fillWidth: true
                                    Layout.leftMargin: 22
                                    Layout.rightMargin: 10
                                    elide: Text.ElideMiddle
                                    text: `${ev.modelData.src}:${ev.modelData.sport} → ${ev.modelData.host ? ev.modelData.host + " (" + ev.modelData.dst + ")" : ev.modelData.dst}:${ev.modelData.dport}`
                                    font.family: Appearance.font.family.monospace
                                    font.pixelSize: Appearance.font.pixelSize.smallest
                                    color: Appearance.colors.colOnLayer1
                                }
                            }
                        }
                        GridLayout {
                            visible: ev.open
                            Layout.fillWidth: true
                            Layout.leftMargin: 22
                            Layout.rightMargin: 10
                            Layout.bottomMargin: 8
                            columns: 2
                            columnSpacing: 8
                            rowSpacing: 2
                            Repeater {
                                model: [
                                    ["rule", ev.modelData.rule || "—"],
                                    ["path", ev.modelData.path],
                                    ["cmd", ev.modelData.args || "—"],
                                    ["cwd", ev.modelData.cwd || "—"],
                                ]
                                delegate: Item {
                                    required property var modelData
                                    Layout.columnSpan: 2
                                    Layout.fillWidth: true
                                    implicitHeight: kvRow.implicitHeight
                                    RowLayout {
                                        id: kvRow
                                        anchors.left: parent.left
                                        anchors.right: parent.right
                                        spacing: 8
                                        StyledText { Layout.preferredWidth: 34; text: modelData[0].toUpperCase(); font.pixelSize: 9; font.weight: Font.DemiBold; font.letterSpacing: 1; color: Appearance.colors.colSubtext }
                                        StyledText { Layout.fillWidth: true; wrapMode: Text.WrapAnywhere; maximumLineCount: 3; elide: Text.ElideRight; text: modelData[1]; font.family: Appearance.font.family.monospace; font.pixelSize: Appearance.font.pixelSize.smallest; color: Appearance.colors.colOnLayer1 }
                                    }
                                }
                            }
                        }
                    }
                }
            }

            // ── Rules ────────────────────────────────────────────────────
            PaletteCard {
                visible: win.tab === "rules"
                Repeater {
                    model: win.tab === "rules" ? Firewall.ruleList : []
                    delegate: ColumnLayout {
                        id: rl
                        required property var modelData
                        required property int index
                        Layout.fillWidth: true
                        spacing: 0
                        PaletteDivider { visible: rl.index > 0 }
                        RowLayout {
                            Layout.fillWidth: true
                            Layout.margins: 10
                            spacing: 8
                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 2
                                RowLayout {
                                    spacing: 6
                                    Rectangle {
                                        implicitWidth: actLbl.implicitWidth + 10
                                        implicitHeight: 18
                                        radius: 3
                                        readonly property color c: rl.modelData.action === "allow" ? Appearance.m3colors.m3primary : Appearance.m3colors.m3error
                                        color: Qt.alpha(c, 0.16)
                                        StyledText { id: actLbl; anchors.centerIn: parent; text: rl.modelData.action.toUpperCase(); font.pixelSize: 9; font.weight: Font.DemiBold; font.letterSpacing: 1; color: parent.c }
                                    }
                                    StyledText { Layout.fillWidth: true; elide: Text.ElideRight; text: rl.modelData.name; font.pixelSize: Appearance.font.pixelSize.smaller; color: rl.modelData.enabled ? Appearance.m3colors.m3onSurface : Appearance.colors.colSubtext }
                                }
                                StyledText {
                                    Layout.fillWidth: true
                                    wrapMode: Text.WrapAnywhere
                                    text: rl.modelData.condition
                                    font.family: Appearance.font.family.monospace
                                    font.pixelSize: Appearance.font.pixelSize.smallest
                                    color: Appearance.colors.colOnLayer1
                                }
                                StyledText {
                                    text: [rl.modelData.duration, rl.modelData.precedence ? "priority" : "", rl.modelData.nolog ? "no log" : ""].filter(x => x).join(" · ")
                                    font.pixelSize: Appearance.font.pixelSize.smallest
                                    color: Appearance.colors.colSubtext
                                }
                            }
                            StyledSwitch {
                                checked: rl.modelData.enabled
                                onClicked: Firewall.setRuleEnabled(rl.modelData.name, checked)
                            }
                            RippleButton {
                                implicitWidth: 30
                                implicitHeight: 30
                                buttonRadius: Appearance.rounding.verysmall
                                colBackground: "transparent"
                                colBackgroundHover: Qt.alpha(Appearance.m3colors.m3error, 0.14)
                                onClicked: Firewall.deleteRule(rl.modelData.name)
                                contentItem: MaterialSymbol { anchors.centerIn: parent; text: "delete"; iconSize: 18; color: Appearance.colors.colSubtext }
                            }
                        }
                    }
                }
            }

            // ── Stats ────────────────────────────────────────────────────
            PaletteCard {
                visible: win.tab === "stats"
                GridLayout {
                    Layout.fillWidth: true
                    Layout.margins: 12
                    columns: 4
                    columnSpacing: 8
                    rowSpacing: 10
                    Repeater {
                        model: {
                            if (win.tab !== "stats") return [];
                            const s = Firewall.stats;
                            const up = s.uptime ?? 0;
                            return [
                                ["CONNS", s.connections], ["ACCEPTED", s.accepted], ["DROPPED", s.dropped], ["IGNORED", s.ignored],
                                ["DNS", s.dns], ["RULE HITS", s.ruleHits], ["MISSES", s.ruleMisses],
                                ["UPTIME", `${Math.floor(up / 3600)}h${String(Math.floor(up / 60) % 60).padStart(2, "0")}`],
                            ];
                        }
                        delegate: ColumnLayout {
                            required property var modelData
                            Layout.fillWidth: true
                            Layout.preferredWidth: 1
                            spacing: 0
                            StyledText { text: modelData[0]; font.pixelSize: 9; font.weight: Font.DemiBold; font.letterSpacing: 1.1; color: Appearance.colors.colSubtext }
                            StyledText { text: String(modelData[1] ?? "—"); font.family: Appearance.font.family.monospace; font.pixelSize: Appearance.font.pixelSize.small; color: modelData[0] === "DROPPED" ? Appearance.m3colors.m3error : Appearance.m3colors.m3onSurface }
                        }
                    }
                }
                StyledText {
                    Layout.leftMargin: 12
                    Layout.bottomMargin: 10
                    text: `opensnitchd ${Firewall.stats.daemonVersion || "—"} · ${Firewall.stats.rules ?? 0} rules`
                    font.family: Appearance.font.family.monospace
                    font.pixelSize: Appearance.font.pixelSize.smallest
                    color: Appearance.colors.colSubtext
                }
            }
            Repeater {
                model: [
                    ["Top hosts", "byHost"], ["Top ports", "byPort"], ["Programs", "byExecutable"],
                    ["Protocols", "byProto"], ["Users (uid)", "byUid"],
                ]
                delegate: ColumnLayout {
                    id: topList
                    required property var modelData
                    readonly property var rows: win.tab === "stats" ? (Firewall.stats[modelData[1]] ?? []) : []
                    readonly property real maxCount: Math.max(1, ...rows.map(r => r.count))
                    visible: win.tab === "stats" && rows.length > 0
                    Layout.fillWidth: true
                    spacing: 4
                    Caption { text: topList.modelData[0] }
                    PaletteCard {
                        ColumnLayout {
                            Layout.fillWidth: true
                            Layout.margins: 10
                            spacing: 5
                            Repeater {
                                model: topList.rows
                                delegate: ColumnLayout {
                                    required property var modelData
                                    Layout.fillWidth: true
                                    spacing: 2
                                    RowLayout {
                                        Layout.fillWidth: true
                                        StyledText { Layout.fillWidth: true; elide: Text.ElideMiddle; text: modelData.key; font.family: Appearance.font.family.monospace; font.pixelSize: Appearance.font.pixelSize.smallest; color: Appearance.colors.colOnLayer1 }
                                        StyledText { text: String(modelData.count); font.family: Appearance.font.family.monospace; font.pixelSize: Appearance.font.pixelSize.smallest; color: Appearance.colors.colSubtext }
                                    }
                                    Rectangle {
                                        Layout.fillWidth: true
                                        implicitHeight: 2
                                        radius: 1
                                        color: Qt.alpha(Appearance.colors.colOnLayer1, 0.08)
                                        Rectangle { width: parent.width * modelData.count / topList.maxCount; height: 2; radius: 1; color: Appearance.m3colors.m3primary }
                                    }
                                }
                            }
                        }
                    }
                }
            }

            // ── Incoming ─────────────────────────────────────────────────
            Caption { visible: win.tab === "incoming"; text: Translation.tr("Profile") }
            Chips {
                visible: win.tab === "incoming"
                items: [
                    { id: "home", label: Translation.tr("Home") },
                    { id: "public", label: Translation.tr("Public") },
                    { id: "gaming", label: Translation.tr("Gaming") },
                ]
                current: Firewall.profile
                onPicked: id => Firewall.setProfile(id)
            }
            Caption { visible: win.tab === "incoming"; text: Translation.tr("Open ports — everything else incoming is blocked") }
            PaletteCard {
                visible: win.tab === "incoming"
                Repeater {
                    model: win.tab === "incoming" ? Firewall.ports : []
                    delegate: ColumnLayout {
                        required property var modelData
                        required property int index
                        Layout.fillWidth: true
                        spacing: 0
                        PaletteDivider { visible: index > 0 }
                        PaletteRow {
                            glyph: modelData.open ? "lock_open" : "lock"
                            title: modelData.name
                            subtitle: modelData.detail
                            trailing: "switch"
                            isOn: modelData.open
                            lit: isOn
                            onSwitched: Firewall.setPort(modelData.id, !isOn)
                        }
                    }
                }
            }

            // ── Log ──────────────────────────────────────────────────────
            PaletteCard {
                visible: win.tab === "log"
                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.margins: 10
                    spacing: 6
                    Repeater {
                        model: win.tab === "log" ? Firewall.log : []
                        delegate: RowLayout {
                            required property var modelData
                            Layout.fillWidth: true
                            spacing: 8
                            Rectangle {
                                implicitWidth: 6; implicitHeight: 6; radius: 3
                                color: root.actionColor[modelData.verdict] ?? Appearance.colors.colSubtext
                            }
                            StyledText {
                                text: modelData.t
                                font.family: Appearance.font.family.monospace
                                font.pixelSize: Appearance.font.pixelSize.smallest
                                color: Appearance.colors.colSubtext
                            }
                            StyledText {
                                text: modelData.app
                                font.pixelSize: Appearance.font.pixelSize.smaller
                                color: Appearance.colors.colOnLayer1
                            }
                            StyledText {
                                Layout.fillWidth: true
                                elide: Text.ElideMiddle
                                text: modelData.dest
                                font.family: Appearance.font.family.monospace
                                font.pixelSize: Appearance.font.pixelSize.smallest
                                color: Appearance.colors.colSubtext
                            }
                        }
                    }
                }
            }
        }
    }
}
