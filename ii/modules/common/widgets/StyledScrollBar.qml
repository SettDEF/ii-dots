import QtQuick
import QtQuick.Controls
import qs.modules.common
import qs.modules.common.functions

/**
 * The shell's scroll bar.
 *
 * Four things it used to get wrong, in order of how much they cost:
 *
 * 1. It was 4px wide and 4px was also the whole target, so grabbing it was a
 *    game of patience. The drawn bar is still 4px; the INTERACTIVE area is now
 *    much wider than what you can see, which is how every scroll bar worth
 *    using works.
 *
 * 2. `active: hovered || pressed` meant it stayed invisible while you were
 *    scrolling — the one moment you want to see where you are. Qt's own logic
 *    already shows it during a flick; the override was throwing that away.
 *
 * 3. With a long list the thumb shrank to a few pixels and became both
 *    unreadable and ungrabbable. It now has a floor.
 *
 * 4. Nothing acknowledged a drag, so you could not tell a bar you were holding
 *    from one you were merely near.
 */
ScrollBar {
    id: root

    /// Drawn width at rest, and while engaged.
    property real barWidth: 4
    property real barWidthActive: 9
    /// Width of the area that actually responds to the pointer.
    ///
    /// An attached ScrollBar OVERLAYS its flickable rather than reserving a
    /// column, and the whole control takes presses — so this is also a strip
    /// down the right edge of every list where clicks go to the bar instead of
    /// to the content under it. 12 is the compromise: three times the old 4px
    /// target, and narrow enough to land on a list's right padding rather than
    /// on its rows.
    property real hitWidth: 12
    /// Shortest the thumb may become, in pixels.
    property real minimumThumbHeight: 40

    // ── Map and magnets ─────────────────────────────────────────────────
    // Optional. Give the bar the landmarks in its content and it becomes a map
    // of that content rather than an undifferentiated strip: each marker is
    // drawn as a tick on the track, and a drag that comes close to one is
    // pulled onto it.
    //
    //   markers: [
    //       { at: 0.00, label: "Setup", major: true },
    //       { at: 0.09, label: "System" },
    //       { at: 0.18, label: "Bar", current: true },
    //   ]
    //
    // `at` is a fraction of the scrollable range, i.e. the `position` the bar
    // would have with that landmark at the top. `major` draws the bigger dot —
    // a section start against the items inside it. `current` is where you are.
    // Empty means the bar behaves exactly as it did before, so every existing
    // use is unaffected.
    property var markers: []
    /// How near a marker has to be, as a fraction of the range, before it pulls.
    property real snapRadius: 0.035
    readonly property bool hasMap: (root.markers?.length ?? 0) > 0

    /// Emitted when a dot on the map is clicked. The bar scrolls there itself;
    /// this is for a host that wants to do more — the settings rail switches
    /// page on it, so the map navigates rather than merely scrolls.
    signal markerActivated(int index)

    /// Index of the dot under the pointer, or -1.
    property int hoveredMarker: -1

    /// Which landmark is the one you are "at", or -1.
    ///
    /// Deliberately its own property rather than a `current` field inside
    /// `markers`: a new array makes the Repeater destroy and rebuild every
    /// dot, so carrying the current index in there meant changing page threw
    /// the whole map away and built it again.
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

    // The magnet. Only while dragging, and only once the drag settles — pulling
    // during the drag itself would fight the pointer, which feels like a stuck
    // scroll rather than a snap.
    signal snapCaught(int index)

    function snapAnimTo(target) {
        snapAnim.to = target;
        snapAnim.restart();
    }

    onPressedChanged: {
        if (!root.pressed && root.hasMap && root.nearestMarker >= 0) {
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

    policy: ScrollBar.AsNeeded
    topPadding: Appearance.rounding.normal
    bottomPadding: Appearance.rounding.normal

    // Deliberately NOT overriding `active`. Qt sets it while the attached
    // flickable is moving as well as on hover, so leaving it alone is what
    // makes the bar appear when you scroll with the wheel.

    implicitWidth: root.hitWidth
    // `minimumSize` is a fraction of the track, so the pixel floor has to be
    // converted — and guarded, because height is 0 before the first layout.
    minimumSize: root.height > 0 ? Math.min(1, root.minimumThumbHeight / root.height) : 0

    // A track, so that once you are near the bar you can see how far it runs
    // and aim at it. It only appears while the bar is engaged, so nothing
    // changes for anyone who never touches it.
    //
    // Drawn, not interactive: Qt's own press-and-drag handling lives on the
    // control, and a MouseArea laid over the groove to add click-to-jump
    // swallows the events that make dragging work. Not worth trading a
    // working drag for a nicer click.
    background: Item {
        implicitWidth: root.hitWidth

        Rectangle {
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            anchors.topMargin: root.topPadding
            anchors.bottomMargin: root.bottomPadding
            width: (root.pressed || root.hovered) ? root.barWidthActive : root.barWidth
            radius: width / 2
            color: Appearance.colors.colOnSurfaceVariant
            opacity: (root.hovered || root.pressed) && root.size < 1.0 ? 0.16 : 0

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

        // The map.
        //
        // A dot per landmark down the track: small for an item, large for the
        // start of a section, filled for wherever you are now. Ticks were the
        // first attempt and read as measurement marks on a ruler; dots read as
        // places, which is what they are.
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

                anchors.horizontalCenter: parent.horizontalCenter
                y: root.topPadding + trackLength * (modelData.at ?? 0) - height / 2
                // Grows when it is where you are, again when the magnet has
                // hold of it — so the pull is visible before you let go — and
                // again under the pointer, so it is obvious it can be clicked.
                width: baseSize + (current ? 2 : 0) + (pulled ? 3 : 0) + (hovered ? 3 : 0)
                height: width
                radius: width / 2

                color: (current || pulled) ? Appearance.colors.colPrimary
                                           : Appearance.colors.colOnSurfaceVariant
                // Visible at rest, or it is not a map — but faint, so a
                // scrollbar still reads as a scrollbar until you go near it.
                opacity: root.size >= 1.0 ? 0
                    : (current || pulled) ? 1
                    : (root.hovered || root.pressed) ? (major ? 0.7 : 0.45)
                    : (major ? 0.38 : 0.22)

                Behavior on opacity { NumberAnimation { duration: 140 } }
                Behavior on width   {
                    NumberAnimation {
                        duration: Appearance.animation.elementMoveFast.duration
                        easing.type: Easing.BezierSpline
                        easing.bezierCurve: Appearance.animationCurves.expressiveFastSpatial
                    }
                }
                // A plain ColorAnimation, not colorAnimation.createObject(this):
                // that builds one animation OBJECT per dot, and there is one
                // dot per page.
                Behavior on color {
                    ColorAnimation {
                        duration: Appearance.animation.elementMoveFast.duration
                        easing.type: Appearance.animation.elementMoveFast.type
                        easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve
                    }
                }

                // A ring that expands and fades once when the magnet catches,
                // so a snap is something you SEE happen rather than something
                // you notice afterwards.
                Rectangle {
                    id: catchRing
                    anchors.centerIn: parent
                    // Not bound to the dot: the animation drives this, and a
                    // binding would be dropped on the first frame anyway.
                    width: dot.width
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

                // Only fires for the dot that was actually caught.
                Connections {
                    target: root
                    function onSnapCaught(i) { if (i === index) catchAnim.restart() }
                }

                // The hit target is bigger than the dot, because a 3px circle
                // is not something anyone can click. Transparent, so the map
                // still looks like dots.
                //
                // DragThreshold, so the tap is abandoned the moment the pointer
                // moves: dragging the bar from a dot has to keep working, and
                // a handler that grabs on press would take that away.
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
                    // Clearing unconditionally clobbers the neighbour: moving
                    // from one dot to the next, the one being LEFT reports
                    // false after the one being entered has already claimed the
                    // slot, and the label vanishes mid-slide.
                    onHoveredChanged: {
                        if (hovered) root.hoveredMarker = index;
                        else if (root.hoveredMarker === index) root.hoveredMarker = -1;
                    }
                }
            }
        }

        // The label for whichever dot is under the pointer or being pulled.
        // One instance, not one per dot: only ever one is shown, and forty
        // permanently-constructed pills to show one of them is waste.
        Rectangle {
            id: mapLabel
            readonly property int shown: root.hoveredMarker >= 0 ? root.hoveredMarker : root.nearestMarker
            readonly property var marker: (root.hasMap && shown >= 0) ? root.markers[shown] : null

            visible: opacity > 0
            // Only while the pointer is on the map or dragging the bar.
            // `nearestMarker` is live whenever the position happens to pass
            // near a dot, so without this the label popped up on its own during
            // ordinary scrolling.
            opacity: (marker && String(marker.label ?? "").length > 0
                      && (root.hoveredMarker >= 0 || root.pressed)) ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: 120 } }

            // Opens away from the bar, whichever edge the bar is on. A bar
            // moved to the left with LayoutMirroring would otherwise open its
            // label off the side of the window.
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
            // The thumb is centred in the wider hit area rather than filling
            // it, so the target grows without the bar looking heavier.
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.verticalCenter: parent.verticalCenter
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
