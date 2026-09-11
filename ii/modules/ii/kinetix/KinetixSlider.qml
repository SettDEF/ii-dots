// A labelled slider row for the pointer panel.
//
// Extracted because the panel needs three of them and they differ only in
// label, range and suffix — the shape of the row is identical.
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts

ColumnLayout {
    id: row

    property string label: ""
    property string hint: ""
    property real from: 0
    property real to: 1
    property real value: 0
    property string suffix: ""
    /// Emitted on release and on typed entry, never per-pixel while dragging —
    /// each commit writes the config file and wakes the daemon.
    signal committed(real v)

    Layout.fillWidth: true
    spacing: 2

    RowLayout {
        Layout.fillWidth: true
        StyledText {
            Layout.fillWidth: true
            text: row.label
            elide: Text.ElideRight
            font.pixelSize: Appearance.font.pixelSize.small
            color: Appearance.colors.colOnLayer1
        }
        StyledText {
            // The SLIDER's live position, not the committed value: dragging
            // must show the number you are dragging to. The write still only
            // happens on release (see below) — showing live and writing live
            // are different things, and only the second one is expensive.
            text: slider.value.toFixed(2) + row.suffix
            font.pixelSize: Appearance.font.pixelSize.small
            font.family: Appearance.font.family.numbers
            font.weight: Font.DemiBold
            color: Appearance.colors.colOnLayer1
        }
    }

    StyledSlider {
        id: slider
        Layout.fillWidth: true
        from: row.from
        to: row.to
        // Only adopt the external value when not dragging, or the binding
        // fights the thumb: each commit writes the config, the config is read
        // back, and `row.value` snaps the slider out from under your finger.
        value: row.value
        Binding on value {
            when: !slider.pressed
            value: row.value
        }
        onPressedChanged: if (!pressed) row.committed(value)
    }

    StyledText {
        Layout.fillWidth: true
        visible: row.hint.length > 0
        text: row.hint
        wrapMode: Text.WordWrap
        font.pixelSize: Appearance.font.pixelSize.smallest
        color: Appearance.colors.colSubtext
    }
}
