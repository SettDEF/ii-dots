// Rss — reads newsboat's cache.db to surface unread articles.
// Polls newsboat for refresh every 15 min (only while the right
// sidebar is open) and re-reads the unread list every 60 s.
pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import qs

Singleton {
    id: root

    // Each entry: { title, url, author, feed, pubDate, unread }
    property var items: []
    readonly property int unreadCount:
        items.filter(i => i.unread).length

    // Newsboat ships with two possible cache paths.  Prefer the legacy
    // ~/.newsboat/cache.db when it exists (older configs), otherwise
    // fall back to the XDG ~/.local/share/newsboat/cache.db.  The bash
    // command picks whichever is on disk.
    readonly property string home: Quickshell.env("HOME") || `${Quickshell.env("HOME")}`
    readonly property string cacheLegacy: home + "/.newsboat/cache.db"
    readonly property string cacheXdg:    home + "/.local/share/newsboat/cache.db"

    // Multi-character separator unlikely to appear in any field.  Both
    // the bash side (sqlite3 -separator) and the JS side use this
    // verbatim, so the round-trip can't be mangled by escape parsing.
    readonly property string _sep: "<<|>>"

    function refresh() { readProc.exec({ command: ["bash", "-c", _readCmd() ]}) }
    function reload()  { reloadProc.exec({ command: ["bash", "-c",
        "newsboat -x reload >/dev/null 2>&1 || true"
    ]}) }
    function markRead(url) {
        if (!url) return
        markProc.exec({ command: ["bash", "-c",
            `db="${root.cacheLegacy}"; [ -f "$db" ] || db="${root.cacheXdg}"; ` +
            `sqlite3 "$db" "UPDATE rss_item SET unread=0 WHERE url='${url.replace(/'/g, "''")}';" 2>/dev/null`
        ]})
        const next = items.slice()
        for (let i = 0; i < next.length; i++) {
            if (next[i].url === url) {
                next[i] = Object.assign({}, next[i], { unread: false })
            }
        }
        items = next
    }

    function _readCmd() {
        return `db="${cacheLegacy}"; [ -f "$db" ] || db="${cacheXdg}"; ` +
            `[ -f "$db" ] && sqlite3 -separator '${_sep}' "$db" "
            SELECT
              REPLACE(REPLACE(IFNULL(title,''),  CHAR(10),' '), CHAR(13),' '),
              IFNULL(url,''),
              REPLACE(REPLACE(IFNULL(author,''), CHAR(10),' '), CHAR(13),' '),
              IFNULL(feedurl,''),
              IFNULL(pubDate,0),
              unread
            FROM rss_item
            ORDER BY pubDate DESC
            LIMIT 100;
        " 2>/dev/null`
    }

    Process {
        id: readProc
        stdout: StdioCollector { onStreamFinished: {
            const next = []
            const sep = root._sep
            for (const ln of (text || "").split("\n")) {
                if (!ln) continue
                const p = ln.split(sep)
                if (p.length < 6) continue
                next.push({
                    title:   p[0],
                    url:     p[1],
                    author:  p[2],
                    feed:    p[3],
                    pubDate: parseInt(p[4]) || 0,
                    unread:  p[5] === "1"
                })
            }
            root.items = next
        }}
    }
    Process { id: reloadProc; onExited: root.refresh() }
    Process { id: markProc;   onExited: root.refresh() }

    Component.onCompleted: refresh()

    Timer {
        interval: 60000
        running: GlobalStates.sidebarRightOpen
        repeat: true
        onTriggered: root.refresh()
    }
    Timer {
        interval: 15 * 60 * 1000
        running: GlobalStates.sidebarRightOpen
        repeat: true
        onTriggered: root.reload()
    }
}
