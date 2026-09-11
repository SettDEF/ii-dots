import QtQuick
import qs.modules.common

Rectangle {
    id: root

    radius: Appearance.rounding.normal
    color: Appearance.colors.colLayer1

    signal openAudioOutputDialog()
    signal openAudioInputDialog()
    signal openDevicesDialog()
    signal openNightLightDialog()
    signal openWifiDialog()
    signal openKdeConnectDialog()
    signal openMonitorsDialog()
    signal openRssDialog()
}
