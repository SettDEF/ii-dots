import qs.modules.common
import QtQuick
import QtQuick.Layouts

// The header every panel shares: icon, title, then the panel's icon buttons and the close.
// With appearance.glass.decor.panels on (default) it is a window title bar's (ii-decor): its
// height, title size and weight, dots and side; off, the round pill of buttons (Palette's old).
//
//   PanelHeader {
//       icon: "tune"; title: qsTr("Palette")
//       onClose: GlobalStates.fooOpen = false
//       HeaderIconButton { icon: "restart_alt"; onClicked: … }   // with the close
//       middle: [ StyledText { text: "working…" } ]               // between title and buttons
//   }
RowLayout {
    id: root
    property string icon: ""
    property string title: ""
    property bool showClose: true
    // the panel's icon buttons (HeaderIconButton), with the close
    default property alias actions: group.actions
    // anything between the title and the buttons (a status line)
    property alias middle: middleRow.data
    signal close()

    readonly property var decor: Config.options.appearance.glass.decor
    readonly property bool asDecor: decor.panels === true
    readonly property bool leftSide: group.leftSide

    implicitHeight: root.asDecor ? Math.max(decor.height ?? 28, group.implicitHeight) : group.implicitHeight
    spacing: 8

    // the buttons sit in one of two slots: left of the icon, or after the status line
    Item {
        id: leftSlot
        visible: root.leftSide
        implicitWidth: group.implicitWidth
        implicitHeight: group.implicitHeight
        Layout.alignment: Qt.AlignVCenter
    }
    MaterialSymbol {
        visible: root.icon !== "" && (!root.asDecor || root.decor.icon !== false)
        text: root.icon
        iconSize: root.asDecor ? (root.decor.iconSize ?? 16) : Appearance.font.pixelSize.normal
        color: Appearance.colors.colPrimary
        opacity: 0.8
        Layout.alignment: Qt.AlignVCenter
    }
    StyledText {
        Layout.fillWidth: true
        Layout.alignment: Qt.AlignVCenter
        text: root.title
        elide: Text.ElideRight
        // decor.titleSize is in points, like the title bars'
        font.pixelSize: root.asDecor ? Math.round((root.decor.titleSize ?? 11) * 4 / 3) : Appearance.font.pixelSize.small
        font.weight: root.asDecor && root.decor.titleBold ? Font.Bold : Font.Medium
        color: Appearance.colors.colOnLayer0
    }
    Row {
        id: middleRow
        spacing: 6
        Layout.alignment: Qt.AlignVCenter
    }
    Item {
        id: rightSlot
        visible: !root.leftSide
        implicitWidth: group.implicitWidth
        implicitHeight: group.implicitHeight
        Layout.alignment: Qt.AlignVCenter
    }
    HeaderActionGroup {
        id: group
        parent: root.leftSide ? leftSlot : rightSlot
        anchors.centerIn: parent
        showClose: root.showClose
        onClose: root.close()
    }
}
