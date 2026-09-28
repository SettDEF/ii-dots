import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts

/**
 * A sheet over a settings panel: scrim, a card, a title row with a close
 * button.
 *
 * Reparented OUT of the Flickable that panel content lives in (a sheet drawn
 * inside one is clipped by it and scrolls with it) and INTO the item that holds
 * that Flickable - the panel's rounded card. Not the window's top item: the
 * layer surface is a plain rectangle larger than the card, so a scrim filling
 * it painted square corners past the card's rounded ones, and did not follow
 * the card's own slide-in transform.
 *
 *     PanelSheet {
 *         open: GlobalStates.somethingOpen
 *         title: Translation.tr("Something")
 *         onClosed: GlobalStates.somethingOpen = false
 *         ColumnLayout { ... }      // default children go in the card
 *     }
 */
Item {
    id: root

    property bool open: false
    property string title: ""
    /// Optional second line under the title.
    property string subtitle: ""
    /// Cap on the card's width; it shrinks to fit a narrow panel.
    property real maxWidth: 360
    default property alias content: sheetContent.data

    signal closed()

    // Resolved ONCE, imperatively. As a binding on `parent` it would re-run
    // after the reparent, walk up from the new parent, find no Flickable and
    // move the sheet again.
    property Item host: null
    Component.onCompleted: {
        let it = root.parent;
        let top = root;
        while (it) {
            if (it.contentY !== undefined && it.flickableDirection !== undefined && it.parent) {
                root.host = it.parent;
                break;
            }
            top = it;
            it = it.parent;
        }
        if (!root.host) root.host = top;
        root.parent = root.host;
        // Anchored HERE rather than declaratively, because until the line above
        // runs this item is still a child of the ColumnLayout it was written
        // in, and `anchors.fill` on a layout-managed item is undefined
        // behaviour that Qt warns about on every construction. Filling only
        // after the reparent means there is no moment where both are true.
        root.anchors.fill = root.host;
    }

    readonly property real hostRadius: (root.host && root.host.radius !== undefined)
        ? root.host.radius : 0

    // anchors.fill is assigned in Component.onCompleted, after the reparent.
    z: 8000

    // Not `visible: open`: it has to outlive the dismissal to animate out of it.
    visible: opacity > 0
    opacity: root.open ? 1 : 0
    Behavior on opacity {
        NumberAnimation {
            duration: Appearance.animation.elementMoveFast.duration
            easing.type: Easing.BezierSpline
            easing.bezierCurve: Appearance.animationCurves.standard
        }
    }

    Rectangle {
        anchors.fill: parent
        // Same corners as the card it dims.
        radius: root.hostRadius
        color: Appearance.colors.colScrim
        MouseArea {
            anchors.fill: parent
            enabled: root.open
            acceptedButtons: Qt.AllButtons
            onPressed: root.closed()
        }
    }

    // The card and its shadow share ONE transform. As siblings the shadow did
    // not scale with the card, so every open and close flashed a full-size
    // shadow behind a 0.95 card - a dark ring popping out past its corners -
    // and RectangularShadow caches its texture, so a card that changed height
    // (the picker unfolding) kept drawing the old one's outline.
    Item {
        id: cardWrap
        anchors.centerIn: parent
        width: Math.min(parent.width - 24, root.maxWidth)
        height: Math.min(parent.height - 24, sheetCol.implicitHeight + 28)

        // Rises into place; accelerates out so dismissing feels immediate.
        scale: root.open ? 1 : 0.95
        anchors.verticalCenterOffset: root.open ? 0 : 14
        Behavior on scale {
            NumberAnimation {
                duration: Appearance.animation.elementMoveFast.duration
                easing.type: Easing.BezierSpline
                easing.bezierCurve: root.open ? Appearance.animationCurves.emphasizedDecel
                                              : Appearance.animationCurves.emphasizedAccel
            }
        }
        Behavior on anchors.verticalCenterOffset {
            NumberAnimation {
                duration: Appearance.animation.elementMoveFast.duration
                easing.type: Easing.BezierSpline
                easing.bezierCurve: root.open ? Appearance.animationCurves.emphasizedDecel
                                              : Appearance.animationCurves.emphasizedAccel
            }
        }

        StyledRectangularShadow { target: sheetCard }

        Rectangle {
            id: sheetCard
            anchors.fill: parent
            radius: Appearance.rounding.large
            color: Appearance.m3colors.m3surfaceContainerHigh
            border.width: 1
            border.color: Appearance.colors.colLayer0Border

            // Swallow clicks, or picking something dismisses through the scrim.
            MouseArea { anchors.fill: parent; acceptedButtons: Qt.AllButtons }

            ColumnLayout {
                id: sheetCol
                anchors { left: parent.left; right: parent.right; top: parent.top; margins: 14 }
                spacing: 10

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 1
                        StyledText {
                            Layout.fillWidth: true
                            elide: Text.ElideRight
                            text: root.title
                            font.pixelSize: Appearance.font.pixelSize.small
                            font.weight: Font.Medium
                            color: Appearance.colors.colOnLayer0
                        }
                        StyledText {
                            Layout.fillWidth: true
                            visible: root.subtitle.length > 0
                            elide: Text.ElideRight
                            text: root.subtitle
                            font.pixelSize: Appearance.font.pixelSize.smallest
                            color: Appearance.colors.colSubtext
                        }
                    }
                    RippleButton {
                        implicitWidth: 26
                        implicitHeight: 26
                        buttonRadius: 13
                        onClicked: root.closed()
                        contentItem: MaterialSymbol {
                            anchors.centerIn: parent
                            text: "close"
                            iconSize: 16
                            color: Appearance.colors.colOnLayer0
                        }
                    }
                }

                ColumnLayout {
                    id: sheetContent
                    Layout.fillWidth: true
                    spacing: 10
                }
            }
        }
    }
}
