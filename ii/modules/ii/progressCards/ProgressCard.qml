pragma ComponentBehavior: Bound
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts

/**
 * One job as a card, on one grid: the state icon left; title and step beside it; the bar under both
 * with "n of m" at its left end and the percent at its right end. Close/stop floats at the top right on hover.
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
    readonly property int pad: 14
    // the step without trailing dots and spaces (pacman pads its lines)
    readonly property string step: (job.step || "").replace(/[\s.…]+$/, "")

    implicitWidth: 340
    implicitHeight: col.implicitHeight + pad * 2
    radius: Appearance.rounding.large
    color: Qt.alpha(Appearance.m3colors.m3surfaceContainerHigh, 0.92)
    border.width: 1
    border.color: Appearance.colors.colLayer0Border

    ColumnLayout {
        id: col
        anchors { left: parent.left; right: parent.right; top: parent.top; margins: root.pad }
        spacing: 10
        RowLayout {
            Layout.fillWidth: true
            spacing: 12
            Rectangle {
                Layout.alignment: Qt.AlignVCenter
                implicitWidth: 36; implicitHeight: 36; radius: Appearance.rounding.full
                color: Qt.alpha(root.tint, 0.16)
                Behavior on color { ColorAnimation { duration: 200 } }
                MaterialSymbol {
                    anchors.centerIn: parent
                    text: root.running ? "progress_activity" : root.failed ? "error" : "check"
                    iconSize: 20
                    color: root.tint
                    RotationAnimation on rotation { running: root.running; from: 0; to: 360; duration: 1100; loops: Animation.Infinite }
                    onTextChanged: if (!root.running) rotation = 0
                }
            }
            ColumnLayout {
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignVCenter
                // room for the hover button at the top right
                Layout.rightMargin: 24
                spacing: 1
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
                    text: root.failed ? `Failed${root.job.code != null ? " (exit " + root.job.code + ")" : ""}` : !root.running ? "Done" : (root.step || "Working")
                    elide: Text.ElideRight
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: Appearance.colors.colSubtext
                }
            }
        }
        // the bar, full width
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
        // under the bar's two ends: the count and the percent
        RowLayout {
            Layout.fillWidth: true
            visible: countText.text.length > 0 || pctText.text.length > 0
            StyledText {
                id: countText
                text: root.job.count && root.running ? `${root.job.count[0]} of ${root.job.count[1]}` : ""
                font.family: Appearance.font.family.monospace
                font.pixelSize: Appearance.font.pixelSize.smallest
                color: Appearance.colors.colSubtext
            }
            Item { Layout.fillWidth: true }
            StyledText {
                id: pctText
                text: root.pct >= 0 ? Math.round(root.running ? root.pct : 100) + "%" : ""
                font.family: Appearance.font.family.monospace
                font.pixelSize: Appearance.font.pixelSize.smallest
                color: root.tint
            }
        }
    }
    // close: a finished card goes, a running job is stopped (Ctrl+C to it)
    Rectangle {
        anchors { top: parent.top; right: parent.right; margins: root.pad - 4 }
        implicitWidth: 26; implicitHeight: 26; radius: Appearance.rounding.full
        color: xh.hovered ? Appearance.colors.colLayer2Hover : "transparent"
        opacity: hov.hovered ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: 140 } }
        MaterialSymbol { anchors.centerIn: parent; text: root.running ? "stop" : "close"; iconSize: 16; color: Appearance.colors.colOnLayer1 }
        HoverHandler { id: xh; cursorShape: Qt.PointingHandCursor }
        TapHandler { onTapped: root.closeRequested() }
    }
    HoverHandler { id: hov }
    TapHandler { onTapped: root.openRequested() }
}
