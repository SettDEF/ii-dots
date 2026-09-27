import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts

/// A left-hand list of the sections in a scrolling page, as used by the
/// settings window and the Palette panel.
///
///     SectionRail { flickable: page; column: page.contentItem }
///
/// It scrolls to a heading rather than swapping pages: the column stays one
/// document, so state keeps sitting next to what it affects.
Rectangle {
    id: root

    /// The scrolling area, and the column inside it holding the sections.
    property Flickable flickable: null
    property Item column: null

    /// Transparent by default, like the settings nav rail: the selected pill is
    /// colSecondaryContainer, which is dark, and on a raised container it reads
    /// as a hole rather than as a selection. A host with a very dark ground can
    /// set one.
    property color surface: "transparent"

    /// Anything in the column carrying a title. ContentSection and any other
    /// heading with `title` and `icon` qualify without being told to.
    readonly property var sections: {
        if (!root.column) return [];
        void root.column.children.length;
        const out = [];
        const walk = (item, depth) => {
            for (const c of item.children) {
                if (!c || !c.visible) continue;
                if (c.title !== undefined && String(c.title).length > 0) out.push(c);
                else if (depth > 0) walk(c, depth - 1);
            }
        };
        walk(root.column, 1);
        return out;
    }

    property int currentSection: 0

    function sectionY(item) {
        return item.mapToItem(root.column, 0, 0).y;
    }

    function goToSection(i) {
        const target = root.sections[i];
        if (!target || !root.flickable) return;
        scrollAnim.to = Math.max(0, Math.min(root.sectionY(target) - 10,
                                             root.flickable.contentHeight - root.flickable.height));
        scrollAnim.restart();
        root.currentSection = i;
    }

    implicitWidth: 150
    radius: Appearance.rounding.large
    color: root.surface
    visible: root.sections.length > 1

    NumberAnimation {
        id: scrollAnim
        target: root.flickable
        property: "contentY"
        duration: 260
        easing.type: Easing.BezierSpline
        easing.bezierCurve: Appearance.animationCurves.emphasizedDecel
    }

    Connections {
        target: root.flickable
        enabled: root.flickable !== null
        function onContentYChanged() {
            if (scrollAnim.running) return;
            // The last sections sit inside the final screenful and never reach
            // the top, so the reading line sweeps down as the scroll runs out.
            const max = Math.max(1, root.flickable.contentHeight - root.flickable.height);
            const t = Math.min(1, Math.max(0, root.flickable.contentY / max));
            const sweep = Math.max(0, (t - 0.5) * 2);
            const line = root.flickable.contentY + 28
                       + (root.flickable.height - 28) * sweep;
            let best = 0;
            for (let i = 0; i < root.sections.length; ++i)
                if (root.sectionY(root.sections[i]) <= line) best = i;
            root.currentSection = best;
        }
    }

    ColumnLayout {
        anchors {
            left: parent.left; right: parent.right; top: parent.top
            margins: 8
        }
        spacing: 2

        Repeater {
            model: root.sections

            delegate: Rectangle {
                id: railItem
                required property var modelData
                required property int index
                readonly property bool active: root.currentSection === index
                readonly property color fg: railItem.active
                    ? Appearance.m3colors.m3onSecondaryContainer
                    : Appearance.colors.colOnLayer1

                Layout.fillWidth: true
                implicitHeight: 34
                radius: Appearance.rounding.full
                // Never bare "transparent": a ColorAnimation to it walks RGB
                // toward 0 as well as alpha, so every frame in between is
                // translucent BLACK and the row flashes a grey plate.
                color: railItem.active ? Appearance.colors.colSecondaryContainer
                     : railHover.hovered ? Appearance.colors.colLayer2
                     : ColorUtils.transparentize(Appearance.colors.colSecondaryContainer)
                Behavior on color { ColorAnimation { duration: 140 } }

                HoverHandler { id: railHover }
                TapHandler { onTapped: root.goToSection(railItem.index) }

                Row {
                    anchors {
                        left: parent.left; leftMargin: 11
                        right: parent.right; rightMargin: 8
                        verticalCenter: parent.verticalCenter
                    }
                    spacing: 8

                    MaterialSymbol {
                        anchors.verticalCenter: parent.verticalCenter
                        text: railItem.modelData.icon ?? "chevron_right"
                        iconSize: Appearance.font.pixelSize.normal
                        color: railItem.fg
                        opacity: railItem.active ? 1 : 0.65
                    }
                    StyledText {
                        anchors.verticalCenter: parent.verticalCenter
                        width: parent.width - 8 - Appearance.font.pixelSize.normal
                        text: railItem.modelData.title ?? ""
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        font.weight: railItem.active ? Font.DemiBold : Font.Normal
                        color: railItem.fg
                        opacity: railItem.active ? 1 : 0.7
                        elide: Text.ElideRight
                    }
                }
            }
        }
    }
}
