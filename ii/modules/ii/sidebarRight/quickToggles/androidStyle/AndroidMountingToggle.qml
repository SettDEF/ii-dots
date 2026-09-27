// Drives quick toggle. Expanded view: scrollable device list. Each row
// can expand inline into a per-device panel showing usage bar, temp,
// open-in-files / copy-path / safely-eject.
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
    toggleModel: MountingToggle {}

    // Track which row is expanded inline.
    property string expandedPath: ""

    function _fmtBytes(b) {
        if (!b || b <= 0) return "—"
        const u = ["B","KB","MB","GB","TB","PB"]
        let i = 0, v = b
        while (v >= 1024 && i < u.length - 1) { v /= 1024; i++ }
        return v.toFixed(v < 10 && i > 0 ? 1 : 0) + " " + u[i]
    }
    function _fsIcon(fs) {
        const f = (fs || "").toLowerCase()
        if (f.startsWith("ntfs"))               return "developer_board"
        if (f === "exfat" || f === "vfat" || f.startsWith("fat")) return "sd_card"
        if (f.startsWith("ext"))                return "save"
        if (f === "btrfs" || f === "xfs" || f === "f2fs") return "lan"
        if (f === "iso9660" || f === "udf")     return "album"
        return "storage"
    }

    expandedDelegate: Component {
        ColumnLayout {
            spacing: 6

            RowLayout {
                Layout.fillWidth: true
                spacing: 8
                MaterialSymbol {
                    text: "usb"
                    iconSize: 22
                    color: Appearance.m3colors.m3onSurface
                }
                StyledText {
                    Layout.fillWidth: true
                    text: Mounting.devices.length === 0
                        ? Translation.tr("No drives detected")
                        : Translation.tr("%1 drive(s) • %2 mounted")
                            .arg(Mounting.devices.length).arg(Mounting.mountedCount)
                    font.pixelSize: Appearance.font.pixelSize.smallie
                    font.weight: Font.DemiBold
                    color: Appearance.m3colors.m3onSurface
                    elide: Text.ElideRight
                }
                // Header buttons
                Repeater {
                    model: [
                        { sym: "refresh", tip: "Refresh", fn: () => Mounting.refresh() },
                        { sym: "folder_open", tip: "Open ~", fn: () => Quickshell.execDetached(["xdg-open", "~"]) },
                    ]
                    delegate: Rectangle {
                        required property var modelData
                        Layout.preferredWidth: 24
                        Layout.preferredHeight: 24
                        radius: 12
                        color: hbHov.hovered ? Appearance.colors.colLayer2Hover : ColorUtils.transparentize(Appearance.colors.colLayer2Hover)
                        Behavior on color { ColorAnimation { duration: 120 } }
                        HoverHandler { id: hbHov }
                        TapHandler { onTapped: modelData.fn() }
                        MaterialSymbol {
                            anchors.centerIn: parent
                            text: modelData.sym
                            iconSize: 16
                            color: Appearance.m3colors.m3onSurface
                        }
                    }
                }
            }

            // Scrollable device list
            ScrollView {
                Layout.fillWidth: true
                Layout.fillHeight: true
                ScrollBar.horizontal.policy: ScrollBar.AlwaysOff
                clip: true

                ListView {
                    spacing: 4
                    model: Mounting.devices
                    delegate: Rectangle {
                        id: row
                        required property var modelData
                        readonly property bool isExpanded: root.expandedPath === modelData.path
                        readonly property var stats: Mounting.statsByPath[modelData.path] ?? null
                        width: ListView.view.width
                        radius: Appearance.rounding.normal
                        color: rowHov.hovered || isExpanded
                            ? Qt.alpha(Appearance.colors.colOnLayer0, 0.05)
                            : ColorUtils.transparentize(Qt.alpha(Appearance.colors.colOnLayer0, 0.05))
                        Behavior on color { ColorAnimation { duration: 120 } }
                        implicitHeight: rowCol.implicitHeight + 6
                        clip: true
                        Behavior on implicitHeight {
                            NumberAnimation { duration: 200; easing.type: Easing.OutCubic }
                        }

                        HoverHandler { id: rowHov }

                        ColumnLayout {
                            id: rowCol
                            anchors.fill: parent
                            anchors.margins: 3
                            spacing: 4

                            // ── Top row: icon, label, mount/unmount, info toggle
                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 6

                                MaterialSymbol {
                                    Layout.alignment: Qt.AlignVCenter
                                    text: row.modelData.removable
                                        ? "usb"
                                        : root._fsIcon(row.modelData.fsType)
                                    iconSize: 18
                                    color: row.modelData.mounted
                                        ? Appearance.colors.colPrimary
                                        : Appearance.colors.colSubtext
                                }

                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: -1
                                    StyledText {
                                        Layout.fillWidth: true
                                        text: row.modelData.label || row.modelData.name
                                        font.pixelSize: Appearance.font.pixelSize.smallie
                                        font.weight: Font.DemiBold
                                        color: Appearance.m3colors.m3onSurface
                                        elide: Text.ElideRight
                                    }
                                    StyledText {
                                        Layout.fillWidth: true
                                        text: (row.modelData.fsType || "—") +
                                              "  •  " + (row.modelData.size || "?") +
                                              (row.modelData.mounted
                                                ? "  •  " + (row.modelData.mountPoint || Translation.tr("mounted"))
                                                : "")
                                        font.pixelSize: Appearance.font.pixelSize.smallest
                                        color: Appearance.colors.colSubtext
                                        elide: Text.ElideRight
                                    }
                                }

                                // Info / collapse toggle
                                Rectangle {
                                    Layout.preferredWidth: 28
                                    Layout.preferredHeight: 28
                                    radius: 14
                                    color: infoHov.hovered
                                        ? Appearance.colors.colLayer2Hover
                                        : ColorUtils.transparentize(Appearance.colors.colLayer2Hover)
                                    Behavior on color { ColorAnimation { duration: 120 } }
                                    HoverHandler { id: infoHov }
                                    TapHandler {
                                        onTapped: {
                                            if (row.isExpanded) {
                                                root.expandedPath = ""
                                                Mounting.setStatsTarget("", "")
                                            } else {
                                                root.expandedPath = row.modelData.path
                                                Mounting.setStatsTarget(row.modelData.path, row.modelData.mountPoint)
                                            }
                                        }
                                    }
                                    MaterialSymbol {
                                        anchors.centerIn: parent
                                        text: row.isExpanded ? "expand_less" : "info"
                                        iconSize: 16
                                        color: Appearance.m3colors.m3onSurface
                                    }
                                }

                                // Primary action (mount / unmount)
                                Rectangle {
                                    Layout.preferredWidth: 28
                                    Layout.preferredHeight: 28
                                    radius: 14
                                    color: row.modelData.mounted
                                        ? Appearance.colors.colSecondaryContainer
                                        : (mtHov.hovered ? Appearance.colors.colLayer2Hover : ColorUtils.transparentize(Appearance.colors.colLayer2Hover))
                                    Behavior on color { ColorAnimation { duration: 120 } }
                                    HoverHandler { id: mtHov }
                                    TapHandler {
                                        onTapped: row.modelData.mounted
                                            ? Mounting.unmountDevice(row.modelData.path)
                                            : Mounting.mountDevice(row.modelData.path)
                                    }
                                    MaterialSymbol {
                                        anchors.centerIn: parent
                                        text: row.modelData.mounted ? "eject" : "play_arrow"
                                        iconSize: 16
                                        color: row.modelData.mounted
                                            ? Appearance.m3colors.m3onSecondaryContainer
                                            : Appearance.m3colors.m3onSurface
                                    }
                                }
                            }

                            // ── Inline panel: usage bar, temp, more actions
                            Item {
                                Layout.fillWidth: true
                                Layout.preferredHeight: row.isExpanded ? panel.implicitHeight + 4 : 0
                                visible: Layout.preferredHeight > 0
                                clip: true
                                Behavior on Layout.preferredHeight {
                                    NumberAnimation { duration: 180; easing.type: Easing.OutCubic }
                                }

                                ColumnLayout {
                                    id: panel
                                    anchors.left: parent.left
                                    anchors.right: parent.right
                                    anchors.top: parent.top
                                    spacing: 4
                                    opacity: row.isExpanded ? 1 : 0
                                    Behavior on opacity { NumberAnimation { duration: 140 } }

                                    // Usage bar (only meaningful when mounted + we have stats)
                                    RowLayout {
                                        Layout.fillWidth: true
                                        spacing: 6
                                        visible: row.modelData.mounted

                                        Rectangle {
                                            Layout.fillWidth: true
                                            Layout.preferredHeight: 6
                                            radius: 3
                                            color: Qt.alpha(Appearance.colors.colOnLayer0, 0.10)
                                            Rectangle {
                                                anchors.left: parent.left
                                                anchors.top: parent.top
                                                anchors.bottom: parent.bottom
                                                width: parent.width * Math.min(1, (row.stats?.percent ?? 0) / 100)
                                                radius: parent.radius
                                                color: (row.stats?.percent ?? 0) > 90
                                                    ? Appearance.m3colors.m3error
                                                    : Appearance.colors.colPrimary
                                                Behavior on width { NumberAnimation { duration: 240; easing.type: Easing.OutCubic } }
                                                Behavior on color { ColorAnimation { duration: 240 } }
                                            }
                                        }
                                        StyledText {
                                            text: row.stats
                                                ? root._fmtBytes(row.stats.used) + " / " + root._fmtBytes(row.stats.total)
                                                : "…"
                                            font.pixelSize: Appearance.font.pixelSize.smallest
                                            color: Appearance.colors.colSubtext
                                        }
                                    }

                                    // Stats line: temp, free, percent
                                    RowLayout {
                                        Layout.fillWidth: true
                                        spacing: 10

                                        // Temperature chip
                                        RowLayout {
                                            visible: !!row.stats && isFinite(row.stats.temp)
                                            spacing: 3
                                            MaterialSymbol {
                                                text: "thermostat"
                                                iconSize: 14
                                                color: (row.stats?.temp ?? 0) > 70
                                                    ? Appearance.m3colors.m3error
                                                    : Appearance.colors.colSubtext
                                            }
                                            StyledText {
                                                text: row.stats ? Math.round(row.stats.temp) + " °C" : ""
                                                font.pixelSize: Appearance.font.pixelSize.smallest
                                                color: Appearance.colors.colSubtext
                                            }
                                        }
                                        // Free
                                        RowLayout {
                                            visible: !!row.stats && row.modelData.mounted
                                            spacing: 3
                                            MaterialSymbol {
                                                text: "data_saver_off"
                                                iconSize: 14
                                                color: Appearance.colors.colSubtext
                                            }
                                            StyledText {
                                                text: Translation.tr("%1 free").arg(root._fmtBytes(row.stats?.free))
                                                font.pixelSize: Appearance.font.pixelSize.smallest
                                                color: Appearance.colors.colSubtext
                                            }
                                        }
                                        Item { Layout.fillWidth: true }
                                    }

                                    // Action chips
                                    RowLayout {
                                        Layout.fillWidth: true
                                        spacing: 4

                                        component Chip: Rectangle {
                                            property string sym: ""
                                            property string label: ""
                                            property var onTap: () => {}
                                            property bool danger: false
                                            Layout.alignment: Qt.AlignVCenter
                                            implicitHeight: 24
                                            implicitWidth: chipRow.implicitWidth + 12
                                            radius: height / 2
                                            color: chipHov.hovered
                                                ? (danger
                                                    ? Qt.alpha(Appearance.m3colors.m3error, 0.15)
                                                    : Appearance.colors.colLayer2Hover)
                                                : Qt.alpha(Appearance.colors.colOnLayer0, 0.06)
                                            Behavior on color { ColorAnimation { duration: 120 } }
                                            HoverHandler { id: chipHov }
                                            TapHandler { onTapped: parent.onTap() }
                                            RowLayout {
                                                id: chipRow
                                                anchors.centerIn: parent
                                                spacing: 4
                                                MaterialSymbol {
                                                    text: parent.parent.sym
                                                    iconSize: 13
                                                    color: parent.parent.danger
                                                        ? Appearance.m3colors.m3error
                                                        : Appearance.m3colors.m3onSurface
                                                }
                                                StyledText {
                                                    text: parent.parent.label
                                                    font.pixelSize: Appearance.font.pixelSize.smallest
                                                    color: parent.parent.danger
                                                        ? Appearance.m3colors.m3error
                                                        : Appearance.m3colors.m3onSurface
                                                }
                                            }
                                        }

                                        Chip {
                                            visible: row.modelData.mounted
                                            sym: "folder_open"; label: Translation.tr("Open")
                                            onTap: () => Mounting.openInFileManager(row.modelData.mountPoint)
                                        }
                                        Chip {
                                            sym: "content_copy"
                                            label: row.modelData.mounted ? Translation.tr("Copy path") : Translation.tr("Copy device")
                                            onTap: () => Mounting.copyPath(
                                                row.modelData.mounted ? row.modelData.mountPoint : row.modelData.path
                                            )
                                        }
                                        Chip {
                                            visible: row.modelData.removable
                                            sym: "power_settings_new"
                                            label: Translation.tr("Power off")
                                            danger: true
                                            onTap: () => Mounting.powerOff(row.modelData.path)
                                        }
                                        Item { Layout.fillWidth: true }
                                    }
                                }
                            }
                        }
                    }

                    StyledText {
                        anchors.centerIn: parent
                        visible: Mounting.devices.length === 0
                        text: Translation.tr("Plug in a drive")
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        color: Appearance.colors.colSubtext
                        opacity: 0.6
                    }
                }
            }
        }
    }
}
