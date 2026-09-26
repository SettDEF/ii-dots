pragma ComponentBehavior: Bound
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Services.Pipewire

// Per-app audio sources: live meter + volume + "audio follows focus" mode.
ColumnLayout {
    id: root
    // Every open app, not just the ones currently streaming — a silent
    // Telegram still gets a row and a volume.
    readonly property list<var> appNodes: AppVolumes.rows
    readonly property int rowHeight: 54
    spacing: 2

    // Height the popup can use to size itself: rows (capped) + padding.
    // No header — the "Sources" tab in CornerPopup already names this view.
    // The empty state needs room for PagePlaceholder's 56px icon plus its
    // title, otherwise the popup crops it into a blob.
    readonly property int contentHeight: root.appNodes.length === 0
        ? 116
        : 10 + Math.min(root.appNodes.length, 5) * (rowHeight + 2)

    StyledListView {
        id: list
        Layout.fillWidth: true
        Layout.fillHeight: true
        Layout.leftMargin: 6
        Layout.rightMargin: 6
        Layout.bottomMargin: 6
        clip: true
        spacing: 2
        model: ScriptModel { values: root.appNodes }
        delegate: AppAudioRow {
            anchors.left: parent?.left
            anchors.right: parent?.right
            required property var modelData
            row: modelData
        }

        PagePlaceholder {
            anchors.centerIn: parent
            icon: "music_off"
            title: Translation.tr("Nothing playing")
            shown: root.appNodes.length === 0
        }
    }
}
