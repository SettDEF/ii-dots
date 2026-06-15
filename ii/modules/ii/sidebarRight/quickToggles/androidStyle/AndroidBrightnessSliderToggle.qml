import qs
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.models.quickToggles
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts
import Quickshell

AndroidQuickToggleButton {
    id: root
    toggleModel: BrightnessSliderToggle {}
    parentContainerType: "sliders"
    compactExpanded: true
    tallTile: false
    property var screen: root.QsWindow.window?.screen
    property var brightnessMonitor: screen ? Brightness.getMonitorForScreen(screen) : null

    expandedDelegate: Component {
        Item {
            implicitHeight: 36
            SliderItem {
                anchors.fill: parent
                anchors.margins: 4
                materialSymbol: "brightness_6"
                value: root.brightnessMonitor?.brightness ?? 0
                onMoved: { if (root.brightnessMonitor) root.brightnessMonitor.setBrightness(value) }
            }
        }
    }
}
