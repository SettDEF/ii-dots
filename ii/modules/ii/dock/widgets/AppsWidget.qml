import qs.services
import qs.modules.common
import qs.modules.ii.dock
import QtQuick
import QtQuick.Layouts

// The running/pinned apps, as a widget. It was a hardcoded sibling of the
// widget repeater because DockWidget only knew how to draw a 35px square;
// kind "inline" is what lets it size itself.
DockApps {
    buttonPadding: Config.options?.dock.buttonPadding ?? 5
    onRequestDockShowChanged: DockWidgets.appsRequestShow = requestDockShow
    Component.onCompleted: DockWidgets.appsRequestShow = requestDockShow
    Component.onDestruction: DockWidgets.appsRequestShow = false
}
