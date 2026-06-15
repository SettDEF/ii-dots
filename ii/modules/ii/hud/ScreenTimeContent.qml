import qs
import QtQuick

/**
 * HUD "Screen Time" tab content. Switches between the Today / Week /
 * Apps sub-views (GlobalStates.hudScreenTab) and a per-app detail
 * drill-down (`detailApp`, set by tapping an app row in any view).
 */
Item {
    id: root
    implicitHeight: viewLoader.item ? viewLoader.item.implicitHeight : 560

    readonly property int subTab: GlobalStates.hudScreenTab   // 0 Today · 1 Week · 2 Apps
    property string detailApp: ""

    onSubTabChanged: detailApp = ""
    function openApp(id) { root.detailApp = id }
    function closeDetail() { root.detailApp = "" }

    Loader {
        id: viewLoader
        anchors { left: parent.left; right: parent.right; top: parent.top }
        sourceComponent: root.detailApp !== "" ? detailC
            : root.subTab === 1 ? weekC
            : root.subTab === 2 ? appsC
            : todayC
    }

    Component { id: todayC; StTodayView { onAppSelected: id => root.openApp(id) } }
    Component { id: weekC;  StWeekView  { onAppSelected: id => root.openApp(id) } }
    Component { id: appsC;  StAppsView  { onAppSelected: id => root.openApp(id) } }
    Component {
        id: detailC
        StAppDetail { appId: root.detailApp; onClosed: root.closeDetail() }
    }
}
