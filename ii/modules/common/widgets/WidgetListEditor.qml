// The widget list any surface with pluggable widgets needs: one row per catalog
// entry, a switch to turn it on, reorder arrows once it is, and that widget's
// own settings rendered underneath from its schema.
//
// Knows no widget. It is handed a registry -- DockWidgets, BarWidgets, or
// whatever comes next -- and everything it draws comes from that registry's
// catalog, so a new widget is a catalog entry and nothing here changes.
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts

ColumnLayout {
    id: root

    /// The registry singleton: needs catalog, isEnabled, toggle, move, get, set.
    required property var registry
    /// Heading above the list. Empty hides it.
    property string title: ""
    /// Reorder arrows point along the surface the widgets sit on.
    property bool horizontalOrder: true

    spacing: 0

    StyledText {
        visible: root.title.length > 0
        Layout.fillWidth: true
        Layout.topMargin: 8
        Layout.leftMargin: 4
        text: root.title
        font.pixelSize: Appearance.font.pixelSize.smallest
        font.weight: Font.Medium
        color: Appearance.colors.colSubtext
    }

    Repeater {
        model: root.registry?.catalog ?? []
        delegate: Rectangle {
            id: widgetBlock
            required property var modelData
            readonly property bool on: root.registry.isEnabled(widgetBlock.modelData.id)
            readonly property var schema: widgetBlock.modelData.settings ?? []

            Layout.fillWidth: true
            Layout.topMargin: 4
            implicitHeight: widgetCol.implicitHeight + 12
            radius: Appearance.rounding.normal
            // An enabled widget carries its settings, so it gets a surface; a
            // disabled one is just a row in a list.
            color: widgetBlock.on ? Appearance.colors.colLayer1
                                  : ColorUtils.transparentize(Appearance.colors.colLayer1)
            Behavior on color { ColorAnimation { duration: 160 } }

            ColumnLayout {
                id: widgetCol
                anchors {
                    left: parent.left; right: parent.right
                    verticalCenter: parent.verticalCenter
                    leftMargin: 4; rightMargin: 4
                }
                spacing: 0

                RowLayout {
                    id: widgetRow
                    readonly property var modelData: widgetBlock.modelData
                    readonly property bool on: widgetBlock.on
                    Layout.fillWidth: true
                    spacing: 0

                    ConfigSwitch {
                        Layout.fillWidth: true
                        buttonIcon: widgetRow.modelData.icon
                        text: widgetRow.modelData.name
                        checked: widgetRow.on
                        onCheckedChanged: {
                            if (checked !== widgetRow.on)
                                root.registry.toggle(widgetRow.modelData.id);
                        }
                    }
                    // Reorder only makes sense once it is on the surface.
                    RippleButton {
                        visible: widgetRow.on
                        implicitWidth: 26
                        implicitHeight: 26
                        buttonRadius: Appearance.rounding.full
                        onClicked: root.registry.move(widgetRow.modelData.id, -1)
                        contentItem: MaterialSymbol {
                            anchors.centerIn: parent
                            text: root.horizontalOrder ? "chevron_left" : "expand_less"
                            iconSize: Appearance.font.pixelSize.large
                            color: Appearance.colors.colOnLayer0
                        }
                    }
                    RippleButton {
                        visible: widgetRow.on
                        implicitWidth: 26
                        implicitHeight: 26
                        buttonRadius: Appearance.rounding.full
                        onClicked: root.registry.move(widgetRow.modelData.id, 1)
                        contentItem: MaterialSymbol {
                            anchors.centerIn: parent
                            text: root.horizontalOrder ? "chevron_right" : "expand_more"
                            iconSize: Appearance.font.pixelSize.large
                            color: Appearance.colors.colOnLayer0
                        }
                    }
                }

                // Hairline between a widget and its own settings, so the
                // sub-rows read as belonging to it rather than as more widgets.
                Rectangle {
                    visible: widgetBlock.on && widgetBlock.schema.length > 0
                    Layout.fillWidth: true
                    Layout.leftMargin: 10
                    Layout.rightMargin: 10
                    Layout.topMargin: 2
                    Layout.bottomMargin: 2
                    implicitHeight: 1
                    color: Appearance.colors.colOutlineVariant
                    opacity: 0.6
                }

                Repeater {
                    model: widgetBlock.on ? widgetBlock.schema : []
                    delegate: Loader {
                        required property var modelData
                        readonly property string wid: widgetBlock.modelData.id
                        readonly property var reg: root.registry
                        Layout.fillWidth: true
                        Layout.leftMargin: 10
                        sourceComponent: modelData.type === "int" ? intSetting : boolSetting
                    }
                }
            }
        }
    }

    Component {
        id: boolSetting
        ConfigSwitch {
            text: parent.modelData.label
            checked: parent.reg.get(parent.wid, parent.modelData.key) === true
            onCheckedChanged: {
                if (checked !== (parent.reg.get(parent.wid, parent.modelData.key) === true))
                    parent.reg.set(parent.wid, parent.modelData.key, checked);
            }
        }
    }
    Component {
        id: intSetting
        ConfigSpinBox {
            text: parent.modelData.label
            value: parent.reg.get(parent.wid, parent.modelData.key) ?? 0
            from: parent.modelData.min ?? 0
            to: parent.modelData.max ?? 100
            stepSize: 1
            onValueChanged: parent.reg.set(parent.wid, parent.modelData.key, value)
        }
    }
}
