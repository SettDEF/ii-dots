import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.models.quickToggles
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts

AndroidQuickToggleButton {
    id: root
    toggleModel: MicSliderToggle {}
    parentContainerType: "sliders"
    compactExpanded: true
    tallTile: false
    expandedDelegate: Component {
        Item {
            implicitHeight: 36
            SliderItem {
                anchors.fill: parent
                anchors.margins: 4
                materialSymbol: "mic"
                value: Audio.source?.audio?.volume ?? 0
                onMoved: { if (Audio.source?.audio) Audio.source.audio.volume = value }
            }
        }
    }
}
