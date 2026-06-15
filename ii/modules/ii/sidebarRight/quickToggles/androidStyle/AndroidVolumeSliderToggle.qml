import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.models.quickToggles
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts

AndroidQuickToggleButton {
    id: root
    toggleModel: VolumeSliderToggle {}
    parentContainerType: "sliders"
    compactExpanded: true
    tallTile: false
    expandedDelegate: Component {
        Item {
            id: cell
            implicitHeight: 36
            SliderItem {
                id: vSlider
                anchors.fill: parent
                anchors.margins: 4
                materialSymbol: "volume_up"
                value: Audio.sink?.audio?.volume ?? 0
                onMoved: { if (Audio.sink?.audio) Audio.sink.audio.volume = value }
                iconTappable: true
                onIconClicked: sinkPicker.visible ? sinkPicker.close() : sinkPicker.open()
            }
            SinkPicker {
                id: sinkPicker
                anchorItem: vSlider
            }
        }
    }
}
