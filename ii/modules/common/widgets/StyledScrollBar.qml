import QtQuick
import QtQuick.Controls
import qs.modules.common
import qs.modules.common.functions

/// The shell's scroll bar. Optionally a map of its content — see `markers`.
ScrollBar {
    id: root

    /// "minimal" | "rail" | "stripes"
    property string style: Config.options?.appearance?.scrollbar?.style ?? "minimal"

    /// Drawn width at rest, and engaged.
    property real barWidth: Config.options?.appearance?.scrollbar?.width ?? 4
    property real barWidthActive: Config.options?.appearance?.scrollbar?.activeWidth ?? 9
    /// Visible whenever content overflows, not only when engaged.
    property bool alwaysVisible: Config.options?.appearance?.scrollbar?.alwaysVisible ?? false
    /// Pointer target, wider than the drawn bar. Also a dead strip down every
    /// list's edge, since an attached ScrollBar overlays rather than reserves.
    property real hitWidth: 12
    /// Shortest the thumb may become, in pixels.
    property real minimumThumbHeight: 40

    /// Landmarks: [{ at, label, major }]. `at` is a fraction of the scrollable
    /// range; `major` draws the bigger dot. Empty = a plain scroll bar.
    property var markers: []
    /// Pull radius, as a fraction of the range.
    property real snapRadius: 0.035
    readonly property bool hasMap: (root.markers?.length ?? 0) > 0
        && (Config.options?.appearance?.scrollbar?.showMap ?? true)

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
        snapAnim.to = target;
        snapAnim.restart();
    }

    onPressedChanged: {
        if (!root.pressed && root.hasMap && root.nearestMarker >= 0
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
        easing.bezierCurve: Appearance.animationCurves.expressiveFastSpatial
    }

    policy: (root.alwaysVisible && root.size < 1.0) ? ScrollBar.AlwaysOn : ScrollBar.AsNeeded
    topPadding: Appearance.rounding.normal
    bottomPadding: Appearance.rounding.normal

    // `active` is left to Qt: it sets it while the flickable moves, not only on hover.
    implicitWidth: root.hitWidth
    // minimumSize is a fraction of the track; height is 0 before first layout.
    minimumSize: root.height > 0 ? Math.min(1, root.minimumThumbHeight / root.height) : 0

    // Drawn, not interactive: a MouseArea over the groove swallows the events
    // Qt's own press-and-drag needs.
    background: Item {
        implicitWidth: root.hitWidth

        Rectangle {
            // x, not a centring anchor: anchors resolve a pass later than the
            // width feeding them, so an animated width trails by a frame.
            x: (parent.width - width) / 2
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            anchors.topMargin: root.topPadding
            anchors.bottomMargin: root.bottomPadding
            width: (root.pressed || root.hovered) ? root.barWidthActive : root.barWidth
            radius: width / 2
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
            Behavior on width {
                NumberAnimation {
                    duration: Appearance.animation.elementMoveFast.duration
                    easing.type: Appearance.animation.elementMoveFast.type
                    easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve
                }
            }
        }

        // stripes: the track as countable rungs, with the thumb riding over.
        Repeater {
            model: root.style === "stripes" && root.size < 1.0 ? stripeCount : 0

            // From the height, so rungs stay evenly spaced on any panel.
            property int stripeCount: {
                const track = Math.max(0, root.height - root.topPadding - root.bottomPadding);
                return Math.max(0, Math.floor(track / 9));
            }

            delegate: Rectangle {
                required property int index
                readonly property real track: Math.max(0,
                    root.height - root.topPadding - root.bottomPadding)

                x: (parent.width - width) / 2
                y: root.topPadding + index * 9
                width: (root.pressed || root.hovered) ? root.barWidthActive : root.barWidth
                height: 2
                radius: 1
                color: Appearance.colors.colOnSurfaceVariant
                opacity: (root.hovered || root.pressed) ? 0.3 : 0.18

                Behavior on opacity { NumberAnimation { duration: 140 } }
                Behavior on width {
                    NumberAnimation {
                        duration: Appearance.animation.elementMoveFast.duration
                        easing.type: Appearance.animation.elementMoveFast.type
                        easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve
                    }
                }
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

                readonly property real trackLength: Math.max(0,
                    root.height - root.topPadding - root.bottomPadding)
                readonly property real baseSize: major ? 6 : 3

                readonly property bool hovered: root.hoveredMarker === index

                // Is this landmark inside the part of the content the thumb is
                // showing? This is what makes the dots answer to the bar rather
                // than sit there: scrolling lights them as the thumb reaches them.
                readonly property real at: modelData.at ?? 0
                readonly property bool underThumb:
                    dot.at >= root.position - 0.001
                    && dot.at <= root.position + root.size + 0.001

                // Smooth falloff either side, so the response is a wave passing
                // down the map and not a row of switches flicking.
                readonly property real nearness: {
                    const span = Math.max(root.size, root.snapRadius * 2);
                    const d = Math.abs(dot.at - (root.position + root.size / 2));
                    return Math.max(0, 1 - d / span);
                }
                readonly property bool lit: dot.current || dot.pulled || dot.underThumb

                x: (parent.width - width) / 2
                y: root.topPadding + trackLength * dot.at - height / 2
                // Grows where you are, under the magnet, the pointer, and the thumb.
                width: baseSize + (current ? 2 : 0) + (pulled ? 3 : 0) + (hovered ? 3 : 0)
                    + dot.nearness * 2
                height: width
                radius: width / 2

                color: dot.lit ? Appearance.colors.colPrimary
                               : Appearance.colors.colOnSurfaceVariant
                // Never invisible: a map you cannot see is not a map. The
                // resting floor rises with nearness to the thumb.
                opacity: root.size >= 1.0 ? 0
                    : (current || pulled) ? 1
                    : underThumb ? 0.85
                    : Math.min(1, (major ? 0.5 : 0.34)
                        + dot.nearness * 0.3
                        + ((root.hovered || root.pressed) ? 0.25 : 0))

                Behavior on opacity { NumberAnimation { duration: 140 } }
                Behavior on width   {
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

                // 9px margin: a 3px circle is not clickable. DragThreshold, so
                // dragging the bar from a dot still works.
                TapHandler {
                    gesturePolicy: TapHandler.DragThreshold
                    margin: 9
                    onTapped: {
                        root.snapAnimTo(modelData.at ?? 0);
                        root.markerActivated(index);
                    }
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

            visible: opacity > 0
            // nearestMarker is live during ordinary scrolling; gate on intent.
            opacity: (marker && String(marker.label ?? "").length > 0
                      && (Config.options?.appearance?.scrollbar?.labels ?? true)
                      && (root.hoveredMarker >= 0 || root.pressed)) ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: 120 } }

            // Opens away from whichever edge the bar is on.
            anchors.right: root.mirrored ? undefined : parent.left
            anchors.rightMargin: 6
            anchors.left: root.mirrored ? parent.right : undefined
            anchors.leftMargin: 6
            y: {
                const at = mapLabel.marker?.at ?? 0;
                const track = Math.max(0, root.height - root.topPadding - root.bottomPadding);
                return Math.max(0, Math.min(root.height - height,
                    root.topPadding + track * at - height / 2));
            }
            Behavior on y {
                NumberAnimation {
                    duration: Appearance.animation.elementMoveFast.duration
                    easing.type: Easing.BezierSpline
                    easing.bezierCurve: Appearance.animationCurves.expressiveFastSpatial
                }
            }

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
        implicitWidth: root.hitWidth
        implicitHeight: root.minimumThumbHeight

        Rectangle {
            id: thumb
            // Centred in the hit area, not filling it. Bound, not anchored — see above.
            x: (parent.width - width) / 2
            y: 0
            width: (root.pressed || root.hovered) ? root.barWidthActive : root.barWidth
            height: parent.height
            radius: width / 2

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
            Behavior on width {
                NumberAnimation {
                    duration: Appearance.animation.elementMoveFast.duration
                    easing.type: Appearance.animation.elementMoveFast.type
                    easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve
                }
            }
            Behavior on color {
                animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
            }
        }
    }
}
