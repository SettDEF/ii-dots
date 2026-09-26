// Renders DockTooltip above the dock, centred on whichever tile published it.
pragma ComponentBehavior: Bound
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import Quickshell

PopupWindow {
    id: root
    required property Item anchorItem

    readonly property Item target: DockTooltip.target
    readonly property var hostWin: root.anchorItem?.QsWindow?.window ?? null
    readonly property real hostWidth: root.hostWin?.width ?? 0
    // Only the dock on the target's own screen draws it.
    readonly property bool mine: root.target !== null
        && root.target.QsWindow?.window === root.hostWin

    color: "transparent"
    /// Read from the target every frame, not copied on enter — a snapshot
    /// froze CPU/RAM at whatever they were when the pointer arrived.
    readonly property string liveText: (root.target && root.target.tooltip !== undefined)
        ? root.target.tooltip : DockTooltip.text
    readonly property bool want: root.mine && root.liveText.length > 0 && root.hostWidth > 0
    // Stays mapped through the fade-out, or the bubble vanishes mid-animation.
    visible: bubble.opacity > 0 || root.want

    // mapFromItem() is a call, not a dependency, so re-sync while the dock moves.
    property int _tick: 0
    Timer { running: root.visible; interval: 120; repeat: true; onTriggered: root._tick++ }
    readonly property point origin: {
        root._tick;
        root.hostWidth;
        if (!root.mine || !root.hostWin) return Qt.point(0, 0);
        return root.hostWin.contentItem.mapFromItem(root.target, 0, 0);
    }

    anchor {
        window: root.hostWin
        gravity: Edges.Top | Edges.Right
        edges: Edges.Top | Edges.Left
        adjustment: PopupAdjustment.None
        // rect.y places the popup's BOTTOM, so the tile's top edge sits it
        // just above the tile; the gap is the margin below.
        rect: Qt.rect(0, root.heldY - 6, 1, 1)
    }

    // Latched: on leave the target goes null and origin collapses to 0, which
    // would yank the bubble to the screen edge while it is still fading.
    property string heldText: ""
    property real heldCentre: 0
    property real heldY: 0
    function _latch() {
        if (!root.want) return;
        root.heldText = root.liveText;
        root.heldCentre = root.origin.x + (root.target?.width ?? 0) / 2;
        // y as well as x: on leave the target goes null, origin collapses to
        // (0,0), and an anchor reading origin.y directly snapped the bubble
        // to the top of the dock window — it jumped up as it faded.
        root.heldY = root.origin.y;
    }
    onOriginChanged: root._latch()
    onWantChanged: root._latch()
    onLiveTextChanged: root._latch()
    Connections {
        target: DockTooltip
        function onTextChanged() { root._latch(); }
    }

    implicitWidth: Math.max(1, root.hostWidth)
    implicitHeight: Math.max(1, bubble.implicitHeight)
    mask: Region { item: bubble }

    Rectangle {
        id: bubble
        anchors.bottom: parent.bottom
        // Centred on the tile, clamped inside the screen.
        x: Math.max(6, Math.min(root.heldCentre - width / 2, root.hostWidth - width - 6))
        // Slides between tiles instead of teleporting.
        Behavior on x {
            animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
        }

        opacity: root.want ? 1 : 0
        Behavior on opacity {
            animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
        }
        implicitWidth: label.implicitWidth + 18
        implicitHeight: label.implicitHeight + 10
        radius: Appearance.rounding.small
        color: Appearance.colors.colTooltip
        border.width: 1
        border.color: Appearance.colors.colLayer0Border
        StyledText {
            id: label
            anchors.centerIn: parent
            text: root.heldText
            font.pixelSize: Appearance.font.pixelSize.smaller
            color: Appearance.colors.colOnTooltip
        }
    }
}
