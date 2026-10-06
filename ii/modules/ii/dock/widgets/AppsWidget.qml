import qs.services
import qs.modules.common
import qs.modules.ii.dock
import QtQuick

// The running/pinned apps. Layout is the host's job now — see DockWidget.
DockApps {
    buttonPadding: Config.options?.dock.buttonPadding ?? 5
    onRequestDockShowChanged: DockWidgets.appsRequestShow = requestDockShow
    Component.onCompleted: DockWidgets.appsRequestShow = requestDockShow
    Component.onDestruction: DockWidgets.appsRequestShow = false
}
