import qs
import qs.modules.common
import qs.modules.common.widgets
import qs.services
import QtQuick
import QtQuick.Layouts
import Quickshell

DialogListItem {
    id: root
    required property var monitor   // entry from MonitorManager.friendly

    property bool expanded: false
    pointingHandCursor: !expanded

    onClicked: expanded = !expanded
    altAction: () => expanded = !expanded

    readonly property bool isInternal: monitor?.kind === "internal"
    readonly property bool isOn: !(monitor?.disabled ?? true)
    readonly property bool isMirroring: (monitor?.mirrorOf ?? "").length > 0

    contentItem: ColumnLayout {
        anchors {
            fill: parent
            topMargin: root.verticalPadding
            bottomMargin: root.verticalPadding
            leftMargin: root.horizontalPadding
            rightMargin: root.horizontalPadding
        }
        spacing: 0

        RowLayout {
            Layout.fillWidth: true
            spacing: 10

            MaterialSymbol {
                iconSize: Appearance.font.pixelSize.larger
                text: root.isInternal ? "laptop" : "monitor"
                color: Appearance.colors.colOnSurfaceVariant
            }

            ColumnLayout {
                spacing: 2
                Layout.fillWidth: true
                StyledText {
                    Layout.fillWidth: true
                    color: Appearance.colors.colOnSurfaceVariant
                    elide: Text.ElideRight
                    text: root.monitor?.description?.length > 0
                        ? root.monitor.description
                        : (root.monitor?.name ?? "—")
                    textFormat: Text.PlainText
                }
                StyledText {
                    Layout.fillWidth: true
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: Appearance.colors.colSubtext
                    elide: Text.ElideRight
                    text: {
                        const m = root.monitor
                        if (!m) return ""
                        const kind = root.isInternal
                            ? Translation.tr("Internal")
                            : Translation.tr("External")
                        if (m.disabled)
                            return `${kind} • ${m.name} • ${Translation.tr("Off")}`
                        if (root.isMirroring)
                            return `${kind} • ${m.name} • ${Translation.tr("Mirroring %1").arg(m.mirrorOf)}`
                        const res = (m.width && m.height)
                            ? `${m.width}×${m.height}@${Math.round(m.refreshRate)}Hz`
                            : ""
                        const scale = m.scale && m.scale !== 1
                            ? ` · ${(+m.scale).toFixed(2)}×`
                            : ""
                        return res
                            ? `${kind} • ${m.name} • ${res}${scale}`
                            : `${kind} • ${m.name}`
                    }
                }
            }

            // Active indicator
            MaterialSymbol {
                visible: root.isOn && !root.isMirroring
                text: root.monitor?.focused ? "star" : "check"
                iconSize: Appearance.font.pixelSize.larger
                color: Appearance.colors.colOnSurfaceVariant
            }

            MaterialSymbol {
                text: "keyboard_arrow_down"
                iconSize: Appearance.font.pixelSize.larger
                color: Appearance.colors.colOnLayer3
                rotation: root.expanded ? 180 : 0
                Behavior on rotation {
                    animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                }
            }
        }

        // Action row: Enable/Disable, mirror controls (external only)
        RowLayout {
            visible: root.expanded
            Layout.topMargin: 8
            Layout.fillWidth: true
            spacing: 6

            Item { Layout.fillWidth: true }

            PrimaryActionButton {
                buttonText: root.isOn ? Translation.tr("Disable") : Translation.tr("Enable")
                visible: !root.isInternal || MonitorManager.externalMonitors.length > 0
                colBackground: root.isOn ? Appearance.colors.colError : Appearance.colors.colPrimary
                colBackgroundHover: root.isOn ? Appearance.colors.colErrorHover : Appearance.colors.colPrimaryHover
                colRipple: root.isOn ? Appearance.colors.colErrorActive : Appearance.colors.colPrimaryActive
                colText: root.isOn ? Appearance.colors.colOnError : Appearance.colors.colOnPrimary
                onClicked: MonitorManager.toggleEnabled(root.monitor)
            }

            // Mirror controls — external only
            PrimaryActionButton {
                visible: !root.isInternal
                      && MonitorManager.internalMonitors.length > 0
                      && !root.isMirroring
                      && root.isOn
                buttonText: Translation.tr("Mirror internal")
                onClicked: {
                    const target = MonitorManager.internalMonitors[0]?.name
                    if (target) MonitorManager.setMirror(root.monitor.name, target)
                }
            }
            PrimaryActionButton {
                visible: !root.isInternal && root.isMirroring
                buttonText: Translation.tr("Stop mirroring")
                onClicked: MonitorManager.setMirror(root.monitor.name, "")
            }
        }
        Item { Layout.fillHeight: true }
    }
}
