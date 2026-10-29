import qs
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts

/**
 * A page pushed over a settings panel: the panel's content slides out to the left while the page
 * slides in from the right. The header stays: back on the left, the title in the middle, `actions`
 * on the right take its place (headerItem); `toolbar` (a search, chips) under it; the content fills the rest
 * and scrolls itself (a ListView). Esc and back close it. Only moves, no fades.
 *
 *     PanelPage {
 *         open: root.fooOpen
 *         title: qsTr("Foo")
 *         onClosed: root.fooOpen = false
 *         toolbar: [ PillTextField { ... } ]
 *         StyledListView { Layout.fillWidth: true; Layout.fillHeight: true }
 *     }
 */
Item {
    id: root

    property bool open: false
    property string title: ""
    property string subtitle: ""
    /// the card it covers; found as for PanelSheet (the Flickable's parent) when not set
    property Item host: null
    /// the panel's header: it stays put (the page's header takes its place, back and title)
    property Item headerItem: null
    default property alias content: pageContent.data
    property alias toolbar: toolbarCol.data
    property alias actions: actionRow.data

    signal closed()

    // where the move is: 0 closed, 1 open
    property real openT: open ? 1 : 0
    Behavior on openT {
        NumberAnimation {
            duration: Appearance.animation.elementMove.duration
            easing.type: Easing.BezierSpline
            easing.bezierCurve: root.open ? Appearance.animationCurves.emphasizedDecel
                                          : Appearance.animationCurves.emphasizedAccel
        }
    }
    visible: openT > 0
    z: 8500

    // Esc as for PanelSheet: wherever the focus is; the panel's own Esc waits (GlobalStates.openSheets)
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

    // into the card (out of the Flickable), filling it; the card's other children slide left with the
    // page (a third of the way, the way a pushed page does)
    readonly property bool isPanelOverlay: true
    Component.onCompleted: {
        if (!root.host) {
            let it = root.parent;
            let top = root;
            while (it) {
                if (it.contentY !== undefined && it.flickableDirection !== undefined && it.parent) { root.host = it.parent; break; }
                top = it;
                it = it.parent;
            }
            if (!root.host) root.host = top;
        }
        root.parent = root.host;
        root.anchors.fill = root.host;
        // the content sliding out must not draw past the card
        root.host.clip = true;
        for (const c of root.host.children) {
            if (c === root || c === root.headerItem || c.isPanelOverlay) continue;
            const tr = Qt.createQmlObject("import QtQuick; Translate {}", c);
            tr.x = Qt.binding(() => -root.openT * root.width / 3);
            c.transform = [tr];
        }
    }

    // the header stays where the panel's is (`headerItem`, covered in place, never moved): back, the
    // title in the middle, `actions`; only what is under it slides
    readonly property real headX: headerItem ? headerItem.x : 13
    readonly property real headY: headerItem ? headerItem.y : 13
    readonly property real headW: headerItem ? headerItem.width : width - 26
    readonly property real headH: headerItem ? headerItem.height : 40
    readonly property color cardColor: (root.host && root.host.color !== undefined) ? root.host.color : Appearance.colors.colLayer0

    // the page under the header, sliding in from the right
    Rectangle {
        id: page
        width: parent.width
        y: root.headY + root.headH + 4
        height: parent.height - y
        x: (1 - root.openT) * (parent.width + 8)
        color: root.cardColor
        bottomLeftRadius: (root.host && root.host.radius !== undefined) ? root.host.radius : 0
        bottomRightRadius: bottomLeftRadius
        clip: true

        // clicks stay on the page
        MouseArea { anchors.fill: parent; acceptedButtons: Qt.AllButtons }

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 14
            anchors.topMargin: 6
            spacing: 10

            ColumnLayout {
                id: toolbarCol
                Layout.fillWidth: true
                spacing: 8
                visible: children.length > 0
            }

            ColumnLayout {
                id: pageContent
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: 10
            }
        }
    }

    Rectangle {
        id: head
        visible: root.open
        x: root.headX - 4
        y: root.headY
        width: root.headW + 8
        height: root.headH
        color: root.cardColor
        MouseArea { anchors.fill: parent; acceptedButtons: Qt.AllButtons }

        RippleButton {
            id: back
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            implicitWidth: 34
            implicitHeight: 34
            buttonRadius: 17
            onClicked: root.closed()
            contentItem: MaterialSymbol {
                anchors.centerIn: parent
                text: "arrow_back"
                iconSize: 20
                color: Appearance.colors.colOnLayer0
            }
            StyledToolTip { text: qsTr("Back (Esc)") }
        }
        ColumnLayout {
            anchors.centerIn: parent
            width: parent.width - 2 * Math.max(back.width, actionRow.width) - 16
            spacing: 0
            StyledText {
                Layout.fillWidth: true
                horizontalAlignment: Text.AlignHCenter
                elide: Text.ElideRight
                text: root.title
                font.pixelSize: Appearance.font.pixelSize.normal
                font.weight: Font.Medium
                color: Appearance.colors.colOnLayer0
            }
            StyledText {
                Layout.fillWidth: true
                visible: root.subtitle.length > 0
                horizontalAlignment: Text.AlignHCenter
                elide: Text.ElideRight
                text: root.subtitle
                font.pixelSize: Appearance.font.pixelSize.smallest
                color: Appearance.colors.colSubtext
            }
        }
        Row {
            id: actionRow
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            spacing: 4
        }
    }
}
