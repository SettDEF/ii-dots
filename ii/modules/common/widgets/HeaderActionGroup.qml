import qs.services
import qs.modules.common
import QtQuick

// The icon buttons of a panel header with the close, laid out as the button style says
// (services/ButtonStyles.qml): its gap, and one round pill around them if it asks for one. The
// close comes last, or first when the title bars have their buttons on the left.
//
//   HeaderActionGroup {
//       onClose: GlobalStates.fooOpen = false
//       HeaderIconButton { icon: "refresh"; tooltip: "Reload"; onClicked: … }
//   }
Rectangle {
    id: root
    default property alias actions: row.data
    property bool showClose: true
    property string closeTooltip: Translation.tr("Close")
    signal close()

    readonly property var decor: Config.options.appearance.glass.decor
    // the style's own values, from a button of it (they are all the same style)
    readonly property bool pill: closeBtn.face?.pill ?? true
    readonly property int gap: closeBtn.face?.gap ?? 2
    // the title bars' side: close first on the left (macOS-left), last on the right
    readonly property bool leftSide: decor.panels === true && (decor.buttons === "left" || decor.layout === "macos-left")

    implicitWidth: row.implicitWidth + (root.pill ? 6 : 0)
    implicitHeight: row.implicitHeight + (root.pill ? 6 : 0)
    radius: height / 2
    color: root.pill ? Appearance.colors.colLayer1 : "transparent"
    border.width: root.pill ? 1 : 0
    border.color: Appearance.colors.colLayer0Border

    Row {
        id: row
        anchors.centerIn: parent
        spacing: root.gap
        // the close is the last child: right to left puts it first, on the left
        layoutDirection: root.leftSide ? Qt.RightToLeft : Qt.LeftToRight
    }
    // Moved into `row` once the caller's buttons are in, so it is always last.
    Component.onCompleted: closeBtn.parent = row
    HeaderIconButton {
        id: closeBtn
        visible: root.showClose
        icon: "close"
        danger: true
        tooltip: root.closeTooltip
        onClicked: root.close()
    }
}
