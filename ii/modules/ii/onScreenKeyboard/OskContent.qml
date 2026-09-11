import qs.modules.common
import qs.services
import "layouts.js" as Layouts
import QtQuick
import QtQuick.Layouts

Item {
    id: root
    property var layouts: Layouts.byName

    // The drawn keys follow the REAL keyboard by default.
    //
    // HyprlandXkb tracks the layout of the keyboard that last produced input
    // (see its lastKeyboardName), so with more than one keyboard attached the
    // OSK shows the one you are actually typing on rather than whichever device
    // happens to be flagged `main`.
    readonly property string systemLayoutName:
        Layouts.resolve(HyprlandXkb.currentLayoutName, HyprlandXkb.currentLayoutCode)

    // Manual override, used when following is off or the system layout has no
    // drawn equivalent here (e.g. French — no AZERTY keymap in layouts.js).
    readonly property string configuredLayoutName:
        layouts.hasOwnProperty(Config.options?.osk?.layout ?? "")
            ? Config.options.osk.layout
            : Layouts.defaultLayout

    property var activeLayoutName: {
        const follow = Config.options?.osk?.followSystemLayout ?? true
        if (follow && root.systemLayoutName.length > 0) return root.systemLayoutName
        return root.configuredLayoutName
    }
    property var currentLayout: layouts[activeLayoutName] ?? layouts[Layouts.defaultLayout]

    implicitWidth: keyRows.implicitWidth
    implicitHeight: keyRows.implicitHeight

    ColumnLayout {
        id: keyRows
        anchors.fill: parent
        spacing: 5

        Repeater {
            model: root.currentLayout.keys

            delegate: RowLayout {
                id: keyRow
                required property var modelData
                spacing: 5
                
                Repeater {
                    model: modelData
                    // A normal key looks like this: {label: "a", labelShift: "A", shape: "normal", keycode: 30, type: "normal"}
                    delegate: OskKey { 
                        required property var modelData
                        keyData: modelData
                    }
                }
            }
        }
    }
}
