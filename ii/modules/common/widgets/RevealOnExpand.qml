import QtQuick

// Scrolls `target` into view in the list or panel it sits in once it opens (`when` turns true): just
// enough to show all of it, its top kept in sight. It waits until the opening has settled (the
// height stops changing), so a part that grows in steps (a Loader, a list filling) is shown whole.
// Works in any Flickable or ListView (originY), StyledFlickable's own scroll animation included.
Item {
    id: root
    required property Item target
    property bool when: false
    /// room left above and below the part
    property real margin: 12

    visible: false
    width: 0
    height: 0

    // the opening is watched for this long at most (a part that never settles)
    property bool watching: false
    onWhenChanged: {
        if (when) {
            root.watching = true;
            settle.restart();
            giveUp.restart();
        } else {
            root.watching = false;
        }
    }

    Connections {
        target: root.watching ? root.target : null
        function onHeightChanged() { settle.restart(); }
        function onImplicitHeightChanged() { settle.restart(); }
    }
    // the height has stayed put this long: it has opened
    Timer {
        id: settle
        interval: 90
        onTriggered: {
            root.watching = false;
            giveUp.stop();
            root.reveal();
        }
    }
    Timer {
        id: giveUp
        interval: 1500
        onTriggered: {
            root.watching = false;
            root.reveal();
        }
    }

    /// The nearest Flickable above `item` that can scroll.
    function scroller(item) {
        let f = item ? item.parent : null;
        while (f) {
            if (f.contentY !== undefined && f.contentItem !== undefined && f.contentHeight > f.height + 0.5)
                return f;
            f = f.parent;
        }
        return null;
    }

    function reveal() {
        const t = root.target;
        const f = root.scroller(t);
        if (!t || !f || !t.visible || f.height <= 0 || f.moving)
            return;
        const origin = f.originY ?? 0;
        const top = t.mapToItem(f.contentItem, 0, 0).y;
        const bottom = top + t.height;
        const minY = origin;
        const maxY = origin + Math.max(0, f.contentHeight - f.height);
        let to = f.contentY;
        if (bottom + root.margin > f.contentY + f.height)
            to = bottom + root.margin - f.height;
        if (top - root.margin < to)
            to = top - root.margin;
        to = Math.max(minY, Math.min(to, maxY));
        if (Math.abs(to - f.contentY) < 1)
            return;
        if (f.scrollTargetY !== undefined) {
            // StyledFlickable / StyledListView glide contentY themselves; their wheel target follows
            f.scrollTargetY = to;
            f.contentY = to;
        } else {
            glide.target = f;
            glide.to = to;
            glide.restart();
        }
    }

    NumberAnimation {
        id: glide
        property: "contentY"
        duration: 260
        easing.type: Easing.OutCubic
    }
}
