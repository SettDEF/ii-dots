// StartMenuHome — the Start Menu's landing page: Pinned apps, Recommended
// (frecency-ranked, reusing services/LauncherRanking.qml), a scrollable list
// of every app, and a power-action row (modules/common/functions/Session.qml).
// No search/ranking logic lives here — only reads of existing services.
pragma ComponentBehavior: Bound
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Widgets

ColumnLayout {
    id: root
    spacing: 12

    readonly property var pinnedEntries: (Config.options?.launcher.pinnedApps ?? [])
        .map(id => DesktopEntries.byId(id))
        .filter(e => e)

    // Top-6 by frecency, minus anything already pinned above.
    readonly property var recommended: LauncherRanking.apply(
        AppSearch.list.map(e => ({ entry: e, score: 0 })), "frecency", { limit: 10 }
    ).map(it => it.entry).filter(e => root.pinnedEntries.indexOf(e) === -1).slice(0, 6)

    readonly property var allEntries: LauncherRanking.apply(
        AppSearch.list.map(e => ({ entry: e, score: 0 })), "alphabetical", {}
    ).map(it => it.entry)

    component SectionLabel: StyledText {
        font.pixelSize: Appearance.font.pixelSize.smaller
        font.weight: Font.Bold
        color: Appearance.colors.colSubtext
    }

    SectionLabel { visible: root.pinnedEntries.length > 0; text: Translation.tr("Pinned") }
    Flow {
        Layout.fillWidth: true
        visible: root.pinnedEntries.length > 0
        spacing: 4
        Repeater {
            model: root.pinnedEntries
            delegate: StartMenuAppTile {
                required property var modelData
                entry: modelData
            }
        }
    }

    SectionLabel { visible: root.recommended.length > 0; text: Translation.tr("Recommended") }
    Flow {
        Layout.fillWidth: true
        visible: root.recommended.length > 0
        spacing: 4
        Repeater {
            model: root.recommended
            delegate: StartMenuAppTile {
                required property var modelData
                entry: modelData
            }
        }
    }

    SectionLabel { text: Translation.tr("All apps") }
    StyledListView {
        id: allAppsList
        Layout.fillWidth: true
        Layout.fillHeight: true
        clip: true
        model: ScriptModel {
            objectProp: "id"
            values: root.allEntries
        }
        delegate: AppRow {
            required property var modelData
            entry: modelData
            width: allAppsList.width
        }
    }

    RowLayout {
        Layout.fillWidth: true
        Layout.topMargin: 2
        spacing: 6

        Item { Layout.fillWidth: true }

        PowerBtn { powerIcon: "lock";              tip: Translation.tr("Lock");     onClicked: root.doPower(Session.lock) }
        PowerBtn { powerIcon: "dark_mode";         tip: Translation.tr("Sleep");    onClicked: root.doPower(Session.suspend) }
        PowerBtn { powerIcon: "logout";            tip: Translation.tr("Log out");  onClicked: root.doPower(Session.logout) }
        PowerBtn { powerIcon: "restart_alt";       tip: Translation.tr("Restart");  onClicked: root.doPower(Session.reboot) }
        PowerBtn { powerIcon: "power_settings_new"; tip: Translation.tr("Shut down"); onClicked: root.doPower(Session.poweroff) }
    }

    function doPower(fn) {
        GlobalStates.startMenuOpen = false
        fn()
    }

    // One row in the "All apps" list — icon, name, launch on click.
    component AppRow: RippleButton {
        id: rowBtn
        required property var entry
        implicitHeight: 40
        buttonRadius: Appearance.rounding.small
        colBackgroundHover: Appearance.colors.colLayer1Hover
        colRipple: Appearance.colors.colLayer1Active
        onClicked: { GlobalStates.startMenuOpen = false; AppLaunch.launch(rowBtn.entry) }

        contentItem: RowLayout {
            spacing: 10
            IconImage {
                Layout.leftMargin: 8
                source: Quickshell.iconPath(AppSearch.guessIcon(rowBtn.entry?.id ?? ""), "image-missing")
                implicitSize: 22
            }
            StyledText {
                Layout.fillWidth: true
                text: rowBtn.entry?.name ?? ""
                font.pixelSize: Appearance.font.pixelSize.small
                color: Appearance.colors.colOnLayer1
                elide: Text.ElideRight
            }
        }
    }

    // One button in the power row.
    component PowerBtn: RippleButton {
        id: powerBtn
        required property string powerIcon
        required property string tip
        implicitWidth: 34
        implicitHeight: 34
        buttonRadius: Appearance.rounding.full
        colBackgroundHover: Appearance.colors.colLayer1Hover
        colRipple: Appearance.colors.colLayer1Active
        contentItem: MaterialSymbol {
            anchors.centerIn: parent
            text: powerBtn.powerIcon
            iconSize: Appearance.font.pixelSize.larger
            color: Appearance.colors.colOnLayer1
        }
        StyledToolTip { text: powerBtn.tip }
    }
}
