pragma Singleton
pragma ComponentBehavior: Bound

// Bank data for the sidebar, read from the file `finance-sync` writes.
//
// The shell never talks to a bank. PSD2 caps unattended access at roughly four
// calls per account per day and consent expires every 90 days, so a Rust timer
// does the fetching and this just watches the result. That also means the
// sidebar paints instantly from cache instead of blocking on a bank.
//
// See scripts/finance/ for the fetcher.

import qs.modules.common
import Quickshell
import Quickshell.Io
import QtQuick

Singleton {
    id: root

    readonly property string statePath: `${Directories.state}/finance.json`

    property var data: ({})
    property bool loaded: false
    // Set when the fetcher could not refresh. Kept separate from `loaded` so
    // the UI can show stale numbers AND say they are stale, rather than
    // pretending a failed sync is fine.
    property string error: ""

    readonly property string currency:        root.data.currency ?? "EUR"
    readonly property real totalBalance:      root.data.total_balance ?? 0
    readonly property real spentThisMonth:    root.data.spent_this_month ?? 0
    readonly property real incomeThisMonth:   root.data.income_this_month ?? 0
    readonly property var accounts:           root.data.accounts ?? []
    readonly property var transactions:       root.data.transactions ?? []
    readonly property var recurring:          root.data.recurring ?? []
    readonly property var byCategory:         root.data.by_category ?? ({})
    readonly property string generatedAt:     root.data.generated_at ?? ""
    readonly property string consentExpires:  root.data.consent_expires ?? ""

    readonly property real safeToSpend:    root.data.safe_to_spend ?? 0
    readonly property real prevMonthSpent: root.data.prev_month_spent ?? 0
    readonly property var upcoming:        root.data.upcoming ?? []
    readonly property var dailyNet:        root.data.daily_net ?? []

    readonly property bool available: root.loaded && root.accounts.length > 0

    // Small view-side derivations. Anything heavier — month totals, recurring
    // detection, projections — is done once per sync in Rust, not in bindings.
    readonly property real committedSoon: root.totalBalance - root.safeToSpend
    readonly property real committedFraction:
        root.totalBalance > 0 ? root.committedSoon / root.totalBalance : 0
    readonly property real recurringMonthly:
        root.recurring.reduce((sum, r) => sum + Math.abs(r.amount), 0)
    /// Percent change in spend versus last month. Guarded: with no previous
    /// month this would be a divide by zero rendered as "Infinity%".
    readonly property real spendDelta:
        root.prevMonthSpent > 0
            ? ((root.spentThisMonth - root.prevMonthSpent) / root.prevMonthSpent) * 100
            : 0
    /// Categories biggest-first, shared by the overview bars and the filter
    /// chips so the two always list the same set in the same order.
    readonly property var categoriesSorted: {
        const out = [];
        for (const k in root.byCategory) out.push({ name: k, value: root.byCategory[k] });
        out.sort((a, b) => b.value - a.value);
        return out;
    }

    // Consent dies every 90 days and the re-link is manual, so warn while
    // there is still time to do something about it.
    readonly property int consentDaysLeft: {
        if (root.consentExpires.length === 0) return -1;
        const end = new Date(root.consentExpires);
        if (isNaN(end.getTime())) return -1;
        return Math.floor((end - new Date()) / 86400000);
    }
    readonly property bool consentExpiringSoon: consentDaysLeft >= 0 && consentDaysLeft <= 14

    function money(v) {
        const sign = v < 0 ? "-" : "";
        return `${sign}${Math.abs(v).toFixed(2)} ${root.currency}`;
    }

    // Fire a sync by hand. The timer covers the normal case; this is for
    // "I just got paid and want to see it".
    function refresh() {
        syncProc.running = false;
        syncProc.running = true;
    }
    readonly property alias syncing: syncProc.running

    Process {
        id: syncProc
        command: [`${Directories.scriptPath}/finance/finance-sync`, "sync"]
        stderr: StdioCollector { id: syncErr }
        onExited: (code) => {
            if (code === 0) { root.error = ""; return }
            // Distinguish "not set up" from "broke". The first is a setup step
            // and telling the user it failed is just wrong; the second is a
            // real fault and gets the real message.
            const msg = (syncErr.text ?? "").trim();
            root.error = msg.includes("no linked session") || msg.includes("not found in")
                ? qsTr("Not linked yet — see scripts/finance/README.md")
                : (msg.length > 0 ? msg.split("\n")[0] : qsTr("Sync failed (exit %1)").arg(code));
        }
    }

    FileView {
        id: stateFile
        path: Qt.resolvedUrl(root.statePath)
        // The fetcher writes via a temp file and renames, so a change here is
        // always a complete document.
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            try {
                root.data = JSON.parse(stateFile.text() || "{}");
                root.error = root.data.error ?? "";
                root.loaded = true;
            } catch (e) {
                root.error = qsTr("Could not parse %1").arg(root.statePath);
                root.loaded = false;
            }
        }
        onLoadFailed: (error) => {
            root.loaded = false;
            root.error = (error === FileViewError.FileNotFound)
                ? qsTr("No data yet — run finance-sync")
                : qsTr("Could not read %1").arg(root.statePath);
        }
    }
}
