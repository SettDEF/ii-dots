import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts

/// A span on a timeline track: drag the body to move it, the edges to
/// resize it; the change is committed on release (one undo step).
Item {
    id: blk
    property real start: 0
    property real end: 1
    property real pxPerSec: 100
    property real duration: 10
    /// Neighbours on the same track: a drag stops at their edges.
    property real minStart: 0
    property real maxEnd: duration
    property string label: ""
    property string icon: ""
    property color fill: Appearance.colors.colPrimaryContainer
    property color onFill: Appearance.colors.colOnPrimaryContainer
    property bool selected: false
    property bool dim: false
    /// false: a point in time (a cut-in): the body moves it, no edges
    property bool resizable: true
    signal committed(real start, real end)
    signal picked()
    /// Right click (block-local position).
    signal menuRequested(real x, real y)

    // Live values while dragging.
    property real s: start
    property real e: end
    onStartChanged: s = start
    onEndChanged: e = end

    x: s * pxPerSec
    width: Math.max(6, (e - s) * pxPerSec)
    opacity: dim ? 0.38 : 1

    Rectangle {
        anchors.fill: parent
        radius: Appearance.rounding.verysmall
        color: blk.fill
        border.width: blk.selected ? 2 : 0
        border.color: Appearance.colors.colPrimary
        RowLayout {
            anchors { fill: parent; leftMargin: 8; rightMargin: 8 }
            spacing: 4
            clip: true
            MaterialSymbol {
                visible: blk.icon.length > 0 && blk.width > 34
                text: blk.icon
                iconSize: Appearance.font.pixelSize.small
                color: blk.onFill
            }
            StyledText {
                Layout.fillWidth: true
                visible: blk.width > 56
                text: blk.label
                elide: Text.ElideRight
                font.pixelSize: Appearance.font.pixelSize.smallest
                font.family: Appearance.font.family.monospace
                color: blk.onFill
            }
        }
    }

    component Grip: MouseArea {
        property int mode: 0 // 0 move, 1 left edge, 2 right edge
        property real px0: 0
        property real s0: 0
        property real e0: 0
        hoverEnabled: true
        cursorShape: mode === 0 ? Qt.OpenHandCursor : Qt.SizeHorCursor
        preventStealing: true
        onPressed: (m) => { px0 = mapToItem(blk.parent, m.x, 0).x; s0 = blk.s; e0 = blk.e; blk.picked(); }
        onPositionChanged: (m) => {
            if (!pressed) return;
            const d = (mapToItem(blk.parent, m.x, 0).x - px0) / blk.pxPerSec;
            const minLen = 0.2;
            if (mode === 0) {
                const len = e0 - s0;
                const ns = Math.max(blk.minStart, Math.min(blk.maxEnd - len, s0 + d));
                blk.s = ns; blk.e = ns + len;
            } else if (mode === 1) {
                blk.s = Math.max(blk.minStart, Math.min(e0 - minLen, s0 + d));
            } else {
                blk.e = Math.min(blk.maxEnd, Math.max(s0 + minLen, e0 + d));
            }
        }
        onReleased: if (blk.s !== blk.start || blk.e !== blk.end) blk.committed(blk.s, blk.e)
    }
    // Under the grips: they take the left button, this takes the right.
    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.RightButton
        onClicked: (m) => { blk.picked(); blk.menuRequested(m.x, m.y); }
    }
    Grip { anchors.fill: parent; anchors.leftMargin: blk.resizable ? 7 : 0; anchors.rightMargin: blk.resizable ? 7 : 0; mode: 0 }
    Grip { visible: blk.resizable; anchors { left: parent.left; top: parent.top; bottom: parent.bottom } width: 8; mode: 1 }
    Grip { visible: blk.resizable; anchors { right: parent.right; top: parent.top; bottom: parent.bottom } width: 8; mode: 2 }
}
