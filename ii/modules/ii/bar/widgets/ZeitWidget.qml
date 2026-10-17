// zeit in the bar: running jobs with their time, or the last one's result.
// Click: show its pane in zeit. Hover: the recent jobs.
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.bar
import QtQuick
import QtQuick.Layouts

MouseArea {
    id: root
    required property string widgetId

    readonly property bool showResult: BarWidgets.get(root.widgetId, "showResult") !== false
    readonly property var job: Zeit.running.length > 0 ? Zeit.running[0] : (root.showResult && Zeit.fresh ? Zeit.latest : null)
    property int tick: 0
    Timer { interval: 1000; running: Zeit.running.length > 0; repeat: true; onTriggered: root.tick++ }
    function dur(s) {
        s = Math.max(0, Math.floor(s))
        return s < 60 ? `${s}s` : `${Math.floor(s / 60)}m ${String(s % 60).padStart(2, "0")}s`
    }
    function short(cmd) { return cmd.split(/\s+/).slice(0, 3).join(" ") }

    visible: !!root.job
    hoverEnabled: true
    acceptedButtons: Qt.LeftButton | Qt.RightButton
    implicitWidth: row.implicitWidth + 4
    implicitHeight: row.implicitHeight + 8
    onClicked: mouse => {
        if (!root.job) return
        if (mouse.button === Qt.RightButton) Zeit.markSeen()
        else Zeit.jump(root.job)
    }

    RowLayout {
        id: row
        anchors { left: parent.left; right: parent.right; leftMargin: 2; rightMargin: 2; verticalCenter: parent.verticalCenter }
        spacing: 6

        MaterialSymbol {
            text: !root.job ? "terminal" : root.job.state === "running" ? "progress_activity" : root.job.state === "ok" ? "check_circle" : "error"
            iconSize: Appearance.font.pixelSize.normal
            fill: 1
            color: !root.job ? Appearance.colors.colOnLayer1
                : root.job.state === "failed" ? Appearance.m3colors.m3error
                : root.job.state === "running" ? Appearance.colors.colPrimary : Appearance.colors.colOnLayer1
            RotationAnimation on rotation {
                running: root.job?.state === "running" && root.visible
                from: 0; to: 360; duration: 1200; loops: Animation.Infinite
            }
        }
        StyledText {
            text: root.job ? root.short(root.job.cmd) : ""
            Layout.maximumWidth: 160
            elide: Text.ElideRight
            font.pixelSize: Appearance.font.pixelSize.smaller
            color: Appearance.colors.colOnLayer1
        }
        StyledText {
            text: !root.job ? "" : root.job.state === "running"
                ? (root.tick, root.dur(root.job.seconds + root.tick)) + (root.job.progress !== null ? `  ${Math.round(root.job.progress * 100)}%` : "")
                : root.dur(root.job.seconds)
            font.family: Appearance.font.family.monospace
            font.pixelSize: Appearance.font.pixelSize.smaller
            color: root.job?.state === "failed" ? Appearance.m3colors.m3error : Appearance.colors.colSubtext
        }
        StyledText {
            visible: Zeit.running.length > 1
            text: `+${Zeit.running.length - 1}`
            font.family: Appearance.font.family.monospace
            font.pixelSize: Appearance.font.pixelSize.smaller
            color: Appearance.colors.colSubtext
        }
    }

    StyledPopup {
        hoverTarget: root

        ColumnLayout {
            anchors.centerIn: parent
            spacing: 4

            StyledPopupHeaderRow { icon: "terminal"; label: "zeit" }
            Repeater {
                model: Zeit.jobs.slice(0, 8)
                delegate: RowLayout {
                    required property var modelData
                    Layout.preferredWidth: 380
                    spacing: 8
                    MaterialSymbol {
                        text: modelData.state === "running" ? "progress_activity" : modelData.state === "ok" ? "check_circle" : "error"
                        iconSize: Appearance.font.pixelSize.normal
                        color: modelData.state === "failed" ? Appearance.m3colors.m3error : modelData.state === "running" ? Appearance.colors.colPrimary : Appearance.colors.colSubtext
                    }
                    StyledText {
                        Layout.fillWidth: true
                        elide: Text.ElideRight
                        text: modelData.cmd
                        font.family: Appearance.font.family.monospace
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        color: Appearance.colors.colOnLayer1
                    }
                    StyledText {
                        text: [...modelData.counts, modelData.state === "failed" ? `exit ${modelData.exit}` : "", root.dur(modelData.seconds)].filter(s => s).join(" · ")
                        font.family: Appearance.font.family.monospace
                        font.pixelSize: Appearance.font.pixelSize.smallest
                        color: modelData.state === "failed" ? Appearance.m3colors.m3error : Appearance.colors.colSubtext
                    }
                }
            }
            StyledText {
                text: Translation.tr("Click: show it in zeit · right click: dismiss the result")
                font.pixelSize: Appearance.font.pixelSize.smallest
                color: Appearance.colors.colSubtext
            }
        }
    }
}
