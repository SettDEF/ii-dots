import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts

ColumnLayout {
    id: panel
    spacing: 6
    readonly property real vol: Audio.sink?.audio?.volume ?? 0
    readonly property bool muted: Audio.sink?.audio?.muted ?? false

    StyledText {
        Layout.fillWidth: true
        text: Audio.sink?.description ?? Translation.tr("No output")
        font.pixelSize: Appearance.font.pixelSize.smaller
        color: Appearance.colors.colOnLayer0
        elide: Text.ElideRight
    }
    RowLayout {
        Layout.fillWidth: true
        spacing: 6
        RippleButton {
            implicitWidth: 30
            implicitHeight: 30
            buttonRadius: Appearance.rounding.full
            onClicked: if (Audio.sink?.audio) Audio.sink.audio.muted = !panel.muted
            contentItem: MaterialSymbol {
                anchors.centerIn: parent
                text: panel.muted ? "volume_off" : "volume_up"
                iconSize: Appearance.font.pixelSize.large
                color: panel.muted ? Appearance.colors.colSubtext : Appearance.colors.colOnLayer0
            }
        }
        StyledSlider {
            Layout.fillWidth: true
            from: 0
            to: 1
            value: panel.vol
            onMoved: if (Audio.sink?.audio) Audio.sink.audio.volume = value
        }
        StyledText {
            Layout.preferredWidth: 34
            horizontalAlignment: Text.AlignRight
            text: `${Math.round(panel.vol * 100)}%`
            font.pixelSize: Appearance.font.pixelSize.smaller
            font.family: Appearance.font.family.monospace
            color: Appearance.colors.colSubtext
        }
    }
}
