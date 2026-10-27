import qs.modules.common
import qs.modules.common.widgets
import qs.services
import QtQuick
import QtQuick.Layouts

// One Glass app group as a card: a header row (dropdown) and the apps. Closed,
// it lists only the apps that are on; open, all of them.
PaletteCard {
    id: group
    property string title: ""
    property string glyph: "layers"
    property var apps: []               // [{ id, name, icon }]
    property var section: null          // GlassSection: appValue(id), openApp
    property bool showAll: false

    // apps is briefly unset while the card is built: guard every read.
    readonly property var appList: group.apps ?? []
    readonly property var onApps: {
        void Config.options.appearance.glass.apps
        return group.appList.filter(a => Glass.appState(a.id)?.on ?? false)
    }
    readonly property var shown: group.showAll ? group.appList : group.onApps

    // Header = the dropdown.
    PaletteRow {
        glyph: group.glyph
        title: group.title
        value: qsTr("%1 on · %2 off").arg((group.onApps ?? []).length).arg((group.appList ?? []).length - (group.onApps ?? []).length)
        lit: (group.onApps ?? []).length > 0
        chevronIcon: "expand_more"
        chevronRotation: group.showAll ? 180 : 0
        onClicked: group.showAll = !group.showAll
    }

    Repeater {
        model: group.shown
        delegate: ColumnLayout {
            required property var modelData
            Layout.fillWidth: true
            spacing: 0
            PaletteDivider {}
            PaletteRow {
                glyph: modelData.icon
                title: modelData.name
                value: { void Config.options.appearance.glass.apps; return group.section?.appValue(modelData.id) ?? "" }
                lit: { void Config.options.appearance.glass.apps; return Glass.active && (Glass.appState(modelData.id)?.on ?? false) }
                onClicked: if (group.section) group.section.openApp = modelData.id
            }
        }
    }

    // Opening scrolls the page so the unfolded apps are in view (never past the
    // card's own top), with its own easing so it is smooth on any page.
    onShowAllChanged: if (showAll) revealTimer.restart()
    Timer { id: revealTimer; interval: 40; onTriggered: group.reveal() }
    NumberAnimation {
        id: revealAnim
        property: "contentY"
        duration: 380
        easing.type: Easing.OutCubic
    }
    function reveal() {
        let f = group.parent
        while (f && f.contentY === undefined) f = f.parent
        if (!f || !f.contentItem) return
        const p = group.mapToItem(f.contentItem, 0, 0)
        let y = f.contentY
        if (p.y + group.height + 12 > y + f.height) y = p.y + group.height + 12 - f.height
        if (p.y - 8 < y) y = p.y - 8
        y = Math.max(0, Math.min(y, f.contentHeight - f.height))
        if (Math.abs(y - f.contentY) < 1) return
        if (f.animateContentY !== undefined) f.animateContentY = false   // our animation, not its Behavior
        revealAnim.stop()
        revealAnim.target = f
        revealAnim.from = f.contentY
        revealAnim.to = y
        revealAnim.start()
        if (f.scrollTargetY !== undefined) f.scrollTargetY = y
    }
    Connections {
        target: revealAnim
        function onStopped() {
            if (revealAnim.target && revealAnim.target.animateContentY !== undefined)
                revealAnim.target.animateContentY = true
        }
    }
}
