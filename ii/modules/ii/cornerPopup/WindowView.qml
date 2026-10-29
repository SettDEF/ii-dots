import qs
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts

// The corner popup's Window tab: the title bars' (ii-decor) switches at hand, live. The rest of
// their settings (sizes, colours, button styles) are in Theme › Glass.
Item {
    id: root
    readonly property var decor: Config.options.appearance.glass.decor
    readonly property int contentHeight: col.implicitHeight + 16

    ColumnLayout {
        id: col
        anchors { left: parent.left; right: parent.right; top: parent.top; margins: 10 }
        spacing: 2

        ConfigSwitch {
            Layout.fillWidth: true
            buttonIcon: "web_asset"
            text: qsTr("Title bars")
            checked: root.decor.enable
            onCheckedChanged: root.decor.enable = checked
        }
        ConfigSwitch {
            Layout.fillWidth: true
            enabled: root.decor.enable
            buttonIcon: "title"
            text: qsTr("Window title")
            checked: root.decor.title
            onCheckedChanged: root.decor.title = checked
        }
        ConfigSwitch {
            Layout.fillWidth: true
            enabled: root.decor.enable
            buttonIcon: "apps"
            text: qsTr("App icon")
            checked: root.decor.icon
            onCheckedChanged: root.decor.icon = checked
        }
        ConfigSwitch {
            Layout.fillWidth: true
            enabled: root.decor.enable
            buttonIcon: "blur_on"
            text: qsTr("Blur behind the bar")
            checked: root.decor.blur
            onCheckedChanged: root.decor.blur = checked
        }
        ConfigSwitch {
            Layout.fillWidth: true
            enabled: root.decor.enable
            buttonIcon: "horizontal_rule"
            text: qsTr("Line under the bar")
            checked: root.decor.separator
            onCheckedChanged: root.decor.separator = checked
        }
        ConfigSwitch {
            Layout.fillWidth: true
            buttonIcon: "dashboard"
            text: qsTr("Menus use the title bars' buttons")
            checked: root.decor.panels
            onCheckedChanged: root.decor.panels = checked
        }
        RippleButtonWithIcon {
            Layout.fillWidth: true
            Layout.topMargin: 4
            buttonRadius: Appearance.rounding.small
            materialIcon: "palette"
            mainText: qsTr("More in Theme › Glass")
            onClicked: {
                GlobalStates.wallTuneTab = "glass";
                GlobalStates.wallTuneOpen = true;
                GlobalStates.cornerPopupOpen = false;
            }
        }
    }
}
