// One icon with a real fallback chain.
//
// The config had three separate ways to get an icon and no way to combine
// them: MaterialSymbol (always works, never a logo), CustomIcon (local assets
// only), and Quickshell.iconPath (theme only, silently empty when the theme
// lacks the name). Nothing tried one then the next, so any brand icon was
// all-or-nothing.
//
// This walks: icon theme → known theme roots on disk → Material Symbol.
//
// The disk step exists because an icon theme that is configured but NOT
// INSTALLED makes iconPath() return empty for everything — which is the state
// this machine is in (kdeglobals says Reversal; nothing by that name is
// installed). Papirus and breeze ARE installed, so looking straight at them
// keeps brand icons working regardless of what the theme setting claims.
//
// Example
//   BrandIcon {
//       names: MerchantIcons.iconNamesFor(txn.counterparty)
//       symbol: MerchantIcons.symbolFor(txn.counterparty, txn.category)
//   }
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import Quickshell
import Quickshell.Widgets

Item {
    id: root

    /// Icon-theme names to try, best first.
    property var names: []
    /// Material Symbol drawn when nothing above resolves. Always set one.
    property string symbol: "receipt"
    property int size: 20
    property color symbolColor: Appearance.colors.colSubtext

    implicitWidth: root.size
    implicitHeight: root.size

    // Explicit roots, biggest sizes first so the icon is downscaled rather
    // than blown up. Kept short on purpose: probing dozens of paths per row
    // in a list would cost more than the icons are worth.
    readonly property var _roots: [
        `${Quickshell.env("HOME")}/.local/share/icons/Papirus/64x64/apps`,
        `${Quickshell.env("HOME")}/.local/share/icons/Papirus/48x48/apps`,
        "/usr/share/icons/breeze-plus/apps/48",
        "/usr/share/icons/breeze/apps/48",
        "/usr/share/icons/hicolor/64x64/apps",
    ]

    // Candidate URLs, in order. The Image below walks this list on error.
    readonly property var _candidates: {
        const out = [];
        for (const n of (root.names ?? [])) {
            const themed = Quickshell.iconPath(n, "");
            if (themed && themed.length > 0) out.push(themed);
        }
        for (const n of (root.names ?? [])) {
            for (const dir of root._roots) out.push(`file://${dir}/${n}.svg`);
        }
        return out;
    }

    property int _index: 0
    // Reset the walk whenever the candidate set changes — a recycled list
    // delegate would otherwise keep the previous row's exhausted index.
    on_CandidatesChanged: root._index = 0

    IconImage {
        id: img
        anchors.fill: parent
        implicitSize: root.size
        visible: status === Image.Ready
        source: root._index < root._candidates.length ? root._candidates[root._index] : ""
        onStatusChanged: {
            // Step to the next candidate on failure; when they run out the
            // symbol below takes over.
            if (status === Image.Error && root._index < root._candidates.length)
                root._index++;
        }
    }

    MaterialSymbol {
        anchors.centerIn: parent
        visible: !img.visible
        text: root.symbol
        iconSize: Math.round(root.size * 0.85)
        color: root.symbolColor
    }
}
