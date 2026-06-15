// modules/ii/deviceControl/Tile.qml
import QtQuick
import QtQuick.Controls
import "../sidebarRight/quickToggles/androidStyle" as BaseStyles

BaseStyles.AndroidQuickToggleButton {
    id: control

    required property var buttonData
    required property int buttonIndex
    property bool editMode: false

    text: buttonData.name
    // We can access DeviceControl directly because it's in our module
    icon.name: DeviceControl.currentProfile === "Performance" ? "speedometer" : 
               DeviceControl.currentProfile === "Quiet" ? "weather-moon" : "sunny"
    
    statusText: DeviceControl.currentProfile

    property var popupLoader: Loader {
        active: false
        sourceComponent: Panel { parent: control }
        onLoaded: item.open()
    }

    onClicked: buttonData.mainAction()
    onLongPressed: popupLoader.active = true
}
