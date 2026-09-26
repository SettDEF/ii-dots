import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts

ColumnLayout {
    spacing: 6
    StyledText {
        visible: Places.loaded && Places.entries.length === 0
        Layout.fillWidth: true
        text: Translation.tr("No folders found")
        font.pixelSize: Appearance.font.pixelSize.smaller
        color: Appearance.colors.colSubtext
    }
    PlacesGrid { Layout.fillWidth: true }
}
