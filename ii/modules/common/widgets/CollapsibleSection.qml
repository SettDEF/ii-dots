import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts

/**
 * A CollapsibleHeader with its body. The body's space is reserved at once and
 * its content slides into it; tweening the height instead resizes the panel
 * every frame, which is what made expanding a section feel like dragging.
 *
 *     CollapsibleSection {
 *         title: "Battery"; value: "Limit 80%"; icon: "battery_charging_full"
 *         StyledSlider { ... }       // default children form the body
 *     }
 */
ColumnLayout {
    id: root

    property string title: ""
    property string value: ""
    property string icon: ""
    property bool expanded: false
    default property alias content: body.data

    Layout.fillWidth: true
    spacing: 6

    CollapsibleHeader {
        title: root.title
        value: root.value
        icon: root.icon
        expanded: root.expanded
        onToggled: root.expanded = !root.expanded
    }

    Item {
        Layout.fillWidth: true
        clip: true
        // A zero-height child still collects layout spacing; hidden, it is skipped.
        visible: implicitHeight > 0
        implicitHeight: root.expanded ? body.implicitHeight + 6 : 0

        ColumnLayout {
            id: body
            width: parent.width
            spacing: 10
            y: root.expanded ? 4 : -body.implicitHeight
            opacity: root.expanded ? 1 : 0
            Behavior on y {
                animation: Appearance.animation.elementMove.numberAnimation.createObject(this)
            }
            Behavior on opacity {
                animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
            }
        }
    }
}
