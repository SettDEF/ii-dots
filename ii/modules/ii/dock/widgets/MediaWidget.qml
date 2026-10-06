import qs.services
import qs.modules.common
import qs.modules.ii.dock
import QtQuick
import QtQuick.Layouts

// The now-playing card, as a widget. Same reason as AppsWidget: it is wider
// than a tile and collapses to nothing when there is no track, which the
// fixed-square host could not express.
DockMedia {
    visible: (Config.options?.dock.showMedia ?? true) && hasTrack
    Layout.fillHeight: true
    Layout.topMargin: 12
    Layout.bottomMargin: 8
    buttonPadding: Config.options?.dock.buttonPadding ?? 5
    onRequestDockShowChanged: DockWidgets.mediaRequestShow = requestDockShow
    Component.onCompleted: DockWidgets.mediaRequestShow = requestDockShow
    Component.onDestruction: DockWidgets.mediaRequestShow = false
}
