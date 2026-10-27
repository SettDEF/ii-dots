pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets

// Your Discord voice controls — Mute, Deafen, and the input mode (Voice
// Activity / Push to Talk). The same DiscordVoice service and commands as the
// voice section of Discord's dock menu (dock/DockAppMenu.qml), so the two are
// always the same switches showing the same state.
RowLayout {
    id: root
    readonly property var v: DiscordVoice.settings
    visible: !!root.v
    spacing: 6

    component VoiceButton: Rectangle {
        id: vb
        property string icon: ""
        property string tip: ""
        property bool alert: false
        signal clicked
        implicitWidth: 32
        implicitHeight: 32
        radius: 16
        color: vb.alert ? Appearance.m3colors.m3errorContainer
             : vbHover.hovered ? Appearance.colors.colLayer2Hover : Appearance.colors.colLayer2
        Behavior on color { ColorAnimation { duration: 120 } }
        HoverHandler { id: vbHover; cursorShape: Qt.PointingHandCursor }
        TapHandler { onTapped: vb.clicked() }
        MaterialSymbol {
            anchors.centerIn: parent
            text: vb.icon
            iconSize: 18
            fill: vb.alert ? 1 : 0
            color: vb.alert ? Appearance.m3colors.m3onErrorContainer : Appearance.colors.colOnLayer2
        }
        StyledToolTip { text: vb.tip; extraVisibleCondition: false; alternativeVisibleCondition: vbHover.hovered }
    }

    VoiceButton {
        icon: root.v?.mute ? "mic_off" : "mic"
        alert: !!root.v?.mute
        tip: root.v?.mute ? Translation.tr("Unmute") : Translation.tr("Mute")
        onClicked: DiscordVoice.command("toggleMute")
    }
    VoiceButton {
        icon: root.v?.deaf ? "headset_off" : "headphones"
        alert: !!root.v?.deaf
        tip: root.v?.deaf ? Translation.tr("Undeafen") : Translation.tr("Deafen")
        onClicked: DiscordVoice.command("toggleDeaf")
    }
    Item { Layout.fillWidth: true }

    // input mode as one switch: Voice Activity ↔ Push to Talk
    Rectangle {
        id: mode
        readonly property bool ptt: root.v?.mode === "PUSH_TO_TALK"
        implicitWidth: modeRow.implicitWidth + 20
        implicitHeight: 32
        radius: 16
        color: modeHover.hovered ? Appearance.colors.colLayer2Hover : Appearance.colors.colLayer2
        Behavior on color { ColorAnimation { duration: 120 } }
        HoverHandler { id: modeHover; cursorShape: Qt.PointingHandCursor }
        TapHandler { onTapped: DiscordVoice.command("mode", mode.ptt ? "VOICE_ACTIVITY" : "PUSH_TO_TALK") }
        RowLayout {
            id: modeRow
            anchors.centerIn: parent
            spacing: 6
            MaterialSymbol { text: mode.ptt ? "keyboard" : "graphic_eq"; iconSize: 16; color: Appearance.colors.colOnLayer2 }
            StyledText {
                text: mode.ptt ? Translation.tr("Push to Talk") : Translation.tr("Voice Activity")
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: Appearance.colors.colOnLayer2
            }
        }
        StyledToolTip { text: Translation.tr("Switch input mode"); extraVisibleCondition: false; alternativeVisibleCondition: modeHover.hovered }
    }
}
