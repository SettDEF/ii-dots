import qs
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io

Item {
    id: root
    implicitHeight: layoutCol.implicitHeight + 16

    // ── Live state ────────────────────────────────────────────────────────────
    property string activeTags: ""           // space-separated
    property string activeDescription: ""    // first annotation
    property int    activeStartEpoch: 0      // unix epoch seconds, 0 if idle
    property string todaySummary: ""         // raw text from `timew summary :day`
    property bool   running: activeStartEpoch > 0

    // Updated once per second only while running, only when sidebar is open.
    property int _now: Math.floor(Date.now() / 1000)
    Timer {
        interval: 1000
        repeat: true
        running: root.running && GlobalStates.sidebarRightOpen
        onTriggered: root._now = Math.floor(Date.now() / 1000)
    }

    function fmtDuration(seconds) {
        if (seconds <= 0) return "00:00:00"
        const h = Math.floor(seconds / 3600)
        const m = Math.floor((seconds % 3600) / 60)
        const s = seconds % 60
        const pad = n => (n < 10 ? "0" : "") + n
        return pad(h) + ":" + pad(m) + ":" + pad(s)
    }
    readonly property string elapsed: running ? fmtDuration(_now - activeStartEpoch) : "—"

    // ── Polling ───────────────────────────────────────────────────────────────
    // Single bash that prints either "" (no active) or "<epoch>\n<tags>\n<desc>"
    Process {
        id: activeProc
        stdout: StdioCollector {
            onStreamFinished: {
                const text = (this.text || "").trim()
                if (!text) {
                    root.activeStartEpoch = 0
                    root.activeTags = ""
                    root.activeDescription = ""
                    return
                }
                const lines = text.split("\n")
                root.activeStartEpoch = parseInt(lines[0]) || 0
                root.activeTags       = lines[1] || ""
                root.activeDescription = lines.slice(2).join(" ") || ""
            }
        }
    }
    property bool toolMissing: false
    /// [{ tag, seconds }] for today, biggest first, plus the totals.
    property var todayRows: []
    property real todayTotal: 0
    property string lastTag: ""

    // timew stamps are "20260925T222239Z" — not ISO, so Date can't take them.
    function _stamp(v) {
        if (!v || v.length < 15) return null;
        return new Date(`${v.slice(0,4)}-${v.slice(4,6)}-${v.slice(6,8)}`
            + `T${v.slice(9,11)}:${v.slice(11,13)}:${v.slice(13,15)}Z`);
    }
    Process {
        id: summaryProc
        stdout: StdioCollector {
            onStreamFinished: {
                const t = (this.text || "").trim()
                if (t === "__NOTOOL__") {
                    root.toolMissing = true
                    root.todaySummary = ""
                    return
                }
                root.toolMissing = false
                // `timew export` is JSON; the old `timew summary` was an ASCII
                // table, which is why this card used to render as terminal
                // output. Aggregate per tag so the UI can lay it out.
                let data = [];
                try { data = JSON.parse(t || "[]") ?? []; } catch (e) { data = []; }
                const byTag = ({});
                let total = 0, last = "";
                for (const entry of data) {
                    const from = root._stamp(entry.start);
                    if (!from) continue;
                    const to = entry.end ? root._stamp(entry.end) : new Date();
                    const secs = Math.max(0, (to - from) / 1000);
                    const tag = (entry.tags && entry.tags.length > 0)
                        ? entry.tags.join(" ") : Translation.tr("Untagged");
                    byTag[tag] = (byTag[tag] ?? 0) + secs;
                    total += secs;
                    last = tag;
                }
                root.todayRows = Object.keys(byTag)
                    .map(k => ({ tag: k, seconds: byTag[k] }))
                    .sort((a, b) => b.seconds - a.seconds);
                root.todayTotal = total;
                root.lastTag = last;
            }
        }
    }
    function refresh() {
        activeProc.exec({ command: ["bash", "-c",
            // ISO 8601 → epoch via date -d. Empty if no active interval.
            "LC_TIME=C; iso=$(timew get dom.active.start 2>/dev/null); " +
            "if [ -z \"$iso\" ]; then exit 0; fi; " +
            "date -d \"$iso\" +%s; " +
            "timew get dom.active.tag.count 2>/dev/null | { read n; tags=''; for i in $(seq 1 $n); do " +
            "  tags=\"$tags $(timew get dom.active.tag.$i 2>/dev/null)\"; done; echo \"$tags\" | sed 's/^ *//'; }; " +
            "timew get dom.active.json 2>/dev/null | sed -n 's/.*\"annotation\":\"\\([^\"]*\\)\".*/\\1/p' | head -1"
        ] })
        summaryProc.exec({ command: ["bash", "-c",
            "command -v timew >/dev/null || { echo __NOTOOL__; exit 0; }; " +
            "timew export :day 2>/dev/null || echo '[]'"] })
    }
    Component.onCompleted: refresh()
    Connections {
        target: GlobalStates
        function onSidebarRightOpenChanged() { if (GlobalStates.sidebarRightOpen) root.refresh() }
    }
    Timer {
        // Background slow-poll, only while sidebar is open. Cheap.
        interval: 15000
        repeat: true
        running: GlobalStates.sidebarRightOpen
        triggeredOnStart: false
        onTriggered: root.refresh()
    }

    // ── Actions ───────────────────────────────────────────────────────────────
    Process { id: startProc; onExited: root.refresh() }
    Process { id: stopProc;  onExited: root.refresh() }

    function startTag(tag) {
        startProc.exec({ command: ["bash", "-c",
            `timew start ${StringUtils.shellSingleQuoteEscape(tag).replace(/'/g, "'\\''")} 2>&1`
        ] })
    }
    function stop() { stopProc.exec({ command: ["timew", "stop"] }) }

    // ── UI ────────────────────────────────────────────────────────────────────
    ColumnLayout {
        id: layoutCol
        anchors { left: parent.left; right: parent.right; top: parent.top; margins: 8 }
        spacing: 10

        // Active card
        Rectangle {
            Layout.fillWidth: true
            implicitHeight: activeRow.implicitHeight + 16
            radius: Appearance.rounding.normal
            color: root.running ? Appearance.colors.colPrimary : Appearance.colors.colLayer2
            Behavior on color { animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this) }

            RowLayout {
                id: activeRow
                anchors { fill: parent; margins: 8 }
                spacing: 10

                Rectangle {
                    Layout.alignment: Qt.AlignVCenter
                    Layout.preferredWidth: 38; Layout.preferredHeight: 38
                    radius: 19
                    color: root.running
                        ? ColorUtils.transparentize(Appearance.colors.colOnPrimary, 0.85)
                        : Appearance.colors.colLayer3
                    MaterialSymbol {
                        anchors.centerIn: parent
                        text: root.running ? "timer" : "schedule"
                        iconSize: 20
                        fill: 1
                        color: root.running ? Appearance.colors.colOnPrimary : Appearance.colors.colOnLayer3
                    }
                }
                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.alignment: Qt.AlignVCenter
                    spacing: -2
                    StyledText {
                        Layout.fillWidth: true
                        text: root.running
                            ? (root.activeTags !== "" ? root.activeTags : Translation.tr("Tracking…"))
                            : Translation.tr("No active tracker")
                        font.pixelSize: Appearance.font.pixelSize.smallie
                        font.weight: Font.DemiBold
                        elide: Text.ElideRight
                        color: root.running ? Appearance.colors.colOnPrimary : Appearance.colors.colOnLayer2
                    }
                    StyledText {
                        Layout.fillWidth: true
                        text: root.running
                            ? (root.activeDescription !== "" ? root.activeDescription : Translation.tr("running %1").arg(root.elapsed))
                            : Translation.tr("press a chip below to start")
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        elide: Text.ElideRight
                        color: root.running
                            ? ColorUtils.transparentize(Appearance.colors.colOnPrimary, 0.25)
                            : Appearance.colors.colSubtext
                    }
                }
                StyledText {
                    visible: root.running
                    Layout.alignment: Qt.AlignVCenter
                    text: root.elapsed
                    font.family: "monospace"
                    font.pixelSize: Appearance.font.pixelSize.normal
                    font.weight: Font.Bold
                    color: Appearance.colors.colOnPrimary
                }
                Rectangle {
                    visible: root.running
                    Layout.alignment: Qt.AlignVCenter
                    Layout.preferredWidth: 32; Layout.preferredHeight: 32
                    radius: 16
                    color: stopHov.hovered ? Appearance.m3colors.m3errorContainer : ColorUtils.transparentize(Appearance.colors.colOnPrimary, 0.85)
                    HoverHandler { id: stopHov }
                    TapHandler { onTapped: root.stop() }
                    MaterialSymbol {
                        anchors.centerIn: parent
                        text: "stop"; iconSize: 18; fill: 1
                        color: stopHov.hovered ? Appearance.m3colors.m3onErrorContainer : Appearance.colors.colOnPrimary
                    }
                }
            }
        }

        // Quick-start chips
        StyledText {
            visible: !root.running
            text: Translation.tr("Quick start")
            font.pixelSize: Appearance.font.pixelSize.smaller
            color: Appearance.colors.colSubtext
        }
        Flow {
            visible: !root.running
            Layout.fillWidth: true
            spacing: 6
            // Continuing what you were last doing is the commonest action and
            // had no button at all.
            Repeater {
                model: (root.lastTag !== "" && !root.running) ? [root.lastTag] : []
                delegate: Rectangle {
                    required property string modelData
                    implicitWidth: contTextItem.implicitWidth + 34
                    implicitHeight: 30
                    radius: Appearance.rounding.full
                    color: contHov.hovered ? Appearance.colors.colPrimary : Appearance.colors.colPrimaryContainer
                    Behavior on color { animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this) }
                    HoverHandler { id: contHov }
                    TapHandler { onTapped: root.startTag(modelData) }
                    RowLayout {
                        anchors.centerIn: parent
                        spacing: 4
                        MaterialSymbol {
                            text: "replay"
                            iconSize: Appearance.font.pixelSize.normal
                            color: contHov.hovered ? Appearance.colors.colOnPrimary : Appearance.colors.colOnPrimaryContainer
                        }
                        StyledText {
                            id: contTextItem
                            text: modelData
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            color: contHov.hovered ? Appearance.colors.colOnPrimary : Appearance.colors.colOnPrimaryContainer
                        }
                    }
                }
            }
            Repeater {
                model: ["Research", "Personal", "Reading", "Learning", "Other", "Break"]
                delegate: Rectangle {
                    required property string modelData
                    implicitWidth: chipText.implicitWidth + 22
                    implicitHeight: 30
                    radius: 15
                    color: chipHov.hovered ? Appearance.colors.colPrimary : Appearance.colors.colLayer2
                    Behavior on color { animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this) }
                    HoverHandler { id: chipHov }
                    TapHandler { onTapped: root.startTag(modelData) }
                    StyledText {
                        id: chipText
                        anchors.centerIn: parent
                        text: modelData
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        color: chipHov.hovered ? Appearance.colors.colOnPrimary : Appearance.colors.colOnLayer2
                    }
                }
            }
        }

        // Today summary (raw text from `timew summary :day`)
        Rectangle {
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.minimumHeight: 80
            radius: Appearance.rounding.normal
            color: Appearance.colors.colLayer2
            border.width: 1; border.color: Appearance.colors.colLayer0Border
            clip: true

            ColumnLayout {
                anchors { fill: parent; margins: 10 }
                spacing: 4
                RowLayout {
                    Layout.fillWidth: true
                    StyledText {
                        text: Translation.tr("Today")
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        font.weight: Font.DemiBold
                        color: Appearance.colors.colOnLayer2
                    }
                    Item { Layout.fillWidth: true }
                    StyledText {
                        visible: root.todayTotal > 0
                        text: root.fmtDuration(root.todayTotal)
                        font.pixelSize: Appearance.font.pixelSize.normal
                        font.weight: Font.Bold
                        font.family: Appearance.font.family.monospace
                        color: Appearance.colors.colPrimary
                    }
                    Rectangle {
                        Layout.preferredWidth: 22; Layout.preferredHeight: 22
                        radius: Appearance.rounding.full
                        color: refHov.hovered ? Appearance.colors.colLayer3 : "transparent"
                        HoverHandler { id: refHov }
                        TapHandler { onTapped: root.refresh() }
                        MaterialSymbol {
                            anchors.centerIn: parent
                            text: "refresh"; iconSize: 14
                            color: Appearance.colors.colOnLayer2
                        }
                    }
                }
                // Empty and missing-tool states, centred rather than a line of
                // text stranded in a large card.
                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.topMargin: 8
                    Layout.bottomMargin: 8
                    visible: root.todayRows.length === 0
                    spacing: 4
                    MaterialSymbol {
                        Layout.alignment: Qt.AlignHCenter
                        text: root.toolMissing ? "error_outline" : "hourglass_empty"
                        iconSize: Appearance.font.pixelSize.huge
                        color: Appearance.colors.colSubtext
                    }
                    StyledText {
                        Layout.alignment: Qt.AlignHCenter
                        text: root.toolMissing
                            ? Translation.tr("Timewarrior is not installed")
                            : Translation.tr("Nothing tracked today")
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        color: Appearance.colors.colSubtext
                    }
                }

                // One row per tag, longest first, with its share of the day.
                Repeater {
                    model: root.todayRows
                    delegate: ColumnLayout {
                        id: row
                        required property var modelData
                        readonly property real share: root.todayTotal > 0
                            ? modelData.seconds / root.todayTotal : 0
                        Layout.fillWidth: true
                        spacing: 1

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 6
                            StyledText {
                                Layout.fillWidth: true
                                text: row.modelData.tag
                                font.pixelSize: Appearance.font.pixelSize.smaller
                                color: Appearance.colors.colOnLayer2
                                elide: Text.ElideRight
                            }
                            StyledText {
                                text: root.fmtDuration(row.modelData.seconds)
                                font.pixelSize: Appearance.font.pixelSize.smaller
                                font.family: Appearance.font.family.monospace
                                color: Appearance.colors.colOnLayer2
                            }
                        }
                        Rectangle {
                            Layout.fillWidth: true
                            implicitHeight: 4
                            radius: Appearance.rounding.full
                            color: Qt.alpha(Appearance.colors.colOnLayer2, 0.16)
                            Rectangle {
                                anchors { left: parent.left; top: parent.top; bottom: parent.bottom }
                                width: parent.width * row.share
                                radius: parent.radius
                                color: Appearance.colors.colPrimary
                                Behavior on width {
                                    animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
