// Offload widget — viewer for ~/.scripts/offload. Shows mount state +
// per-folder badges (local / linked / broken). No move buttons: the
// destructive ops stay on the CLI behind the script's dry-run.
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.models.quickToggles
import qs.modules.common.widgets
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

AndroidQuickToggleButton {
    id: root
    toggleModel: OffloadToggle {}

    function _stateColor(s) {
        switch (s) {
            case "linked":         return Appearance.colors.colPrimary
            case "local":          return Appearance.colors.colSubtext
            case "linked-broken":  return Appearance.m3colors.m3error
            case "foreign-link":   return Appearance.m3colors.m3error
            case "missing":        return Appearance.m3colors.m3outline
            default:               return Appearance.colors.colSubtext
        }
    }
    function _stateIcon(s) {
        switch (s) {
            case "linked":         return "link"
            case "local":          return "home"
            case "linked-broken":  return "link_off"
            case "foreign-link":   return "warning"
            case "missing":        return "help"
            default:               return "help"
        }
    }

    expandedDelegate: Component {
        ColumnLayout {
            spacing: 6

            // Header
            RowLayout {
                Layout.fillWidth: true
                spacing: 8
                MaterialSymbol {
                    text: "drive_file_move"
                    iconSize: 22
                    color: Appearance.m3colors.m3onSurface
                }
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: -2
                    StyledText {
                        Layout.fillWidth: true
                        text: Translation.tr("Home → /mnt/nuke9100")
                        font.pixelSize: Appearance.font.pixelSize.smallie
                        font.weight: Font.DemiBold
                        color: Appearance.m3colors.m3onSurface
                        elide: Text.ElideRight
                    }
                    StyledText {
                        Layout.fillWidth: true
                        text: Offload.mounted
                            ? Translation.tr("mounted • %1 free").arg(Offload.mountFree)
                            : Translation.tr("drive not mounted")
                        font.pixelSize: Appearance.font.pixelSize.smallest
                        color: Offload.mounted
                            ? Appearance.colors.colSubtext
                            : Appearance.m3colors.m3error
                        elide: Text.ElideRight
                    }
                }
                // Refresh
                Rectangle {
                    Layout.preferredWidth: 24; Layout.preferredHeight: 24
                    radius: 12
                    color: rfHov.hovered ? Appearance.colors.colLayer2Hover : ColorUtils.transparentize(Appearance.colors.colLayer2Hover)
                    Behavior on color { ColorAnimation { duration: 120 } }
                    HoverHandler { id: rfHov }
                    TapHandler { onTapped: Offload.refresh() }
                    MaterialSymbol {
                        anchors.centerIn: parent
                        text: "refresh"; iconSize: 16
                        color: Appearance.m3colors.m3onSurface
                    }
                }
                // Mount (only when unmounted)
                Rectangle {
                    visible: !Offload.mounted
                    Layout.preferredWidth: 24; Layout.preferredHeight: 24
                    radius: 12
                    color: mtHov.hovered ? Appearance.colors.colLayer2Hover : ColorUtils.transparentize(Appearance.colors.colLayer2Hover)
                    Behavior on color { ColorAnimation { duration: 120 } }
                    HoverHandler { id: mtHov }
                    TapHandler { onTapped: Offload.mount() }
                    MaterialSymbol {
                        anchors.centerIn: parent
                        text: "play_arrow"; iconSize: 16
                        color: Appearance.colors.colPrimary
                    }
                }
            }

            // Folder rows
            ScrollView {
                Layout.fillWidth: true
                Layout.fillHeight: true
                ScrollBar.horizontal.policy: ScrollBar.AlwaysOff
                clip: true

                ListView {
                    spacing: 4
                    model: Offload.folders
                    delegate: Rectangle {
                        id: row
                        required property var modelData
                        width: ListView.view.width
                        radius: Appearance.rounding.normal
                        color: rowHov.hovered
                            ? Qt.alpha(Appearance.colors.colOnLayer0, 0.05)
                            : ColorUtils.transparentize(Qt.alpha(Appearance.colors.colOnLayer0, 0.05))
                        Behavior on color { ColorAnimation { duration: 120 } }
                        implicitHeight: rowCol.implicitHeight + 6

                        HoverHandler { id: rowHov }
                        TapHandler { onTapped: Offload.openFolder(row.modelData.folder) }

                        RowLayout {
                            id: rowCol
                            anchors.fill: parent
                            anchors.margins: 6
                            spacing: 8

                            MaterialSymbol {
                                Layout.alignment: Qt.AlignVCenter
                                text: root._stateIcon(row.modelData.state)
                                iconSize: 18
                                color: root._stateColor(row.modelData.state)
                            }

                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: -2
                                StyledText {
                                    Layout.fillWidth: true
                                    text: row.modelData.folder
                                    font.pixelSize: Appearance.font.pixelSize.smallie
                                    font.weight: Font.DemiBold
                                    color: Appearance.m3colors.m3onSurface
                                    elide: Text.ElideRight
                                }
                                StyledText {
                                    Layout.fillWidth: true
                                    text: row.modelData.size + "  •  " + row.modelData.state
                                    font.pixelSize: Appearance.font.pixelSize.smallest
                                    color: Appearance.colors.colSubtext
                                    elide: Text.ElideRight
                                }
                            }

                            // Copy CLI command (link or unlink, depending on state)
                            Rectangle {
                                visible: row.modelData.state === "local" || row.modelData.state === "linked"
                                Layout.preferredWidth: 28; Layout.preferredHeight: 28
                                radius: 14
                                color: cpHov.hovered ? Appearance.colors.colLayer2Hover : ColorUtils.transparentize(Appearance.colors.colLayer2Hover)
                                Behavior on color { ColorAnimation { duration: 120 } }
                                HoverHandler { id: cpHov }
                                TapHandler {
                                    onTapped: Offload.copyDryRun(
                                        row.modelData.folder,
                                        row.modelData.state === "linked" ? "unlink" : "link"
                                    )
                                }
                                MaterialSymbol {
                                    anchors.centerIn: parent
                                    text: "content_copy"; iconSize: 14
                                    color: Appearance.m3colors.m3onSurface
                                }
                            }
                        }
                    }

                    StyledText {
                        anchors.centerIn: parent
                        visible: Offload.folders.length === 0
                        text: Offload.loading
                            ? Translation.tr("Loading…")
                            : Translation.tr("No folders configured")
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        color: Appearance.colors.colSubtext
                        opacity: 0.6
                    }
                }
            }

            StyledText {
                Layout.fillWidth: true
                Layout.topMargin: 2
                text: Translation.tr("Tap row → open. Copy → CLI command (paste in terminal).")
                font.pixelSize: Appearance.font.pixelSize.smallest
                color: Appearance.colors.colSubtext
                wrapMode: Text.WordWrap
                opacity: 0.7
            }
        }
    }
}
