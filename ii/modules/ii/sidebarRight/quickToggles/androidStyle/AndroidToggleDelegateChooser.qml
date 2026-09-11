pragma ComponentBehavior: Bound
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Bluetooth
import "../../../deviceControl" as DeviceModule

DelegateChooser {
    id: root
    property bool editMode: false
    required property real baseCellWidth
    required property real baseCellHeight
    required property real spacing
    required property int startingIndex
    property int tabIndex: -1
    // True when the chooser is rendering the unused-toggle tray (no × overlay).
    property bool inTray: false
    signal openAudioOutputDialog()
    signal openAudioInputDialog()
    signal openDevicesDialog()
    signal openNightLightDialog()
    signal openWifiDialog()
    signal openKdeConnectDialog()
    signal openMonitorsDialog()
    signal openRssDialog()

    role: "type"

    DelegateChoice { roleValue: "antiFlashbang"; AndroidAntiFlashbangToggle {
        required property int index
        required property var modelData
        buttonIndex: root.startingIndex + index
        buttonData: modelData
        editMode: root.editMode
        tabIndex: root.tabIndex
        inTray: root.inTray
        expandedSize: modelData.size > 1
        baseCellWidth: root.baseCellWidth
        baseCellHeight: root.baseCellHeight
        cellSpacing: root.spacing
        cellSize: modelData.size
        onOpenMenu: {
            root.openNightLightDialog()
        }
    } }

    DelegateChoice { roleValue: "audioOutput"; AndroidAudioOutputToggle {
        required property int index
        required property var modelData
        buttonIndex: root.startingIndex + index
        buttonData: modelData
        editMode: root.editMode
        tabIndex: root.tabIndex
        inTray: root.inTray
        expandedSize: modelData.size > 1
        baseCellWidth: root.baseCellWidth
        baseCellHeight: root.baseCellHeight
        cellSpacing: root.spacing
        cellSize: modelData.size
        onOpenMenu: {
            root.openAudioOutputDialog()
        }
    } }

    DelegateChoice { roleValue: "audio"; AndroidAudioToggle {
        required property int index
        required property var modelData
        buttonIndex: root.startingIndex + index
        buttonData: modelData
        editMode: root.editMode
        tabIndex: root.tabIndex
        inTray: root.inTray
        expandedSize: modelData.size > 1
        baseCellWidth: root.baseCellWidth
        baseCellHeight: root.baseCellHeight
        cellSpacing: root.spacing
        cellSize: modelData.size
        onOpenMenu: {
            root.openAudioOutputDialog()
        }
    } }

    DelegateChoice { roleValue: "bluetooth"; AndroidBluetoothToggle {
        required property int index
        required property var modelData
        buttonIndex: root.startingIndex + index
        buttonData: modelData
        editMode: root.editMode
        tabIndex: root.tabIndex
        inTray: root.inTray
        expandedSize: modelData.size > 1
        baseCellWidth: root.baseCellWidth
        baseCellHeight: root.baseCellHeight
        cellSpacing: root.spacing
        cellSize: modelData.size
        onOpenMenu: {
            root.openDevicesDialog()
        }
    } }

    DelegateChoice { roleValue: "vpn"; AndroidVpnToggle {
        required property int index
        required property var modelData
        buttonIndex: root.startingIndex + index
        buttonData: modelData
        editMode: root.editMode
        tabIndex: root.tabIndex
        inTray: root.inTray
        expandedSize: modelData.size > 1
        baseCellWidth: root.baseCellWidth
        baseCellHeight: root.baseCellHeight
        cellSpacing: root.spacing
        cellSize: modelData.size
    } }

    DelegateChoice { roleValue: "cloudflareWarp"; AndroidCloudflareWarpToggle {
        required property int index
        required property var modelData
        buttonIndex: root.startingIndex + index
        buttonData: modelData
        editMode: root.editMode
        tabIndex: root.tabIndex
        inTray: root.inTray
        expandedSize: modelData.size > 1
        baseCellWidth: root.baseCellWidth
        baseCellHeight: root.baseCellHeight
        cellSpacing: root.spacing
        cellSize: modelData.size
    } }

    DelegateChoice { roleValue: "colorPicker"; AndroidColorPickerToggle {
        required property int index
        required property var modelData
        buttonIndex: root.startingIndex + index
        buttonData: modelData
        editMode: root.editMode
        tabIndex: root.tabIndex
        inTray: root.inTray
        expandedSize: modelData.size > 1
        baseCellWidth: root.baseCellWidth
        baseCellHeight: root.baseCellHeight
        cellSpacing: root.spacing
        cellSize: modelData.size
    } }

    DelegateChoice { roleValue: "darkMode"; AndroidDarkModeToggle {
        required property int index
        required property var modelData
        buttonIndex: root.startingIndex + index
        buttonData: modelData
        editMode: root.editMode
        tabIndex: root.tabIndex
        inTray: root.inTray
        expandedSize: modelData.size > 1
        baseCellWidth: root.baseCellWidth
        baseCellHeight: root.baseCellHeight
        cellSpacing: root.spacing
        cellSize: modelData.size
    } }

    DelegateChoice { roleValue: "easyEffects"; AndroidEasyEffectsToggle {
        required property int index
        required property var modelData
        buttonIndex: root.startingIndex + index
        buttonData: modelData
        editMode: root.editMode
        tabIndex: root.tabIndex
        inTray: root.inTray
        expandedSize: modelData.size > 1
        baseCellWidth: root.baseCellWidth
        baseCellHeight: root.baseCellHeight
        cellSpacing: root.spacing
        cellSize: modelData.size
    } }

    DelegateChoice { roleValue: "windows"; AndroidWindowsToggle {
        required property int index
        required property var modelData
        buttonIndex: root.startingIndex + index
        buttonData: modelData
        editMode: root.editMode
        tabIndex: root.tabIndex
        inTray: root.inTray
        expandedSize: modelData.size > 1
        baseCellWidth: root.baseCellWidth
        baseCellHeight: root.baseCellHeight
        cellSpacing: root.spacing
        cellSize: modelData.size
    } }

    DelegateChoice { roleValue: "gameMode"; AndroidGameModeToggle {
        required property int index
        required property var modelData
        buttonIndex: root.startingIndex + index
        buttonData: modelData
        editMode: root.editMode
        tabIndex: root.tabIndex
        inTray: root.inTray
        expandedSize: modelData.size > 1
        baseCellWidth: root.baseCellWidth
        baseCellHeight: root.baseCellHeight
        cellSpacing: root.spacing
        cellSize: modelData.size
    } }

    DelegateChoice { roleValue: "mounting"; AndroidMountingToggle {
        required property int index
        required property var modelData
        buttonIndex: root.startingIndex + index
        buttonData: modelData
        editMode: root.editMode
        tabIndex: root.tabIndex
        inTray: root.inTray
        expandedSize: modelData.size > 1
        baseCellWidth: root.baseCellWidth
        baseCellHeight: root.baseCellHeight
        cellSpacing: root.spacing
        cellSize: modelData.size
    } }

    DelegateChoice { roleValue: "email"; AndroidEmailToggle {
        required property int index
        required property var modelData
        buttonIndex: root.startingIndex + index
        buttonData: modelData
        editMode: root.editMode
        tabIndex: root.tabIndex
        inTray: root.inTray
        expandedSize: modelData.size > 1
        baseCellWidth: root.baseCellWidth
        baseCellHeight: root.baseCellHeight
        cellSpacing: root.spacing
        cellSize: modelData.size
    } }

    DelegateChoice { roleValue: "miniMeters"; AndroidMiniMetersToggle {
        required property int index
        required property var modelData
        buttonIndex: root.startingIndex + index
        buttonData: modelData
        editMode: root.editMode
        tabIndex: root.tabIndex
        inTray: root.inTray
        expandedSize: modelData.size > 1
        baseCellWidth: root.baseCellWidth
        baseCellHeight: root.baseCellHeight
        cellSpacing: root.spacing
        cellSize: modelData.size
    } }

    DelegateChoice { roleValue: "tabletMode"; AndroidTabletModeToggle {
        required property int index
        required property var modelData
        buttonIndex: root.startingIndex + index
        buttonData: modelData
        editMode: root.editMode
        tabIndex: root.tabIndex
        inTray: root.inTray
        expandedSize: modelData.size > 1
        baseCellWidth: root.baseCellWidth
        baseCellHeight: root.baseCellHeight
        cellSpacing: root.spacing
        cellSize: modelData.size
    } }

    DelegateChoice { roleValue: "idleInhibitor"; AndroidIdleInhibitorToggle {
        required property int index
        required property var modelData
        buttonIndex: root.startingIndex + index
        buttonData: modelData
        editMode: root.editMode
        tabIndex: root.tabIndex
        inTray: root.inTray
        expandedSize: modelData.size > 1
        baseCellWidth: root.baseCellWidth
        baseCellHeight: root.baseCellHeight
        cellSpacing: root.spacing
        cellSize: modelData.size
    } }

    DelegateChoice { roleValue: "sleepTimer"; AndroidSleepTimerToggle {
        required property int index
        required property var modelData
        buttonIndex: root.startingIndex + index
        buttonData: modelData
        editMode: root.editMode
        tabIndex: root.tabIndex
        inTray: root.inTray
        expandedSize: modelData.size > 1
        baseCellWidth: root.baseCellWidth
        baseCellHeight: root.baseCellHeight
        cellSpacing: root.spacing
        cellSize: modelData.size
    } }

    DelegateChoice { roleValue: "mic"; AndroidMicToggle {
        required property int index
        required property var modelData
        buttonIndex: root.startingIndex + index
        buttonData: modelData
        editMode: root.editMode
        tabIndex: root.tabIndex
        inTray: root.inTray
        expandedSize: modelData.size > 1
        baseCellWidth: root.baseCellWidth
        baseCellHeight: root.baseCellHeight
        cellSpacing: root.spacing
        cellSize: modelData.size
        onOpenMenu: {
            root.openAudioInputDialog()
        }
    } }

    DelegateChoice { roleValue: "musicRecognition"; AndroidMusicRecognition {
        required property int index
        required property var modelData
        buttonIndex: root.startingIndex + index
        buttonData: modelData
        editMode: root.editMode
        tabIndex: root.tabIndex
        inTray: root.inTray
        expandedSize: modelData.size > 1
        baseCellWidth: root.baseCellWidth
        baseCellHeight: root.baseCellHeight
        cellSpacing: root.spacing
        cellSize: modelData.size
    } }

    DelegateChoice { roleValue: "network"; AndroidNetworkToggle {
        required property int index
        required property var modelData
        buttonIndex: root.startingIndex + index
        buttonData: modelData
        editMode: root.editMode
        tabIndex: root.tabIndex
        inTray: root.inTray
        expandedSize: modelData.size > 1
        baseCellWidth: root.baseCellWidth
        baseCellHeight: root.baseCellHeight
        cellSpacing: root.spacing
        cellSize: modelData.size
        onOpenMenu: {
            root.openWifiDialog()
        }
    } }

    DelegateChoice { roleValue: "nightLight"; AndroidNightLightToggle {
        required property int index
        required property var modelData
        buttonIndex: root.startingIndex + index
        buttonData: modelData
        editMode: root.editMode
        tabIndex: root.tabIndex
        inTray: root.inTray
        expandedSize: modelData.size > 1
        baseCellWidth: root.baseCellWidth
        baseCellHeight: root.baseCellHeight
        cellSpacing: root.spacing
        cellSize: modelData.size
        onOpenMenu: {
            root.openNightLightDialog()
        }
    } }

    DelegateChoice { roleValue: "torrentKeepAlive"; AndroidTorrentKeepAliveToggle {
        required property int index
        required property var modelData
        buttonIndex: root.startingIndex + index
        buttonData: modelData
        editMode: root.editMode
        tabIndex: root.tabIndex
        inTray: root.inTray
        expandedSize: modelData.size > 1
        baseCellWidth: root.baseCellWidth
        baseCellHeight: root.baseCellHeight
        cellSpacing: root.spacing
        cellSize: modelData.size
    } }

    DelegateChoice { roleValue: "notifications"; AndroidNotificationToggle {
        required property int index
        required property var modelData
        buttonIndex: root.startingIndex + index
        buttonData: modelData
        editMode: root.editMode
        tabIndex: root.tabIndex
        inTray: root.inTray
        expandedSize: modelData.size > 1
        baseCellWidth: root.baseCellWidth
        baseCellHeight: root.baseCellHeight
        cellSpacing: root.spacing
        cellSize: modelData.size
    } }

    DelegateChoice { roleValue: "onScreenKeyboard"; AndroidOnScreenKeyboardToggle {
        required property int index
        required property var modelData
        buttonIndex: root.startingIndex + index
        buttonData: modelData
        editMode: root.editMode
        tabIndex: root.tabIndex
        inTray: root.inTray
        expandedSize: modelData.size > 1
        baseCellWidth: root.baseCellWidth
        baseCellHeight: root.baseCellHeight
        cellSpacing: root.spacing
        cellSize: modelData.size
    } }

    DelegateChoice { roleValue: "powerProfile"; AndroidPowerProfileToggle {
        required property int index
        required property var modelData
        buttonIndex: root.startingIndex + index
        buttonData: modelData
        editMode: root.editMode
        tabIndex: root.tabIndex
        inTray: root.inTray
        expandedSize: modelData.size > 1
        baseCellWidth: root.baseCellWidth
        baseCellHeight: root.baseCellHeight
        cellSpacing: root.spacing
        cellSize: modelData.size
    } }

    DelegateChoice { roleValue: "kdeconnect"; AndroidKdeConnectToggle {
        required property int index
        required property var modelData
        buttonIndex: root.startingIndex + index
        buttonData: modelData
        editMode: root.editMode
        tabIndex: root.tabIndex
        inTray: root.inTray
        expandedSize: modelData.size > 1
        baseCellWidth: root.baseCellWidth
        baseCellHeight: root.baseCellHeight
        cellSpacing: root.spacing
        cellSize: modelData.size
        onOpenMenu: {
            root.openKdeConnectDialog()
        }
    } }

    DelegateChoice { roleValue: "lastfm"; AndroidLastFmToggle {
        required property int index
        required property var modelData
        buttonIndex: root.startingIndex + index
        buttonData: modelData
        editMode: root.editMode
        tabIndex: root.tabIndex
        inTray: root.inTray
        expandedSize: modelData.size > 1
        baseCellWidth: root.baseCellWidth
        baseCellHeight: root.baseCellHeight
        cellSpacing: root.spacing
        cellSize: modelData.size
    } }

    DelegateChoice { roleValue: "monitors"; AndroidMonitorsToggle {
        required property int index
        required property var modelData
        buttonIndex: root.startingIndex + index
        buttonData: modelData
        editMode: root.editMode
        tabIndex: root.tabIndex
        inTray: root.inTray
        expandedSize: modelData.size > 1
        baseCellWidth: root.baseCellWidth
        baseCellHeight: root.baseCellHeight
        cellSpacing: root.spacing
        cellSize: modelData.size
        onOpenMenu: {
            root.openMonitorsDialog()
        }
    } }

    DelegateChoice { roleValue: "rss"; AndroidRssToggle {
        required property int index
        required property var modelData
        buttonIndex: root.startingIndex + index
        buttonData: modelData
        editMode: root.editMode
        tabIndex: root.tabIndex
        inTray: root.inTray
        expandedSize: modelData.size > 1
        baseCellWidth: root.baseCellWidth
        baseCellHeight: root.baseCellHeight
        cellSpacing: root.spacing
        cellSize: modelData.size
        onRequestRssDialog: root.openRssDialog()
    } }

    DelegateChoice { roleValue: "offload"; AndroidOffloadToggle {
        required property int index
        required property var modelData
        buttonIndex: root.startingIndex + index
        buttonData: modelData
        editMode: root.editMode
        tabIndex: root.tabIndex
        inTray: root.inTray
        expandedSize: modelData.size > 1
        baseCellWidth: root.baseCellWidth
        baseCellHeight: root.baseCellHeight
        cellSpacing: root.spacing
        cellSize: modelData.size
    } }

    DelegateChoice { roleValue: "volumeSlider"; AndroidVolumeSliderToggle {
        required property int index
        required property var modelData
        buttonIndex: root.startingIndex + index
        buttonData: modelData
        editMode: root.editMode
        tabIndex: root.tabIndex
        inTray: root.inTray
        expandedSize: modelData.size > 1
        baseCellWidth: root.baseCellWidth
        baseCellHeight: root.baseCellHeight
        cellSpacing: root.spacing
        cellSize: modelData.size
    } }

    DelegateChoice { roleValue: "brightnessSlider"; AndroidBrightnessSliderToggle {
        required property int index
        required property var modelData
        buttonIndex: root.startingIndex + index
        buttonData: modelData
        editMode: root.editMode
        tabIndex: root.tabIndex
        inTray: root.inTray
        expandedSize: modelData.size > 1
        baseCellWidth: root.baseCellWidth
        baseCellHeight: root.baseCellHeight
        cellSpacing: root.spacing
        cellSize: modelData.size
    } }

    DelegateChoice { roleValue: "micSlider"; AndroidMicSliderToggle {
        required property int index
        required property var modelData
        buttonIndex: root.startingIndex + index
        buttonData: modelData
        editMode: root.editMode
        tabIndex: root.tabIndex
        inTray: root.inTray
        expandedSize: modelData.size > 1
        baseCellWidth: root.baseCellWidth
        baseCellHeight: root.baseCellHeight
        cellSpacing: root.spacing
        cellSize: modelData.size
    } }

    DelegateChoice { roleValue: "sliders"; AndroidSlidersToggle {
        required property int index
        required property var modelData
        buttonIndex: root.startingIndex + index
        buttonData: modelData
        editMode: root.editMode
        tabIndex: root.tabIndex
        inTray: root.inTray
        expandedSize: false       // container tiles never use inline expansion
        baseCellWidth: root.baseCellWidth
        baseCellHeight: root.baseCellHeight
        cellSpacing: root.spacing
        cellSize: 1               // forced 1×1 — drawer hosts the rich content
    } }

    DelegateChoice { roleValue: "devices"; AndroidDevicesToggle {
        required property int index
        required property var modelData
        buttonIndex: root.startingIndex + index
        buttonData: modelData
        editMode: root.editMode
        tabIndex: root.tabIndex
        inTray: root.inTray
        expandedSize: modelData.size > 1
        baseCellWidth: root.baseCellWidth
        baseCellHeight: root.baseCellHeight
        cellSpacing: root.spacing
        cellSize: modelData.size
        onOpenMenu: root.openDevicesDialog()
    } }

    // Saved layouts predate the rename. Keeping the old key mapped to the same
    // delegate means an existing grid keeps its tile instead of silently losing
    // it; nothing has to migrate.
    DelegateChoice { roleValue: "bluetoothDevices"; AndroidDevicesToggle {
        required property int index
        required property var modelData
        buttonIndex: root.startingIndex + index
        buttonData: modelData
        editMode: root.editMode
        tabIndex: root.tabIndex
        inTray: root.inTray
        expandedSize: modelData.size > 1
        baseCellWidth: root.baseCellWidth
        baseCellHeight: root.baseCellHeight
        cellSpacing: root.spacing
        cellSize: modelData.size
        onOpenMenu: root.openDevicesDialog()
    } }

    DelegateChoice { roleValue: "midi"; AndroidMidiToggle {
        required property int index
        required property var modelData
        buttonIndex: root.startingIndex + index
        buttonData: modelData
        editMode: root.editMode
        tabIndex: root.tabIndex
        inTray: root.inTray
        expandedSize: modelData.size > 1
        baseCellWidth: root.baseCellWidth
        baseCellHeight: root.baseCellHeight
        cellSpacing: root.spacing
        cellSize: modelData.size
    } }

    DelegateChoice { roleValue: "rogProfile"; AndroidRogProfileToggle {
        required property int index
        required property var modelData
        buttonIndex: root.startingIndex + index
        buttonData: modelData
        editMode: root.editMode
        tabIndex: root.tabIndex
        inTray: root.inTray
        expandedSize: modelData.size > 1
        baseCellWidth: root.baseCellWidth
        baseCellHeight: root.baseCellHeight
        cellSpacing: root.spacing
        cellSize: modelData.size
    } }

    DelegateChoice { roleValue: "rogGpu"; AndroidRogGpuToggle {
        required property int index
        required property var modelData
        buttonIndex: root.startingIndex + index
        buttonData: modelData
        editMode: root.editMode
        tabIndex: root.tabIndex
        inTray: root.inTray
        expandedSize: modelData.size > 1
        baseCellWidth: root.baseCellWidth
        baseCellHeight: root.baseCellHeight
        cellSpacing: root.spacing
        cellSize: modelData.size
    } }

    DelegateChoice { roleValue: "rogBattery"; AndroidRogBatteryToggle {
        required property int index
        required property var modelData
        buttonIndex: root.startingIndex + index
        buttonData: modelData
        editMode: root.editMode
        tabIndex: root.tabIndex
        inTray: root.inTray
        expandedSize: modelData.size > 1
        baseCellWidth: root.baseCellWidth
        baseCellHeight: root.baseCellHeight
        cellSpacing: root.spacing
        cellSize: modelData.size
    } }

    DelegateChoice { roleValue: "rogCharge"; AndroidRogChargeToggle {
        required property int index
        required property var modelData
        buttonIndex: root.startingIndex + index
        buttonData: modelData
        editMode: root.editMode
        tabIndex: root.tabIndex
        inTray: root.inTray
        expandedSize: modelData.size > 1
        baseCellWidth: root.baseCellWidth
        baseCellHeight: root.baseCellHeight
        cellSpacing: root.spacing
        cellSize: modelData.size
    } }

    DelegateChoice { roleValue: "rog"; AndroidRogToggle {
        required property int index
        required property var modelData
        buttonIndex: root.startingIndex + index
        buttonData: modelData
        editMode: root.editMode
        tabIndex: root.tabIndex
        inTray: root.inTray
        expandedSize: false       // container tiles never use inline expansion
        baseCellWidth: root.baseCellWidth
        baseCellHeight: root.baseCellHeight
        cellSpacing: root.spacing
        cellSize: 1               // forced 1×1 — drawer hosts the rich content
    } }

    DelegateChoice { roleValue: "phone"; AndroidPhoneToggle {
        required property int index
        required property var modelData
        buttonIndex: root.startingIndex + index
        buttonData: modelData
        editMode: root.editMode
        tabIndex: root.tabIndex
        inTray: root.inTray
        expandedSize: modelData.size > 1
        baseCellWidth: root.baseCellWidth
        baseCellHeight: root.baseCellHeight
        cellSpacing: root.spacing
        cellSize: modelData.size
        onRequestKdeConnectDialog: root.openKdeConnectDialog()
    } }

    DelegateChoice { roleValue: "screenSnip"; AndroidScreenSnipToggle {
        required property int index
        required property var modelData
        buttonIndex: root.startingIndex + index
        buttonData: modelData
        editMode: root.editMode
        tabIndex: root.tabIndex
        inTray: root.inTray
        expandedSize: modelData.size > 1
        baseCellWidth: root.baseCellWidth
        baseCellHeight: root.baseCellHeight
        cellSpacing: root.spacing
        cellSize: modelData.size
    } }
}
