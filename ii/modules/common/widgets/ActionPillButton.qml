import qs
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts

// An action as an icon + label pill (Wi-Fi networks, Bluetooth devices). `tone`: "filled" (the main
// action), "tonal" (neutral), "active" (an on-state, e.g. Preferred),
// "danger" (outlined red: destructive, but not a red block that makes the
// whole card read as a warning).
Rectangle {
    id: root
    property string icon: ""
    property string text: ""
    property string tone: "tonal"
    property bool loading: false
    signal clicked

    /// Exact colours for one button, overriding its tone: a place that had
    /// its own button colours keeps them (Wi-Fi's tonal Prefer, Bluetooth's
    /// solid red Forget). Unset ("transparent" default never used as a fill
    /// here) = the tone decides.
    property color colBackground: "#00000000"
    property color colText: "#00000000"
    readonly property bool _customBg: root.colBackground.a > 0
    readonly property bool _customText: root.colText.a > 0

    readonly property color ink: root._customText ? root.colText
        : root.tone === "filled" || root.tone === "active" ? Appearance.colors.colOnPrimary
        : root.tone === "danger" ? Appearance.colors.colError
        : Appearance.colors.colOnLayer2

    Layout.fillWidth: true
    implicitHeight: 38
    implicitWidth: row.implicitWidth + 28
    radius: height / 2
    opacity: root.enabled ? 1 : 0.5
    color: root._customBg
        ? (hover.hovered ? Qt.tint(root.colBackground, Qt.alpha(root.ink, 0.10)) : root.colBackground)
        : root.tone === "filled" || root.tone === "active"
        ? (hover.hovered ? Appearance.colors.colPrimaryHover : Appearance.colors.colPrimary)
        : root.tone === "danger"
        ? (hover.hovered ? Qt.alpha(Appearance.colors.colError, 0.14) : "transparent")
        : (hover.hovered ? Appearance.colors.colLayer2Hover : Appearance.colors.colLayer2)
    border.width: root.tone === "danger" && !root._customBg ? 1 : 0
    border.color: Qt.alpha(Appearance.colors.colError, 0.55)
    Behavior on color { animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this) }

    HoverHandler { id: hover; cursorShape: Qt.PointingHandCursor }
    TapHandler { enabled: root.enabled; onTapped: root.clicked() }

    RowLayout {
        id: row
        anchors.centerIn: parent
        spacing: 6
        MaterialSymbol {
            visible: root.icon.length > 0 && !root.loading
            text: root.icon
            iconSize: 18
            fill: root.tone === "active" ? 1 : 0
            color: root.ink
        }
        MaterialLoadingIndicator {
            visible: root.loading
            loading: root.loading
            implicitSize: 18
        }
        StyledText {
            text: root.text
            font.pixelSize: Appearance.font.pixelSize.small
            font.weight: Font.Medium
            color: root.ink
        }
    }
}
