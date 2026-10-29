import qs
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
    /// false: the content scrolls itself (a ListView that builds only the rows in view) and gets
    /// the room under the title as its height; `wantHeight` then says how tall it would like to be
    property bool scrolls: true
    property real wantHeight: sheetContent.implicitHeight

    signal closed()
    // a PanelPage leaves it where it is when it slides the card's content aside
    readonly property bool isPanelOverlay: true

    // Esc closes the sheet (not the panel under it): it takes the keys while open
    // Esc closes the sheet wherever the keyboard focus is (a text field in it, the panel under it); the
    // panel's own Esc waits while a sheet is open (GlobalStates.openSheets). The focus it had comes back.
    property Item focusBefore: null
    onOpenChanged: {
        GlobalStates.openSheets += open ? 1 : -1;
        if (open) { focusBefore = root.Window.activeFocusItem; root.forceActiveFocus(); }
        else if (focusBefore) focusBefore.forceActiveFocus();
    }
    Component.onDestruction: if (open) GlobalStates.openSheets -= 1
    Shortcut {
        sequence: "Escape"
        enabled: root.open
        onActivated: root.closed()
    }

    // Resolved ONCE, imperatively. As a binding on `parent` it would re-run
    // after the reparent, walk up from the new parent, find no Flickable and
    // move the sheet again.
    property Item host: null
    // a host set by the user of the sheet wins (a panel whose Flickable sits in a taller item than its card)
    Component.onCompleted: {
        if (root.host) { root.parent = root.host; root.anchors.fill = root.host; return; }
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
        // After the reparent, not declaratively: anchors on a layout-managed
        // item are undefined behaviour and Qt warns on every construction.
        root.anchors.fill = root.host;
    }

    readonly property real hostRadius: (root.host && root.host.radius !== undefined)
        ? root.host.radius : 0

    // anchors.fill: set in Component.onCompleted, after the reparent.
    z: 8000

    // Open and close as a move only: the card slides up from below the panel, the scrim's colour
    // fades. No item opacity or scale (they redrew the whole panel every frame of the animation).
    // Not `visible: open`: it has to outlive the dismissal to animate out of it.
    property real openT: open ? 1 : 0
    Behavior on openT {
        NumberAnimation {
            duration: Appearance.animation.elementMoveFast.duration
            easing.type: Easing.BezierSpline
            easing.bezierCurve: root.open ? Appearance.animationCurves.emphasizedDecel
                                          : Appearance.animationCurves.emphasizedAccel
        }
    }
    visible: openT > 0
    clip: true

    Rectangle {
        anchors.fill: parent
        // Same corners as the card it dims.
        radius: root.hostRadius
        color: Qt.rgba(Appearance.colors.colScrim.r, Appearance.colors.colScrim.g, Appearance.colors.colScrim.b, Appearance.colors.colScrim.a * root.openT)
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
        height: Math.min(parent.height - 24, header.implicitHeight + 10 + root.wantHeight + 28)

        // from below the panel's bottom edge into the middle (decelerates in, accelerates out)
        anchors.verticalCenterOffset: (1 - root.openT) * (parent.height + height) / 2

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
                    id: header
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

                // a long list (the exact themes) scrolls under the fixed title row
                StyledFlickable {
                    id: sheetFlick
                    Layout.fillWidth: true
                    Layout.preferredHeight: Math.max(0, cardWrap.height - 28 - header.height - 10)
                    interactive: root.scrolls
                    contentHeight: root.scrolls ? sheetContent.implicitHeight : height
                    clip: true
                    boundsBehavior: Flickable.StopAtBounds
                    ColumnLayout {
                        id: sheetContent
                        width: sheetFlick.width
                        height: root.scrolls ? implicitHeight : sheetFlick.height
                        spacing: 10
                    }
                }
            }
        }
    }
}
