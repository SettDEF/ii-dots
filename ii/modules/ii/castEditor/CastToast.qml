import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts

/// After an export: the file, with Show in folder / Copy, for a few seconds.
Rectangle {
    id: toast
    objectName: "exportToast"
    required property var doc
    property string path: ""
    visible: opacity > 0
    opacity: shown ? 1 : 0
    property bool shown: false
    Behavior on opacity { NumberAnimation { duration: 160 } }
    implicitWidth: row.implicitWidth + 28
    implicitHeight: 52
    radius: Appearance.rounding.normal
    color: Appearance.colors.colLayer2
    border.width: 1
    border.color: Appearance.colors.colLayer0Border

    Connections {
        target: toast.doc
        function onLastExportChanged() {
            if (toast.doc.lastExport.length === 0) return;
            toast.path = toast.doc.lastExport;
            toast.shown = true;
            hideTimer.restart();
        }
    }
    Timer { id: hideTimer; interval: 9000; onTriggered: toast.shown = false }
    HoverHandler { onHoveredChanged: if (hovered) hideTimer.stop(); else hideTimer.restart() }

    RowLayout {
        id: row
        anchors { verticalCenter: parent.verticalCenter; left: parent.left; leftMargin: 14 }
        spacing: 10
        MaterialSymbol { text: "check_circle"; iconSize: Appearance.font.pixelSize.larger; color: Appearance.colors.colPrimary }
        StyledText {
            text: "Exported " + toast.path.split("/").pop()
            color: Appearance.colors.colOnLayer2
            font.pixelSize: Appearance.font.pixelSize.smaller
        }
        CastReveal { objectName: "toastReveal"; doc: toast.doc; path: toast.path; onActed: toast.shown = false }
        DialogButton { buttonText: "Copy"; onClicked: { toast.doc.copyFile(toast.path); toast.shown = false; } }
        RippleButton {
            implicitWidth: 30; implicitHeight: 30
            buttonRadius: Appearance.rounding.full
            onClicked: toast.shown = false
            contentItem: MaterialSymbol {
                horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter
                text: "close"; iconSize: Appearance.font.pixelSize.normal; color: Appearance.colors.colOnLayer2
            }
        }
    }
}
