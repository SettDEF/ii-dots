// Lightweight email/inbox service.
//
// Counts unread messages in the user's local maildir(s) — works with
// mbsync / isync / offlineimap / fetchmail / mutt setups out of the box.
// If no maildir is found, the count just stays 0 and the widget falls
// back to "Open inbox" mode.
//
// Tap action opens whatever you set in `Config.options.email.openUrl`
// (defaults to Gmail webmail).
//
// Doesn't require credentials, an IMAP client, or any background daemon.
pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import qs.modules.common

Singleton {
    id: root

    property int unread: 0
    property bool loading: false

    // Where to look for new mail. We try each pattern; first hit wins.
    // ~/Maildir/INBOX/new is the classic mbsync layout.
    readonly property var probePaths: [
        "~/Maildir/INBOX/new",
        "~/Maildir/inbox/new",
        "~/Maildir/new",
        "~/.maildir/INBOX/new",
        "~/.local/share/mail/INBOX/new"
    ]

    // URL opened on tap. Override via Config.options.email.openUrl if set.
    readonly property string openUrl:
        (Config.options?.email?.openUrl ?? "") || "https://mail.google.com"

    function refresh() {
        loading = true
        countProc.exec({ command: ["bash", "-c",
            // Print the count of new-mail files across all probe paths,
            // skipping ones that don't exist. Wholly silent on errors.
            probePaths.map(p =>
                `[ -d ${p} ] && find ${p} -maxdepth 1 -type f 2>/dev/null | wc -l`
            ).join(" ; ") + " | awk '{s+=$1} END{print s+0}'"
        ] })
    }

    function open() { Quickshell.execDetached(["xdg-open", openUrl]) }

    Process {
        id: countProc
        stdout: StdioCollector {
            onStreamFinished: {
                root.loading = false
                root.unread = parseInt(text.trim()) || 0
            }
        }
    }

    Timer {
        interval: 60000   // 1 min — gentle on disk
        running: true
        repeat: true
        onTriggered: root.refresh()
    }
    Component.onCompleted: refresh()
}
