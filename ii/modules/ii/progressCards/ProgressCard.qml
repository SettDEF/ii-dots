pragma ComponentBehavior: Bound
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts

/**
 * One job as a card: its state icon, title, step, percent and a bar (a sliding segment when the
 * percent is unknown). Pure UI: the job comes in as `job`, clicks go out as signals.
 */
Rectangle {
    id: root
    property var job: ({})
    signal openRequested()
    signal closeRequested()

    readonly property bool running: job.state === "running"
    readonly property bool failed: job.state === "failed"
    readonly property real pct: job.percent ?? -1
    readonly property color tint: failed ? Appearance.m3colors.m3error : Appearance.colors.colPrimary

    implicitWidth: 340
    implicitHeight: col.implicitHeight + 24
    radius: Appearance.rounding.large
    color: Qt.alpha(Appearance.m3colors.m3surfaceContainerHigh, 0.9)
    border.width: 1
    border.color: Appearance.colors.colLayer0Border

    ColumnLayout {
        id: col
        anchors { left: parent.left; right: parent.right; top: parent.top; margins: 12; leftMargin: 14 }
        spacing: 8
        RowLayout {
            spacing: 10
            // the state: a turning ring while it works, a check or an error after
            Rectangle {
                implicitWidth: 34; implicitHeight: 34; radius: Appearance.rounding.full
                color: Qt.alpha(root.tint, 0.16)
                Behavior on color { ColorAnimation { duration: 200 } }
                MaterialSymbol {
                    anchors.centerIn: parent
                    text: root.running ? "progress_activity" : root.failed ? "error" : "check"
                    iconSize: 20
                    color: root.tint
                    RotationAnimation on rotation { running: root.running; from: 0; to: 360; duration: 1100; loops: Animation.Infinite }
                    rotation: 0
                    onTextChanged: if (!root.running) rotation = 0
                }
            }
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 0
                StyledText {
                    Layout.fillWidth: true
                    text: root.job.title || "Working"
                    elide: Text.ElideRight
                    font.pixelSize: Appearance.font.pixelSize.small
                    font.weight: Font.DemiBold
                    color: Appearance.colors.colOnLayer1
                }
                StyledText {
                    Layout.fillWidth: true
                    text: root.failed ? `Failed${root.job.code != null ? " (exit " + root.job.code + ")" : ""}` : !root.running ? "Done" : (root.job.step || "…")
                    elide: Text.ElideRight
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: Appearance.colors.colSubtext
                }
            }
            StyledText {
                visible: root.pct >= 0
                text: Math.round(root.pct) + "%"
                font.family: Appearance.font.family.monospace
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: root.tint
            }
            // close: a finished card goes, a running job is stopped (Ctrl+C to it)
            Rectangle {
                implicitWidth: 26; implicitHeight: 26; radius: Appearance.rounding.full
                color: xh.hovered ? Appearance.colors.colLayer2Hover : "transparent"
                opacity: hov.hovered ? 1 : 0
                Behavior on opacity { NumberAnimation { duration: 140 } }
                MaterialSymbol { anchors.centerIn: parent; text: root.running ? "stop" : "close"; iconSize: 16; color: Appearance.colors.colOnLayer1 }
                HoverHandler { id: xh; cursorShape: Qt.PointingHandCursor }
                TapHandler { onTapped: root.closeRequested() }
            }
        }
        // the bar
        Rectangle {
            id: track
            Layout.fillWidth: true
            implicitHeight: 6
            radius: 3
            color: Appearance.colors.colLayer2
            clip: true
            Rectangle {
                visible: root.pct >= 0 || !root.running
                height: parent.height; radius: 3
                color: root.tint
                width: parent.width * (root.running ? Math.max(0, root.pct) : 100) / 100
                Behavior on width { NumberAnimation { duration: 280; easing.type: Easing.OutCubic } }
                Behavior on color { ColorAnimation { duration: 200 } }
            }
            // unknown percent: a segment sliding through
            Rectangle {
                id: seg
                visible: root.pct < 0 && root.running
                height: parent.height; radius: 3
                width: parent.width * 0.3
                color: root.tint
                NumberAnimation on x {
                    running: seg.visible; loops: Animation.Infinite
                    from: -seg.width; to: track.width; duration: 1300; easing.type: Easing.InOutQuad
                }
            }
        }
        StyledText {
            visible: (root.job.count ?? null) !== null && root.running
            text: root.job.count ? `${root.job.count[0]} of ${root.job.count[1]}` : ""
            font.family: Appearance.font.family.monospace
            font.pixelSize: Appearance.font.pixelSize.smallest
            color: Appearance.colors.colSubtext
        }
    }
    HoverHandler { id: hov }
    TapHandler { onTapped: root.openRequested() }
}
