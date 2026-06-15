import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.sidebarRight.quickToggles.androidStyle
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Hyprland
import Quickshell.Services.UPower

Rectangle {
    id: root

    property var screen: root.QsWindow.window?.screen
    property var brightnessMonitor: Brightness.getMonitorForScreen(screen)

    implicitWidth: contentItem.implicitWidth + root.horizontalPadding * 2
    implicitHeight: contentItem.implicitHeight + root.verticalPadding * 2
    radius: Appearance.rounding.normal
    color: Appearance.colors.colLayer1
    property real verticalPadding: 4
    property real horizontalPadding: 12

    Column {
        id: contentItem
        anchors {
            fill: parent
            leftMargin: root.horizontalPadding
            rightMargin: root.horizontalPadding
            topMargin: root.verticalPadding
            bottomMargin: root.verticalPadding
        }

        Loader {
            anchors {
                left: parent.left
                right: parent.right
            }
            visible: active
            active: Config.options.sidebar.quickSliders.showBrightness
            sourceComponent: QuickSlider {
                materialSymbol: "brightness_6"
                value: root.brightnessMonitor.brightness
                onMoved: {
                    root.brightnessMonitor.setBrightness(value)
                }
            }
        }

        Loader {
            id: volumeLoader
            anchors {
                left: parent.left
                right: parent.right
            }
            visible: active
            active: Config.options.sidebar.quickSliders.showVolume
            sourceComponent: QuickSlider {
                id: vol
                materialSymbol: "volume_up"
                value: Audio.sink.audio.volume
                iconTappable: true
                onMoved: {
                    Audio.sink.audio.volume = value
                }
                onIconClicked: sinkPickerLoader.toggle()
            }
        }
        // Sink picker shared by the volume slider. Lives outside the slider's
        // Loader so it survives the slider's lifetime and doesn't reset when
        // the slider value changes.
        Loader {
            id: sinkPickerLoader
            active: Config.options.sidebar.quickSliders.showVolume
            function toggle() {
                if (item) item.visible ? item.close() : item.open()
            }
            sourceComponent: SinkPicker {
                anchorItem: volumeLoader.item
            }
        }

        Loader {
            anchors {
                left: parent.left
                right: parent.right
            }
            visible: active
            active: Config.options.sidebar.quickSliders.showMic
            sourceComponent: QuickSlider {
                materialSymbol: "mic"
                value: Audio.source.audio.volume
                onMoved: {
                    Audio.source.audio.volume = value
                }
            }
        }
    }

    component QuickSlider: StyledSlider {
        id: quickSlider
        required property string materialSymbol
        property bool iconTappable: false
        signal iconClicked()
        configuration: StyledSlider.Configuration.M
        stopIndicatorValues: []

        MaterialSymbol {
            id: icon
            property bool nearFull: quickSlider.value >= 0.9
            anchors {
                verticalCenter: parent.verticalCenter
                right: nearFull ? quickSlider.handle.right : parent.right
                rightMargin: quickSlider.nearFull ? 14 : 8
            }
            iconSize: 20
            color: nearFull ? Appearance.colors.colOnPrimary : Appearance.colors.colOnSecondaryContainer
            text: quickSlider.materialSymbol

            Behavior on color {
                animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
            }
            Behavior on anchors.rightMargin {
                animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
            }

            // Optional tap target on the icon (sink picker for the volume slider).
            MouseArea {
                anchors.centerIn: parent
                width: 30; height: 30
                visible: quickSlider.iconTappable
                z: 10
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onPressed: mouse => mouse.accepted = true
                onClicked: quickSlider.iconClicked()
            }
        }
    }
}
