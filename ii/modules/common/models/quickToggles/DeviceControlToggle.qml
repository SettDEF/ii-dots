import QtQuick
import "../../../ii/deviceControl" as DeviceModule // Import the module

QuickToggleModel {
    id: model
    name: "Device Control"
    property string type: "deviceControl"
    property int size: 1

    // Access the singleton via the module namespace
    icon: DeviceModule.DeviceControl.currentProfile === "Performance" ? "speedometer" : 
          DeviceModule.DeviceControl.currentProfile === "Quiet" ? "weather-moon" : "sunny"
    
    statusText: DeviceModule.DeviceControl.currentProfile
    
    mainAction: function() {
        DeviceModule.DeviceControl.cycleProfile();
    }
    
    hasMenu: true
}
