import qs.services
import qs.modules.common
import qs.modules.ii.dock
import QtQuick

// The now-playing card. Collapses to zero width with no track, which is why
// the host takes implicitWidth from the item rather than reserving space.
DockMedia {
    // Width, not visibility: the host sizes the row from implicitWidth.
    implicitWidth: (Config.options?.dock.showMedia ?? true) && hasTrack ? cardWidth : 0
    buttonPadding: Config.options?.dock.buttonPadding ?? 5
    onRequestDockShowChanged: DockWidgets.mediaRequestShow = requestDockShow
    Component.onCompleted: DockWidgets.mediaRequestShow = requestDockShow
    Component.onDestruction: DockWidgets.mediaRequestShow = false
}
