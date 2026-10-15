import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts

/// "Show in folder" for an exported file, with a ▾ menu: Dolphin, the
/// default file manager, a custom one (config), Open video, Copy path.
/// The main button uses the last choice (else the config's file_manager).
RowLayout {
    id: rv
    required property var doc
    property string path: ""
    /// Called after an action (e.g. to hide the toast).
    signal acted()
    spacing: 0
    DialogButton {
        objectName: "revealMain"
        buttonText: "Show in folder"
        onClicked: { rv.doc.reveal(rv.path); rv.acted(); }
        StyledToolTip { text: ({ dolphin: "Opens Dolphin with the file selected", xdg: "Opens the default file manager with the file selected", custom: "Runs " + rv.doc.customFileManager })[rv.doc.revealDefault] ?? "" }
    }
    RippleButton {
        objectName: "revealMore"
        implicitWidth: 28; implicitHeight: 32
        buttonRadius: Appearance.rounding.full
        onClicked: rv.doc.revealMenu(rv, width, height, rv.path)
        contentItem: MaterialSymbol {
            horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter
            text: "arrow_drop_down"; iconSize: Appearance.font.pixelSize.larger
            color: Appearance.colors.colPrimary
        }
        StyledToolTip { text: "Open with…" }
    }
}
