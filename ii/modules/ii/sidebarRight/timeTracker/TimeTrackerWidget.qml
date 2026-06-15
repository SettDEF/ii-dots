import qs
import qs.services
import qs.modules.common
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
    Process {
        id: summaryProc
        stdout: StdioCollector { onStreamFinished: root.todaySummary = (this.text || "").trim() }
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
        summaryProc.exec({ command: ["bash", "-c", "LC_TIME=C timew summary :day 2>/dev/null || true"] })
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
                        Layout.fillWidth: true
                        text: Translation.tr("Today")
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        font.weight: Font.DemiBold
                        color: Appearance.colors.colOnLayer2
                    }
                    Rectangle {
                        Layout.preferredWidth: 22; Layout.preferredHeight: 22
                        radius: 11
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
                Flickable {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    contentWidth: width
                    contentHeight: summaryText.implicitHeight
                    clip: true
                    StyledText {
                        id: summaryText
                        width: parent.width
                        text: root.todaySummary !== ""
                            ? root.todaySummary
                            : Translation.tr("No tracked time today.")
                        font.family: "monospace"
                        font.pixelSize: Appearance.font.pixelSize.smaller - 1
                        color: Appearance.colors.colOnLayer2
                        wrapMode: Text.NoWrap
                    }
                }
            }
        }
    }
}
