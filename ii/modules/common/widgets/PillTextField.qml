import qs.modules.common
import QtQuick
import QtQuick.Layouts

/**
 * Compact rounded text field with an M3-style floating label.
 *
 * Single-row height (~34px) that vertically aligns with IconToolbarButton
 * rows. Floating label slides from inside the pill (centred next to the
 * leading icon) onto the top border when focused or non-empty, with a
 * background-coloured "notch" that punches through the outline.
 *
 * Use as a drop-in alternative to MaterialTextField when you don't want the
 * full M3 TextField height (~56px) — typical in compact header/toolbar rows.
 *
 * Properties
 *   text             : current input text (alias on TextInput.text)
 *   placeholderText  : floating label content (default "Search…")
 *   leadingIcon      : Material Symbol shown on the left (default "search").
 *                      Set to "" to hide.
 *   showClear        : if true (default), shows a "×" when text is non-empty
 *   pillWidth        : preferred width hint for parent layouts
 *
 * Signals
 *   accepted()  : Enter pressed
 *   cleared()   : "×" clicked
 *
 * Example
 *   PillTextField {
 *       placeholderText: qsTr("Filter…")
 *       leadingIcon: "filter_list"
 *       onTextChanged: root.query = text
 *   }
 */
Rectangle {
    id: root

    // Public API
    property string placeholderText: qsTr("Search…")
    property string leadingIcon: "search"
    property bool showClear: true
    property alias text: input.text
    property alias inputItem: input          // expose so callers can forceActiveFocus
    property real pillWidth: 220

    signal accepted()
    signal cleared()

    readonly property bool floated: input.activeFocus || input.text.length > 0

    implicitWidth: pillWidth
    implicitHeight: 34
    radius: height / 2
    color: "transparent"
    border.width: floated ? 1.5 : 1
    border.color: floated ? Appearance.colors.colPrimary : Appearance.colors.colOutlineVariant
    Behavior on border.color { ColorAnimation { duration: 160 } }

    // ── Contents ─────────────────────────────────────────────────────────
    RowLayout {
        anchors.fill: parent
        anchors.leftMargin: 12
        anchors.rightMargin: 10
        spacing: 8

        MaterialSymbol {
            text: root.leadingIcon
            iconSize: 16
            visible: text.length > 0
            Layout.alignment: Qt.AlignVCenter
            color: root.floated ? Appearance.colors.colPrimary : Appearance.colors.colSubtext
            Behavior on color { ColorAnimation { duration: 160 } }
        }

        TextInput {
            id: input
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignVCenter
            verticalAlignment: TextInput.AlignVCenter
            font.family: Appearance.font.family.main
            font.pixelSize: Appearance.font.pixelSize.small
            color: Appearance.colors.colOnLayer1
            selectionColor: Appearance.colors.colSecondaryContainer
            selectedTextColor: Appearance.m3colors.m3onSecondaryContainer
            onAccepted: root.accepted()
        }

        MaterialSymbol {
            text: "close"
            iconSize: 14
            visible: root.showClear && input.text.length > 0
            Layout.alignment: Qt.AlignVCenter
            color: Appearance.colors.colSubtext
            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                    input.text = ""
                    root.cleared()
                }
            }
        }
    }

    // ── Floating label ───────────────────────────────────────────────────
    // Lives on the pill (not inside TextInput) so its animation isn't
    // clipped by the input's bounds. Slides from inside the pill onto the
    // top border, scaling text down one step.
    Text {
        id: floatingLabel
        text: root.placeholderText
        font.family: Appearance.font.family.main
        font.pixelSize: root.floated
            ? Appearance.font.pixelSize.smaller
            : Appearance.font.pixelSize.small
        color: root.floated ? Appearance.colors.colPrimary : Appearance.colors.colSubtext
        // x: align with the input's text column. 36 = leftMargin + icon + spacing.
        x: root.floated ? 14
                        : (root.leadingIcon === "" ? 12 : 36)
        y: root.floated ? -(implicitHeight / 2)
                        : (root.height - implicitHeight) / 2
        visible: input.text.length === 0

        // Notch background — "cuts" the border line for the M3 outlined look.
        Rectangle {
            anchors.fill: parent
            anchors.leftMargin: -4; anchors.rightMargin: -4
            color: Appearance.colors.colLayer0
            z: -1
            visible: root.floated
        }

        Behavior on y              { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
        Behavior on x              { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
        Behavior on font.pixelSize { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
        Behavior on color          { ColorAnimation  { duration: 160 } }
    }

    // Click anywhere on the pill to focus.
    MouseArea {
        anchors.fill: parent
        cursorShape: Qt.IBeamCursor
        acceptedButtons: Qt.NoButton
    }
    TapHandler { onTapped: input.forceActiveFocus() }
}
