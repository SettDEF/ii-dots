import qs.services
import qs.modules.common
import qs.modules.common.functions
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Services.Notifications

/**
 * A group of notifications from the same app.
 * Similar to Android's notifications
 */
MouseArea { // Notification group area
    id: root
    property var notificationGroup
    property var notifications: notificationGroup?.notifications ?? []
    property int notificationCount: notifications.length
    property bool multipleNotifications: notificationCount > 1
    property bool expanded: false
    property bool popup: false
    property real padding: 10
    implicitHeight: background.implicitHeight

    property real dragConfirmThreshold: 70 // Drag further to discard notification
    property real dismissOvershoot: 20 // Account for gaps and bouncy animations
    property var qmlParent: root?.parent?.parent // There's something between this and the parent ListView
    property var parentDragIndex: qmlParent?.dragIndex
    property var parentDragDistance: qmlParent?.dragDistance
    property var dragIndexDiff: Math.abs(parentDragIndex - index)
    property real xOffset: dragIndexDiff == 0 ? parentDragDistance : 
        Math.abs(parentDragDistance) > dragConfirmThreshold ? 0 :
        dragIndexDiff == 1 ? (parentDragDistance * 0.3) :
        dragIndexDiff == 2 ? (parentDragDistance * 0.1) : 0

    function destroyWithAnimation(left = false) {
        root.qmlParent.resetDrag()
        background.anchors.leftMargin = background.anchors.leftMargin; // Break binding
        destroyAnimation.left = left;
        destroyAnimation.running = true;
    }

    hoverEnabled: true
    onContainsMouseChanged: {
        if (!root.popup) return;
        if (root.containsMouse) root.notifications.forEach(notif => {
            Notifications.cancelTimeout(notif.notificationId);
        });
        else root.notifications.forEach(notif => {
            Notifications.restartTimeout(notif.notificationId);
        });
    }

    SequentialAnimation { // Drag finish animation
        id: destroyAnimation
        property bool left: true
        running: false

        NumberAnimation {
            target: background.anchors
            property: "leftMargin"
            to: (root.width + root.dismissOvershoot) * (destroyAnimation.left ? -1 : 1)
            duration: Appearance.animation.elementMove.duration
            easing.type: Appearance.animation.elementMove.type
            easing.bezierCurve: Appearance.animation.elementMove.bezierCurve
        }
        onFinished: () => {
            root.notifications.forEach((notif) => {
                Qt.callLater(() => {
                    Notifications.discardNotification(notif.notificationId);
                });
            });
        }
    }

    function toggleExpanded() {
        if (expanded) implicitHeightAnim.enabled = true;
        else implicitHeightAnim.enabled = false;
        root.expanded = !root.expanded;
    }

    DragManager { // Drag manager
        id: dragManager
        anchors.fill: parent
        interactive: !expanded
        automaticallyReset: false
        acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton

        onPressed: {
            if (mouse.button === Qt.RightButton) 
                root.toggleExpanded();
        }

        onClicked: (mouse) => {
            if (mouse.button === Qt.MiddleButton) 
                root.destroyWithAnimation();
        }

        onDraggingChanged: () => {
            if (dragging) {
                root.qmlParent.dragIndex = root.index ?? root.parent.children.indexOf(root);
            }
        }

        onDragDiffXChanged: () => {
            root.qmlParent.dragDistance = dragDiffX;
        }

        onDragReleased: (diffX, diffY) => {
            if (Math.abs(diffX) > root.dragConfirmThreshold)
                root.destroyWithAnimation(diffX < 0);
            else 
                dragManager.resetDrag();
        }
    }

    StyledRectangularShadow {
        target: background
        visible: popup
    }
    Rectangle { // Background of the notification
        id: background
        anchors.left: parent.left
        width: parent.width
        color: popup ? Appearance.colors.colBackgroundSurfaceContainer : Appearance.colors.colLayer2
        radius: Appearance.rounding.normal
        anchors.leftMargin: root.xOffset

        Behavior on anchors.leftMargin {
            enabled: !dragManager.dragging
            NumberAnimation {
                duration: Appearance.animation.elementMove.duration
                easing.type: Appearance.animation.elementMove.type
                easing.bezierCurve: Appearance.animationCurves.expressiveFastSpatial
            }
        }
        
        clip: true
        implicitHeight: root.expanded ? 
            row.implicitHeight + padding * 2 :
            Math.min(80, row.implicitHeight + padding * 2)

        Behavior on implicitHeight {
            id: implicitHeightAnim
            animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
        }

        RowLayout { // Left column for icon, right column for content
            id: row
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.margins: root.padding
            spacing: 10

            NotificationAppIcon { // Icons
                Layout.alignment: Qt.AlignTop
                Layout.fillWidth: false
                image: root?.multipleNotifications ? "" : notificationGroup?.notifications[0]?.image ?? ""
                appIcon: root.notificationGroup?.appIcon
                summary: root.notificationGroup?.notifications[root.notificationCount - 1]?.summary
                urgency: root.notifications.some(n => n.urgency === NotificationUrgency.Critical.toString()) ? 
                    NotificationUrgency.Critical : NotificationUrgency.Normal
            }

            ColumnLayout { // Content
                Layout.fillWidth: true
                spacing: expanded ? (root.multipleNotifications ? 
                    (notificationGroup?.notifications[root.notificationCount - 1].image != "") ? 35 : 
                    5 : 0) : 0
                // spacing: 00
                Behavior on spacing {
                    animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                }

                Item { // App name (or summary when there's only 1 notif) and time
                    id: topRow
                    // spacing: 0
                    Layout.fillWidth: true
                    property real fontSize: Appearance.font.pixelSize.smaller
                    property bool showAppName: root.multipleNotifications
                    implicitHeight: Math.max(topTextRow.implicitHeight, expandButton.implicitHeight)

                    RowLayout {
                        id: topTextRow
                        anchors.left: parent.left
                        anchors.right: muteButton.left
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 5
                        StyledText {
                            id: appName
                            elide: Text.ElideRight
                            Layout.fillWidth: true
                            text: (topRow.showAppName ?
                                notificationGroup?.appName :
                                notificationGroup?.notifications[0]?.summary) || ""
                            font.pixelSize: topRow.showAppName ?
                                topRow.fontSize :
                                Appearance.font.pixelSize.small
                            color: topRow.showAppName ?
                                Appearance.colors.colSubtext :
                                Appearance.colors.colOnLayer2
                        }
                        StyledText {
                            id: timeText
                            // Layout.fillWidth: true
                            Layout.rightMargin: 10
                            horizontalAlignment: Text.AlignLeft
                            text: NotificationUtils.getFriendlyNotifTimeString(notificationGroup?.time)
                            font.pixelSize: topRow.fontSize
                            color: Appearance.colors.colSubtext
                        }
                    }
                    // Per-app mute toggle: silence future popups from this app
                    // (they still log to the notification centre).
                    Rectangle {
                        id: muteButton
                        // `hovered` so StyledToolTip (which checks parent.hovered)
                        // shows only on hover instead of always.
                        property bool hovered: muteMa.containsMouse
                        readonly property string appName: root.notificationGroup?.appName ?? ""
                        // Reads the map directly (0 = forever, timestamp = until).
                        readonly property bool muted: {
                            const e = Notifications.mutedApps[appName]
                            return e !== undefined && (e === 0 || e === true || e > Date.now())
                        }
                        visible: appName !== ""
                        implicitWidth: appName !== "" ? 26 : 0
                        implicitHeight: 26
                        radius: 13
                        anchors.right: expandButton.left
                        anchors.rightMargin: 2
                        anchors.verticalCenter: parent.verticalCenter
                        color: muteMa.containsMouse ? Appearance.colors.colLayer2Hover : "transparent"
                        Behavior on color { ColorAnimation { duration: 100 } }
                        // MouseArea (not TapHandler): it sits on top of the
                        // group's DragManager MouseArea and actually grabs the
                        // click — a TapHandler lost the press to the drag area.
                        MouseArea {
                            id: muteMa
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            acceptedButtons: Qt.LeftButton
                            // Act on press and accept the event (same as
                            // RippleButton) so the group's DragManager can't
                            // swallow it before a release-based onClicked fires.
                            // Opens the per-app mute menu (mounted on the list
                            // view, in the centre and the popup alike).
                            onPressed: (event) => {
                                event.accepted = true
                                const app = muteButton.appName
                                if (!app) return
                                const menu = root.ListView.view?.contextMenu ?? null
                                if (!menu) { Notifications.toggleAppMute(app); return }
                                const muted = Notifications.isAppMuted(app)
                                const soundOff = Notifications.isAppSoundOff(app)
                                const pt = muteButton.mapToItem(menu, 0, muteButton.height + 2)
                                const model = []
                                // Colour scales with how long the silence lasts.
                                if (muted) {
                                    model.push({ icon: "notifications_active", label: Translation.tr("Unmute"),
                                                 iconColor: Appearance.colors.colPrimary,
                                                 onTriggered: () => Notifications.unmuteApp(app) })
                                } else {
                                    model.push({ icon: "timer", label: Translation.tr("Mute for 15 minutes"),
                                                 iconColor: Appearance.m3colors.m3tertiary,
                                                 onTriggered: () => Notifications.muteApp(app, 15) })
                                    model.push({ icon: "schedule", label: Translation.tr("Mute for 1 hour"),
                                                 iconColor: Appearance.m3colors.m3secondary,
                                                 onTriggered: () => Notifications.muteApp(app, 60) })
                                    model.push({ icon: "notifications_off", label: Translation.tr("Mute forever"),
                                                 iconColor: Appearance.m3colors.m3error,
                                                 onTriggered: () => Notifications.muteApp(app, 0) })
                                }
                                model.push({ separator: true })
                                model.push({ icon: soundOff ? "volume_up" : "volume_off",
                                             label: soundOff ? Translation.tr("Enable sound") : Translation.tr("Disable sound"),
                                             iconColor: Appearance.colors.colSubtext,
                                             onTriggered: () => Notifications.setAppSoundOff(app, !soundOff) })
                                menu.popup(pt.x, pt.y, model)
                            }
                        }
                        MaterialSymbol {
                            anchors.centerIn: parent
                            text: muteButton.muted ? "notifications_off" : "notifications_active"
                            iconSize: Appearance.font.pixelSize.larger
                            color: muteButton.muted ? Appearance.m3colors.m3error : Appearance.colors.colSubtext
                            opacity: muteButton.muted ? 1 : 0.6
                        }
                        StyledToolTip {
                            text: muteButton.muted
                                ? Translation.tr("Unmute notifications from %1").arg(muteButton.appName)
                                : Translation.tr("Mute notifications from %1").arg(muteButton.appName)
                        }
                    }
                    NotificationGroupExpandButton {
                        id: expandButton
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        count: root.notificationCount
                        expanded: root.expanded
                        fontSize: topRow.fontSize
                        onClicked: { root.toggleExpanded() }
                        altAction: () => { root.toggleExpanded() }

                        StyledToolTip {
                            text: Translation.tr("Tip: right-clicking a group\nalso expands it")
                        }
                    }
                }

                StyledListView { // Notification body (expanded)
                    id: notificationsColumn
                    implicitHeight: contentHeight
                    Layout.fillWidth: true
                    spacing: expanded ? 5 : 3
                    // clip: true
                    interactive: false
                    Behavior on spacing {
                        animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                    }
                    model: ScriptModel {
                        values: root.expanded ? root.notifications.slice().reverse() : 
                            root.notifications.slice().reverse().slice(0, 2)
                    }
                    delegate: NotificationItem {
                        required property int index
                        required property var modelData
                        notificationObject: modelData
                        expanded: root.expanded
                        onlyNotification: (root.notificationCount === 1)
                        opacity: (!root.expanded && index == 1 && root.notificationCount > 2) ? 0.5 : 1
                        visible: root.expanded || (index < 2)
                        anchors.left: parent?.left
                        anchors.right: parent?.right
                    }
                }

            }
        }
    }
}
