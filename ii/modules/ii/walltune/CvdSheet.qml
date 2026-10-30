import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts

/// Look > Colour > Colour-blindness preview: the whole screen as seen with a colour-vision
/// deficiency (a screen shader through AppDisplay, which owns it; never saved, Off puts back what was).
PanelSheet {
    id: sheet
    title: qsTr("Colour-blindness preview")
    subtitle: qsTr("The whole screen, as others see it")

    readonly property string dir: `${Directories.config}/quickshell/ii/scripts/colors/cvd/`
    readonly property var kinds: [
        { id: "", label: qsTr("Off"), about: qsTr("Your own colours") },
        { id: "protanopia", label: qsTr("Red-blind"), about: qsTr("Protanopia: about 1 in 100 men") },
        { id: "deuteranopia", label: qsTr("Green-blind"), about: qsTr("Deuteranopia: the most common, about 1 in 20 men in a milder form") },
        { id: "tritanopia", label: qsTr("Blue-blind"), about: qsTr("Tritanopia: rare") },
        { id: "achromatopsia", label: qsTr("No colour"), about: qsTr("Achromatopsia: only light and dark") }
    ]
    readonly property string current: {
        const p = AppDisplay.cvdPreview;
        return p === "" ? "" : p.slice(p.lastIndexOf("/") + 1).replace(".frag", "");
    }

    PaletteCard {
        Repeater {
            model: sheet.kinds
            delegate: ColumnLayout {
                id: kr
                required property var modelData
                required property int index
                Layout.fillWidth: true
                spacing: 0
                PaletteDivider { visible: kr.index > 0 }
                PaletteRow {
                    Layout.fillWidth: true
                    glyph: kr.modelData.id === "" ? "visibility" : "visibility_lock"
                    title: kr.modelData.label
                    subtitle: kr.modelData.about
                    lit: sheet.current === kr.modelData.id
                    trailing: sheet.current === kr.modelData.id ? "chevron" : ""
                    chevronIcon: "check"
                    onClicked: AppDisplay.cvdPreview = kr.modelData.id === "" ? "" : sheet.dir + kr.modelData.id + ".frag"
                }
            }
        }
    }

    StyledText {
        Layout.fillWidth: true
        wrapMode: Text.WordWrap
        text: qsTr("A preview only: it is not saved, and Off puts back the screen effect you had.")
        font.pixelSize: Appearance.font.pixelSize.smallest
        color: Appearance.colors.colSubtext
    }
}
