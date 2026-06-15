import qs.modules.common
import qs.modules.common.widgets
import QtQuick

/**
 * HUD sub-tab tray — a container that flares out of the bar with
 * concave shoulders (the Caelestia side-panel silhouette). Drawn with
 * a Canvas: it rasterises the path directly so it ALWAYS renders (no
 * Shape triangulation, no plugin). Host places y=0 at the bar's edge.
 *
 * Driven by: tabsModel / currentIndex. Emits: selected(index).
 */
Item {
    id: root

    property var tabsModel: []
    property int currentIndex: 0
    signal selected(int index)

    // Open animation — the tray slides DOWN out of the bar: starts
    // translated up (hidden behind the bar) and eases into place.
    transform: Translate {
        id: slideIn
        y: -root.bodyH
    }
    NumberAnimation {
        target: slideIn
        property: "y"
        from: -root.bodyH
        to: 0
        duration: 260
        easing.type: Easing.OutCubic
        running: true
    }

    // Width follows the sub-tab count — animated so switching tabs
    // grows/shrinks the container smoothly.
    property real bodyW: subPills.implicitWidth + 34
    Behavior on bodyW {
        NumberAnimation { duration: 220; easing.type: Easing.OutCubic }
    }
    readonly property real bodyH: 44
    readonly property real fil: 15      // concave shoulder fillet radius
    readonly property real br: 18       // bottom corner radius

    onBodyWChanged: shapeCanvas.requestPaint()
    onWidthChanged: shapeCanvas.requestPaint()

    Canvas {
        id: shapeCanvas
        anchors.fill: parent
        onPaint: {
            const ctx = getContext("2d")
            ctx.reset()
            const cx = width / 2
            const bw = root.bodyW, bh = root.bodyH, f = root.fil, b = root.br
            ctx.fillStyle = Appearance.colors.colLayer0
            ctx.strokeStyle = Appearance.colors.colLayer0Border
            ctx.lineWidth = 1
            ctx.beginPath()
            // Top-left — widest point, flush with the bar.
            ctx.moveTo(cx - bw / 2 - f, 0)
            // Concave left shoulder — curves INWARD from the bar-flush
            // top down to the (narrower) body. Centre sits up-left so
            // the arc bows into the corner instead of bulging out.
            ctx.arc(cx - bw / 2 - f, f, f, -Math.PI / 2, 0, false)
            // Left side down.
            ctx.lineTo(cx - bw / 2, bh - b)
            // Bottom-left corner.
            ctx.arc(cx - bw / 2 + b, bh - b, b, Math.PI, Math.PI / 2, true)
            // Bottom edge.
            ctx.lineTo(cx + bw / 2 - b, bh)
            // Bottom-right corner.
            ctx.arc(cx + bw / 2 - b, bh - b, b, Math.PI / 2, 0, true)
            // Right side up.
            ctx.lineTo(cx + bw / 2, f)
            // Concave right shoulder — mirror of the left.
            ctx.arc(cx + bw / 2 + f, f, f, Math.PI, 3 * Math.PI / 2, false)
            // Top edge back to start.
            ctx.closePath()
            ctx.fill()
            ctx.stroke()
        }
        Component.onCompleted: requestPaint()
    }

    PillTabBar {
        id: subPills
        anchors.horizontalCenter: parent.horizontalCenter
        y: (root.bodyH - height) / 2
        iconOnly: true
        tabs: root.tabsModel
        current: String(root.currentIndex)
        onTabSelected: id => root.selected(parseInt(id))
    }
}
