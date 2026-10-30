pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import qs
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import qs.modules.waffle.looks

BodyRectangle {
    id: root

    ColumnLayout {
        anchors {
            fill: parent
            leftMargin: 32
            rightMargin: 32
            topMargin: 25
            bottomMargin: 30
        }
        spacing: 26

        PinnedApps {
            Layout.fillWidth: true
        }

        AllApps {
            Layout.fillWidth: true
            Layout.fillHeight: true
        }
    }

    component PinnedApps: PageSection {
        title: Translation.tr("Pinned")

        BigAppGrid {
            Layout.fillWidth: true
            columns: 8
            desktopEntries: Config.options.launcher.pinnedApps.map(appId => DesktopEntries.byId(appId))
        }
    }

    component AllApps: PageSection {
        title: Translation.tr("All")
        // TODO: Do we wanna also implement list view and grid view?
        //       (instead of only category view)
        // the room under Pinned, scrolling: at a fixed 300 its second row was drawn over the footer
        Flickable {
            id: allFlick
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            contentHeight: allGrid.implicitHeight
            boundsBehavior: Flickable.StopAtBounds
            ScrollBar.vertical: ScrollBar {}
            AllAppsGrid {
                id: allGrid
                x: 32
                width: allFlick.width - 64
            }
        }
    }

    component PageSection: ColumnLayout {
        id: pageSection
        required property string title
        default property alias data: pageSectionContentArea.data

        spacing: 16

        WText {
            Layout.leftMargin: 32
            text: pageSection.title
            font.pixelSize: Looks.font.pixelSize.large
            font.weight: Looks.font.weight.stronger
        }

        ColumnLayout {
            id: pageSectionContentArea
            Layout.fillWidth: true
            Layout.fillHeight: true
        }
    }
}
