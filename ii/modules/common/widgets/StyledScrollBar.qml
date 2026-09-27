import QtQuick
import QtQuick.Controls
import qs.modules.common
import qs.modules.common.functions

/// The shell's scroll bar. Optionally a map of its content — see `markers`.
///
/// Works in either orientation: every position below is computed along the
/// bar's own long axis and assigned to x or y at the end, rather than being
/// written twice.
ScrollBar {
    id: root

    /// "minimal" | "rail" | "stripes"
    property string style: Config.options?.appearance?.scrollbar?.style ?? "minimal"

    /// Drawn thickness at rest, and engaged.
    property real barWidth: Config.options?.appearance?.scrollbar?.width ?? 4
    property real barWidthActive: Config.options?.appearance?.scrollbar?.activeWidth ?? 9
    /// Visible whenever content overflows, not only when engaged.
    property bool alwaysVisible: Config.options?.appearance?.scrollbar?.alwaysVisible ?? false
    /// Pointer target, wider than the drawn bar. Also a dead strip down every
    /// list's edge, since an attached ScrollBar overlays rather than reserves.
    property real hitWidth: 18
    /// Gap between the outer edge of the container and the drawn bar.
    ///
    /// The drawn bar sits at the outer edge rather than centred, so the extra
    /// container width all falls on the content side — which is where the
    /// pointer arrives from. Grabbing gets easier without the bar moving.
    property real barInset: 3
    /// Shortest the thumb may become, in pixels.
    property real minimumThumbLength: 40

    readonly property bool isVertical: root.orientation === Qt.Vertical
    /// Padding at each end of the track, whichever end that is.
    readonly property real padLead:  root.isVertical ? root.topPadding : root.leftPadding
    readonly property real padTrail: root.isVertical ? root.bottomPadding : root.rightPadding
    /// Length of the track, and the bar's thickness across it.
    readonly property real trackLength: Math.max(0,
        (root.isVertical ? root.height : root.width) - root.padLead - root.padTrail)
    readonly property real thickness:
        (root.pressed || root.hovered) ? root.barWidthActive : root.barWidth

    /// Cross-axis position for something `w` thick, hugging the outer edge.
    function laneOffset(containerThickness, w) {
        return root.mirrored ? root.barInset
                             : Math.max(0, containerThickness - root.barInset - w);
    }

    /// Landmarks: [{ at, label, major }]. `at` is a fraction of the scrollable
    /// range; `major` draws the bigger dot. Empty = a plain scroll bar.
    property var markers: []
    /// Pull radius, as a fraction of the range.
    property real snapRadius: 0.035
    readonly property bool hasMap: (root.markers?.length ?? 0) > 0
        && (Config.options?.appearance?.scrollbar?.showMap ?? true)

    /// Build `markers` from items: a container, or an array of them.
    ///
    /// Every caller was hand-rolling this — measure, guard the range, convert
    /// to fractions. `label(item)` returns a landmark's name, or "" to skip it;
    /// `major(item)` marks a section start.
    function markersFromItems(items, flick, label, major) {
        if (!items || !flick) return [];
        const list = Array.isArray(items) ? items : items.children;
        if (!list) return [];
        const range = (root.isVertical ? flick.contentHeight - flick.height
                                       : flick.contentWidth - flick.width);
        if (range <= 0) return [];
        const out = [];
        for (let i = 0; i < list.length; ++i) {
            const c = list[i];
            if (!c) continue;
            const name = label ? label(c) : "";
            if (!name) continue;
            out.push({
                at: Math.max(0, Math.min(1, (root.isVertical ? c.y : c.x) / range)),
                label: name,
                major: major ? major(c) === true : true
            });
        }
        return out;
    }

    /// A dot was clicked. The bar scrolls there itself; this is for hosts that
    /// want to do more (the settings rail switches page).
    signal markerActivated(int index)

    /// Index of the dot under the pointer, or -1.
    property int hoveredMarker: -1

    /// Which landmark you are "at", or -1. Its own property, not a field in
    /// `markers` — a new array rebuilds every dot.
    property int currentMarker: -1

    /// Index of the marker currently pulling, or -1.
    readonly property int nearestMarker: {
        if (!root.hasMap) return -1;
        let best = -1;
        let bestDist = root.snapRadius;
        for (let i = 0; i < root.markers.length; ++i) {
            const d = Math.abs((root.markers[i].at ?? 0) - root.position);
            if (d < bestDist) { bestDist = d; best = i; }
        }
        return best;
    }

    signal snapCaught(int index)

    function snapAnimTo(target) {
        // Duration follows the distance, or a one-dot hop takes as long as a
        // jump down the whole track.
        const dist = Math.abs(target - root.position);
        snapAnim.duration = Math.round(120 + dist * 320);
        snapAnim.to = target;
        snapAnim.restart();
    }

    /// Centre the thumb on a point along the track, as a fraction of it.
    function scrollToFraction(frac) {
        root.snapAnimTo(Math.max(0, Math.min(1 - root.size, frac - root.size / 2)));
    }

    /// Where the thumb sat when the press began, to tell a drag from a tap.
    property real _pressAnchor: 0

    onPressedChanged: {
        if (root.pressed) { root._pressAnchor = root.position; return; }
        // Only after a real drag: a plain click is handled by the press below,
        // and snapping it here would fight that animation.
        if (Math.abs(root.position - root._pressAnchor) < 0.001) return;
        if (root.hasMap && root.nearestMarker >= 0
                && (Config.options?.appearance?.scrollbar?.magnets ?? true)) {
            const i = root.nearestMarker;
            root.snapAnimTo(root.markers[i].at ?? 0);
            root.snapCaught(i);
        }
    }

    NumberAnimation {
        id: snapAnim
        target: root
        property: "position"
        duration: Appearance.animationCurves.expressiveFastSpatialDuration
        easing.type: Easing.BezierSpline
        easing.bezierCurve: Appearance.animationCurves.emphasizedDecel
    }

    policy: (root.alwaysVisible && root.size < 1.0) ? ScrollBar.AlwaysOn : ScrollBar.AsNeeded
    topPadding: Appearance.rounding.normal
    bottomPadding: Appearance.rounding.normal
    leftPadding: Appearance.rounding.normal
    rightPadding: Appearance.rounding.normal

    // `active` is left to Qt: it sets it while the flickable moves, not only on hover.
    implicitWidth:  root.isVertical ? root.hitWidth : 0
    implicitHeight: root.isVertical ? 0 : root.hitWidth
    // minimumSize is a fraction of the track; it is 0 before the first layout.
    minimumSize: root.trackLength > 0
        ? Math.min(1, root.minimumThumbLength / root.trackLength) : 0

    background: Item {
        implicitWidth:  root.isVertical ? root.hitWidth : 0
        implicitHeight: root.isVertical ? 0 : root.hitWidth

        // Click the groove to glide there instead of stepping a page.
        //
        // The press is INTERCEPTED, not undone: Qt steps on press, and putting
        // the position back afterwards shows as a flick. A press on the thumb
        // is declined so it falls through to Qt, which owns dragging.
        MouseArea {
            anchors.fill: parent
            preventStealing: false
            // opacity 0 does not stop a MouseArea, and this is attached to
            // every list — including the ones whose content fits.
            enabled: root.size < 1.0
            onPressed: mouse => {
                const track = root.trackLength;
                if (track <= 0) { mouse.accepted = false; return; }
                const along = (root.isVertical ? mouse.y : mouse.x) - root.padLead;
                const thumbStart = track * root.position;
                if (along >= thumbStart && along <= thumbStart + track * root.size) {
                    mouse.accepted = false;   // the thumb: Qt drags it
                    return;
                }
                const frac = along / track;

                // A click within reach of a landmark is a click ON it, so the
                // dots need no handler of their own racing this one.
                if (root.hasMap) {
                    let best = -1, bestPx = 11;
                    for (let i = 0; i < root.markers.length; ++i) {
                        const px = Math.abs(((root.markers[i].at ?? 0) - frac) * track);
                        if (px < bestPx) { bestPx = px; best = i; }
                    }
                    if (best >= 0) {
                        root.snapAnimTo(root.markers[best].at ?? 0);
                        root.markerActivated(best);
                        return;
                    }
                }
                root.scrollToFraction(frac);
            }
        }

        Rectangle {
            // Bound, not anchored: a centring anchor resolves a pass later than
            // the thickness feeding it, so an animated thickness trails a frame.
            x: root.isVertical ? root.laneOffset(parent.width, width) : root.padLead
            y: root.isVertical ? root.padLead : root.laneOffset(parent.height, height)
            width:  root.isVertical ? root.thickness : root.trackLength
            height: root.isVertical ? root.trackLength : root.thickness
            radius: Math.min(width, height) / 2
            visible: root.style !== "stripes"
            color: Appearance.colors.colOnSurfaceVariant
            // rail keeps the track drawn; minimal shows it only when engaged.
            opacity: root.size >= 1.0 ? 0
                : (root.hovered || root.pressed) ? 0.16
                : (root.style === "rail" ? 0.10 : 0)

            Behavior on opacity {
                NumberAnimation {
                    duration: Appearance.animation.elementMoveFast.duration
                    easing.type: Appearance.animation.elementMoveFast.type
                    easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve
                }
            }
            Behavior on width  { NumberAnimation { duration: Appearance.animation.elementMoveFast.duration } }
            Behavior on height { NumberAnimation { duration: Appearance.animation.elementMoveFast.duration } }
        }

        // stripes: the track as countable rungs, with the thumb riding over.
        Repeater {
            model: root.style === "stripes" && root.size < 1.0 ? stripeCount : 0

            // From the track length, so rungs stay evenly spaced on any panel.
            property int stripeCount: Math.max(0, Math.floor(root.trackLength / 9))

            delegate: Rectangle {
                required property int index
                readonly property real along: root.padLead + index * 9

                x: root.isVertical ? root.laneOffset(parent.width, width) : along
                y: root.isVertical ? along : root.laneOffset(parent.height, height)
                width:  root.isVertical ? root.thickness : 2
                height: root.isVertical ? 2 : root.thickness
                radius: 1
                color: Appearance.colors.colOnSurfaceVariant
                opacity: (root.hovered || root.pressed) ? 0.3 : 0.18

                Behavior on opacity { NumberAnimation { duration: 140 } }
            }
        }

        // The map: a dot per landmark, larger for a section start.
        Repeater {
            model: root.hasMap ? root.markers : []

            delegate: Rectangle {
                id: dot
                required property var modelData
                required property int index

                readonly property bool major: modelData.major === true
                readonly property bool current: root.currentMarker === index
                readonly property bool pulled: root.nearestMarker === index
                readonly property bool hovered: root.hoveredMarker === index
                readonly property real baseSize: major ? 6 : 3
                readonly property real at: modelData.at ?? 0

                // Inside the span the thumb is showing: this is what makes the
                // dots answer to the bar rather than sit there.
                readonly property bool underThumb:
                    dot.at >= root.position - 0.001
                    && dot.at <= root.position + root.size + 0.001

                // Smooth falloff either side, so the response is a wave down
                // the map and not a row of switches flicking.
                readonly property real nearness: {
                    const span = Math.max(root.size, root.snapRadius * 2);
                    const d = Math.abs(dot.at - (root.position + root.size / 2));
                    return Math.max(0, 1 - d / span);
                }
                readonly property bool lit: dot.current || dot.pulled || dot.underThumb
                readonly property real along: root.padLead + root.trackLength * dot.at

                // Centred on the LANE, not the container, so the dots stay on
                // the same line as the bar however wide the container gets.
                x: root.isVertical
                    ? root.laneOffset(parent.width, root.thickness) + (root.thickness - width) / 2
                    : along - width / 2
                y: root.isVertical
                    ? along - height / 2
                    : root.laneOffset(parent.height, root.thickness) + (root.thickness - height) / 2
                // Grows where you are, under the magnet, the pointer, and the thumb.
                width: baseSize + (current ? 2 : 0) + (pulled ? 3 : 0) + (hovered ? 3 : 0)
                    + dot.nearness * 2
                height: width
                radius: width / 2

                color: dot.lit ? Appearance.colors.colPrimary
                               : Appearance.colors.colOnSurfaceVariant
                // Never invisible: a map you cannot see is not a map.
                opacity: root.size >= 1.0 ? 0
                    : (current || pulled) ? 1
                    : underThumb ? 0.85
                    : Math.min(1, (major ? 0.5 : 0.34)
                        + dot.nearness * 0.3
                        + ((root.hovered || root.pressed) ? 0.25 : 0))

                Behavior on opacity { NumberAnimation { duration: 140 } }
                Behavior on width {
                    NumberAnimation {
                        duration: Appearance.animation.elementMoveFast.duration
                        easing.type: Easing.BezierSpline
                        easing.bezierCurve: Appearance.animationCurves.expressiveFastSpatial
                    }
                }
                // Plain, not createObject(this): that is one animation object per dot.
                Behavior on color {
                    ColorAnimation {
                        duration: Appearance.animation.elementMoveFast.duration
                        easing.type: Appearance.animation.elementMoveFast.type
                        easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve
                    }
                }

                // Expands once when the magnet catches, so the snap is visible.
                Rectangle {
                    id: catchRing
                    x: (dot.width - width) / 2
                    y: (dot.height - height) / 2
                    width: dot.width   // the animation drives this
                    height: width
                    radius: width / 2
                    color: "transparent"
                    border.width: 1.5
                    border.color: Appearance.colors.colPrimary
                    opacity: 0
                    visible: opacity > 0

                    ParallelAnimation {
                        id: catchAnim
                        NumberAnimation {
                            target: catchRing; property: "width"
                            from: dot.width; to: dot.width * 3.4
                            duration: 420
                            easing.type: Easing.BezierSpline
                            easing.bezierCurve: Appearance.animationCurves.emphasizedDecel
                        }
                        NumberAnimation {
                            target: catchRing; property: "opacity"
                            from: 0.85; to: 0
                            duration: 420
                        }
                    }
                }

                // Only the caught dot.
                Connections {
                    target: root
                    function onSnapCaught(i) { if (i === index) catchAnim.restart() }
                }

                HoverHandler {
                    margin: 9
                    // Clearing unconditionally clobbers the neighbour just entered.
                    onHoveredChanged: {
                        if (hovered) root.hoveredMarker = index;
                        else if (root.hoveredMarker === index) root.hoveredMarker = -1;
                    }
                }
            }
        }

        // One label, not one per dot — only ever one is shown.
        Rectangle {
            id: mapLabel
            readonly property int shown: root.hoveredMarker >= 0 ? root.hoveredMarker : root.nearestMarker
            readonly property var marker: (root.hasMap && shown >= 0) ? root.markers[shown] : null
            readonly property real along: root.padLead
                + root.trackLength * (mapLabel.marker?.at ?? 0)

            visible: opacity > 0
            // nearestMarker is live during ordinary scrolling; gate on intent.
            opacity: (marker && String(marker.label ?? "").length > 0
                      && (Config.options?.appearance?.scrollbar?.labels ?? true)
                      && (root.hoveredMarker >= 0 || root.pressed)) ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: 120 } }

            // Along the track for its landmark; clear of the bar on the other
            // axis, on whichever side the bar is not.
            x: root.isVertical
                ? (root.mirrored ? parent.width + 6 : -width - 6)
                : Math.max(0, Math.min(root.width - width, along - width / 2))
            y: root.isVertical
                ? Math.max(0, Math.min(root.height - height, along - height / 2))
                : (root.mirrored ? parent.height + 6 : -height - 6)

            Behavior on x { NumberAnimation { duration: Appearance.animation.elementMoveFast.duration } }
            Behavior on y { NumberAnimation { duration: Appearance.animation.elementMoveFast.duration } }

            implicitWidth: mapLabelText.implicitWidth + 16
            implicitHeight: mapLabelText.implicitHeight + 8
            radius: Appearance.rounding.full
            color: Appearance.colors.colLayer2
            border.width: 1
            border.color: Appearance.colors.colLayer0Border

            StyledText {
                id: mapLabelText
                anchors.centerIn: parent
                text: mapLabel.marker?.label ?? ""
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: Appearance.colors.colOnLayer2
            }
        }
    }

    contentItem: Item {
        implicitWidth:  root.isVertical ? root.hitWidth : root.minimumThumbLength
        implicitHeight: root.isVertical ? root.minimumThumbLength : root.hitWidth

        Rectangle {
            id: thumb
            // Centred across the hit area, not filling it, so the target grows
            // without the bar looking heavier.
            x: root.isVertical ? root.laneOffset(parent.width, width) : 0
            y: root.isVertical ? 0 : root.laneOffset(parent.height, height)
            width:  root.isVertical ? root.thickness : parent.width
            height: root.isVertical ? parent.height : root.thickness
            radius: Math.min(width, height) / 2

            color: root.pressed ? Appearance.colors.colPrimary
                                : Appearance.colors.colOnSurfaceVariant

            opacity: root.policy === ScrollBar.AlwaysOn || (root.active && root.size < 1.0)
                ? (root.pressed ? 0.9 : root.hovered ? 0.75 : 0.5)
                : 0

            Behavior on opacity {
                NumberAnimation {
                    duration: 350
                    easing.type: Appearance.animation.elementMoveFast.type
                    easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve
                }
            }
            Behavior on width  { NumberAnimation { duration: Appearance.animation.elementMoveFast.duration } }
            Behavior on height { NumberAnimation { duration: Appearance.animation.elementMoveFast.duration } }
            Behavior on color {
                ColorAnimation {
                    duration: Appearance.animation.elementMoveFast.duration
                    easing.type: Appearance.animation.elementMoveFast.type
                    easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve
                }
            }
        }
    }
}
