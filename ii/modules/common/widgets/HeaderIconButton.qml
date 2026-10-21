import qs.services
import qs.modules.common
import QtQuick

// One button in a HeaderActionGroup, drawn by the button style the menus use (a QML file:
// services/ButtonStyles.qml). This side does the hover, the click, the tooltip and hands the
// style its state, the icon and the theme's colours; the style draws, and says its size.
// `danger` is the close, `toggled` a button that is on.
Item {
    id: root
    property string icon: ""
    property string tooltip: ""
    property bool danger: false
    property bool toggled: false
    signal clicked()
    // the style's own values (gap, pill), for HeaderActionGroup
    readonly property var face: loader.item

    implicitWidth: loader.item?.implicitWidth ?? 28
    implicitHeight: loader.item?.implicitHeight ?? 28

    Loader {
        id: loader
        anchors.fill: parent
        source: ButtonStyles.currentUrl
        onLoaded: root.apply()
        onStatusChanged: if (status === Loader.Error) console.warn(`HeaderIconButton: button style ${ButtonStyles.currentPath} failed to load`)
    }

    // what the shell gives every style (a style declares only those it uses), then the config's values
    function apply() {
        const it = loader.item;
        if (!it) return;
        const vars = ButtonStyles.vars;
        for (const k in vars) {
            if (k in it) it[k] = vars[k];
        }
    }
    Connections {
        target: ButtonStyles
        function onVarsChanged() { root.apply() }
    }
    // a style declares only what it uses: give it what it has
    function has(n) { return loader.item !== null && (n in loader.item) }
    Binding { target: loader.item; property: "icon"; value: root.icon; when: root.has("icon"); restoreMode: Binding.RestoreNone }
    Binding { target: loader.item; property: "danger"; value: root.danger; when: root.has("danger"); restoreMode: Binding.RestoreNone }
    Binding { target: loader.item; property: "toggled"; value: root.toggled; when: root.has("toggled"); restoreMode: Binding.RestoreNone }
    Binding { target: loader.item; property: "hovered"; value: hov.hovered; when: root.has("hovered"); restoreMode: Binding.RestoreNone }
    Binding { target: loader.item; property: "pressed"; value: tap.pressed; when: root.has("pressed"); restoreMode: Binding.RestoreNone }
    Binding { target: loader.item; property: "iconFamily"; value: Appearance?.font.family.iconMaterial ?? "Material Symbols Rounded"; when: root.has("iconFamily"); restoreMode: Binding.RestoreNone }
    Binding { target: loader.item; property: "errorColor"; value: Appearance.m3colors.m3error; when: root.has("errorColor"); restoreMode: Binding.RestoreNone }
    Binding { target: loader.item; property: "errorContainer"; value: Appearance.m3colors.m3errorContainer; when: root.has("errorContainer"); restoreMode: Binding.RestoreNone }
    Binding { target: loader.item; property: "errorInk"; value: Appearance.m3colors.m3onErrorContainer; when: root.has("errorInk"); restoreMode: Binding.RestoreNone }
    Binding { target: loader.item; property: "primaryColor"; value: Appearance.colors.colPrimary; when: root.has("primaryColor"); restoreMode: Binding.RestoreNone }
    Binding { target: loader.item; property: "primaryInk"; value: Appearance.colors.colOnPrimary; when: root.has("primaryInk"); restoreMode: Binding.RestoreNone }
    Binding { target: loader.item; property: "tertiaryColor"; value: Appearance.m3colors.m3tertiary; when: root.has("tertiaryColor"); restoreMode: Binding.RestoreNone }
    Binding { target: loader.item; property: "neutralColor"; value: Qt.alpha(Appearance.colors.colOnLayer0, 0.38); when: root.has("neutralColor"); restoreMode: Binding.RestoreNone }
    Binding { target: loader.item; property: "inkOnFill"; value: Appearance.colors.colLayer0; when: root.has("inkOnFill"); restoreMode: Binding.RestoreNone }
    Binding { target: loader.item; property: "inkPlain"; value: Appearance.colors.colOnLayer1; when: root.has("inkPlain"); restoreMode: Binding.RestoreNone }
    Binding { target: loader.item; property: "hoverBg"; value: Appearance.colors.colLayer2Hover; when: root.has("hoverBg"); restoreMode: Binding.RestoreNone }
    Binding { target: loader.item; property: "pressBg"; value: Appearance.colors.colLayer2Active; when: root.has("pressBg"); restoreMode: Binding.RestoreNone }

    // a small button keeps the hit area of a normal one
    readonly property real slop: Appearance.sizes.touchSlop + Math.max(0, (28 - root.width) / 2)
    HoverHandler { id: hov; margin: root.slop; cursorShape: Qt.PointingHandCursor }
    TapHandler { id: tap; margin: root.slop; onTapped: root.clicked() }

    StyledToolTip {
        text: root.tooltip
        extraVisibleCondition: false
        alternativeVisibleCondition: hov.hovered && root.tooltip.length > 0
    }
}
