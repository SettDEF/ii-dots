import QtQuick

MouseArea { // Right side | scroll to change volume
    id: root

    signal scrollUp(delta: int)
    signal scrollDown(delta: int)
    signal movedAway()

    property bool hovered: false
    property real lastScrollX: 0
    property real lastScrollY: 0
    property bool trackingScroll: false
    property real moveThreshold: 20
    /// one scrollUp/scrollDown per gesture (a page at a time), not one per wheel event: a touchpad
    /// swipe sends dozens of events, and each moved a page (one swipe skipped pages)
    property bool stepped: false
    property real _acc: 0
    property bool _stepped: false
    // the gesture is over when the events stop (a mouse has no end phase)
    Timer { id: gestureEnd; interval: 220; onTriggered: { root._acc = 0; root._stepped = false; } }

    acceptedButtons: Qt.LeftButton
    hoverEnabled: true

    onEntered: {
        root.hovered = true;
    }

    onExited: {
        root.hovered = false;
        root.trackingScroll = false;
    }

    onWheel: event => {
        if (root.stepped) {
            gestureEnd.restart();
            if (event.phase === Qt.ScrollBegin) { root._acc = 0; root._stepped = false; }
            // a wheel notch is 120; a touchpad's pixels add up to the same before it counts
            root._acc += event.angleDelta.y !== 0 ? event.angleDelta.y : event.pixelDelta.y;
            if (!root._stepped && Math.abs(root._acc) >= 120) {
                root._stepped = true;
                if (root._acc < 0) root.scrollDown(root._acc);
                else root.scrollUp(root._acc);
            }
            if (event.phase === Qt.ScrollEnd) { root._acc = 0; root._stepped = false; }
        } else if (event.angleDelta.y < 0)
            root.scrollDown(event.angleDelta.y);
        else if (event.angleDelta.y > 0)
            root.scrollUp(event.angleDelta.y);
        // Store the mouse position and start tracking
        root.lastScrollX = event.x;
        root.lastScrollY = event.y;
        root.trackingScroll = true;
    }

    onPositionChanged: mouse => {
        if (root.trackingScroll) {
            const dx = mouse.x - root.lastScrollX;
            const dy = mouse.y - root.lastScrollY;
            if (Math.sqrt(dx * dx + dy * dy) > root.moveThreshold) {
                root.movedAway();
                root.trackingScroll = false;
            }
        }
    }

    onContainsMouseChanged: {
        if (!root.containsMouse && root.trackingScroll) {
            root.movedAway();
            root.trackingScroll = false;
        }
    }
}
