import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts

/**
 * One labelled switch with its reason underneath.
 *
 * Extracted rather than repeated four times: every processing stage needs the
 * same row, and an unavailable option has to say WHY in the same place the
 * working ones say what they do.
 *
 * The switch does NOT bind `checked` to the state and write it back. A
 * user-driven write to `checked` destroys that binding, so after the first click
 * the switch stops following the service — it would keep showing the last click
 * even if the command failed. Instead the state drives the visual, and the click
 * only emits; the service decides what `checked` becomes.
 */
RowLayout {
    id: root
    Layout.fillWidth: true
    spacing: 8

    property string label: ""
    property string help: ""
    property bool checked: false
    property bool available: true
    signal toggled(bool on)

    ColumnLayout {
        Layout.fillWidth: true
        spacing: 1

        StyledText {
            text: root.label
            font.pixelSize: Appearance.font.pixelSize.smaller
            color: root.available ? Appearance.colors.colOnLayer1 : Appearance.colors.colSubtext
        }
        StyledText {
            Layout.fillWidth: true
            visible: root.help !== ""
            text: root.help
            wrapMode: Text.Wrap
            font.pixelSize: Appearance.font.pixelSize.smallest
            color: Appearance.colors.colSubtext
        }
    }

    StyledSwitch {
        id: sw
        enabled: root.available
        opacity: root.available ? 1 : 0.45
        // One-way: state in. Re-asserted after every click so a refused or failed
        // action snaps the switch back instead of lying about it.
        checked: root.checked
        onClicked: {
            const want = !root.checked;
            checked = Qt.binding(() => root.checked);
            root.toggled(want);
        }
    }
}
