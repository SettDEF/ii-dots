// A dock widget's own floating window: a real toplevel the compositor
// manages, so it can be moved, stacked and alt-tabbed.
//
// Still toggleable — clicking the same tile again clears DockWidgetPanel and
// the Loader that owns this destroys it. Floating is NOT automatic: a
// toplevel obeys the tiling layout unless a window rule says otherwise, which
// is why custom/rules.conf carries a matching float rule.
pragma ComponentBehavior: Bound
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts
import Quickshell

FloatingWindow {
    id: win

    readonly property string widgetId: DockWidgetPanel.widgetId
    readonly property var entry: DockWidgets.entry(win.widgetId)

    // The rule matches on this title, so it must stay in this shape.
    title: win.entry ? Translation.tr("%1 — Dock").arg(win.entry.name) : Translation.tr("Dock widget")
    minimumSize: Qt.size(Appearance.sizes.dockWidgetWindow.minWidth, Appearance.sizes.dockWidgetWindow.minHeight)
    implicitWidth: win.entry?.w ?? Appearance.sizes.dockWidgetWindow.widthNormal
    // From the catalog, not children: behind a Loader they measure 0 at map time.
    implicitHeight: win.entry?.h ?? Appearance.sizes.dockWidgetWindow.heightNormal
    color: Appearance.colors.colLayer0Base

    visible: true
    onVisibleChanged: if (!visible) DockWidgetPanel.close()

    Rectangle {
        anchors.fill: parent
        color: Appearance.colors.colLayer0Base
        focus: true
        Keys.onEscapePressed: event => { DockWidgetPanel.close(); event.accepted = true }

        ColumnLayout {
            id: shell
            anchors { fill: parent; margins: 14 }
            spacing: 8

            RowLayout {
                id: header
                Layout.fillWidth: true
                spacing: 8
                MaterialSymbol {
                    text: win.entry?.icon ?? ""
                    iconSize: Appearance.font.pixelSize.huge
                    color: Appearance.colors.colPrimary
                }
                StyledText {
                    Layout.fillWidth: true
                    text: DockWidgetPanel.showSettings
                        ? Translation.tr("%1 settings").arg(win.entry?.name ?? "")
                        : (win.entry?.name ?? "")
                    font.pixelSize: Appearance.font.pixelSize.normal
                    font.weight: Font.Medium
                    color: Appearance.colors.colOnLayer0
                    elide: Text.ElideRight
                }
                RippleButton {
                    implicitWidth: 30
                    implicitHeight: 30
                    buttonRadius: Appearance.rounding.full
                    visible: (win.entry?.settings ?? []).length > 0
                    toggled: DockWidgetPanel.showSettings
                    onClicked: DockWidgetPanel.showSettings = !DockWidgetPanel.showSettings
                    contentItem: MaterialSymbol {
                        anchors.centerIn: parent
                        text: DockWidgetPanel.showSettings ? "arrow_back" : "settings"
                        iconSize: Appearance.font.pixelSize.large
                        color: Appearance.colors.colOnLayer0
                    }
                }
                // Hyprland floats these without a titlebar, so without this
                // there is no visible way to dismiss the window.
                RippleButton {
                    implicitWidth: 30
                    implicitHeight: 30
                    buttonRadius: Appearance.rounding.full
                    onClicked: DockWidgetPanel.close()
                    contentItem: MaterialSymbol {
                        anchors.centerIn: parent
                        text: "close"
                        iconSize: Appearance.font.pixelSize.large
                        color: Appearance.colors.colOnLayer0
                    }
                }
            }

            Rectangle {
                Layout.fillWidth: true
                implicitHeight: 1
                color: Appearance.colors.colOutlineVariant
            }

            StyledFlickable {
                Layout.fillWidth: true
                Layout.preferredHeight: body.implicitHeight
                Layout.fillHeight: true
                contentHeight: body.implicitHeight
                clip: true

                ColumnLayout {
                    id: body
                    width: parent.width
                    spacing: 0

                    Loader {
                        Layout.fillWidth: true
                        active: !DockWidgetPanel.showSettings && win.widgetId.length > 0
                        source: active
                            ? Qt.resolvedUrl(`widgets/${win.widgetId.charAt(0).toUpperCase()}${win.widgetId.slice(1)}Panel.qml`)
                            : ""
                    }

                    Repeater {
                        model: DockWidgetPanel.showSettings ? (win.entry?.settings ?? []) : []
                        delegate: Loader {
                            required property var modelData
                            Layout.fillWidth: true
                            sourceComponent: modelData.type === "int" ? intSetting : boolSetting
                        }
                    }
                    Component {
                        id: boolSetting
                        ConfigSwitch {
                            text: parent.modelData.label
                            checked: DockWidgets.get(win.widgetId, parent.modelData.key) === true
                            onCheckedChanged: {
                                if (checked !== (DockWidgets.get(win.widgetId, parent.modelData.key) === true))
                                    DockWidgets.set(win.widgetId, parent.modelData.key, checked);
                            }
                        }
                    }
                    Component {
                        id: intSetting
                        ConfigSpinBox {
                            text: parent.modelData.label
                            value: DockWidgets.get(win.widgetId, parent.modelData.key) ?? 0
                            from: parent.modelData.min ?? 0
                            to: parent.modelData.max ?? 100
                            stepSize: 1
                            onValueChanged: DockWidgets.set(win.widgetId, parent.modelData.key, value)
                        }
                    }
                }
            }
        }
    }
}
