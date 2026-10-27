pragma Singleton
import Quickshell

Singleton {
    id: root
    /**
     * @param { string } summary 
     * @returns { string }
     */
    function findSuitableMaterialSymbol(summary = "") {
        const defaultType = 'chat';
        if (summary.length === 0) return defaultType;

        const keywordsToTypes = {
            'reboot': 'restart_alt',
            'record': 'screen_record',
            'battery': 'power',
            'power': 'power',
            'screenshot': 'screenshot_monitor',
            'welcome': 'waving_hand',
            'time': 'scheduleb',
            'download finished': 'download_done',
            'download started': 'downloading',
            'download failed': 'error',
            'download': 'download',
            'installed': 'download',
            'configuration reloaded': 'reset_wrench',
            'unable': 'question_mark',
            "couldn't": 'question_mark',
            'config': 'reset_wrench',
            'update': 'update',
            'ai response': 'neurology',
            'control': 'settings',
            'upsca': 'compare',
            'music': 'queue_music',
            'install': 'deployed_code_update',
            'input': 'keyboard_alt',
            'preedit': 'keyboard_alt',
            'startswith:file': 'folder_copy', // Declarative startsWith check
        };

        const lowerSummary = summary.toLowerCase();

        for (const [keyword, type] of Object.entries(keywordsToTypes)) {
            if (keyword.startsWith('startswith:')) {
                const startsWithKeyword = keyword.replace('startswith:', '');
                if (lowerSummary.startsWith(startsWithKeyword)) {
                    return type;
                }
            } else if (lowerSummary.includes(keyword)) {
                return type;
            }
        }

        return defaultType;
    }

    /**
     * @param { number | string | Date } timestamp 
     * @returns { string }
     */
    function getFriendlyNotifTimeString(timestamp) {
        if (!timestamp) return '';
        const messageTime = new Date(timestamp);
        const now = new Date();
        const diffMs = now.getTime() - messageTime.getTime();

        // Less than 1 minute
        if (diffMs < 60000)
            return 'Now';

        // Same day - show relative time
        if (messageTime.toDateString() === now.toDateString()) {
            const diffMinutes = Math.floor(diffMs / 60000);
            const diffHours = Math.floor(diffMs / 3600000);

            if (diffHours > 0) {
                return `${diffHours}h`;
            } else {
                return `${diffMinutes}m`;
            }
        }

        // Yesterday
        if (messageTime.toDateString() === new Date(now.getTime() - 86400000).toDateString())
            return 'Yesterday';

        // Older dates
        return Qt.formatDateTime(messageTime, "MMMM dd");
    }

    function processNotificationBody(body, appName) {
        let processedBody = body
        
        // Clean Chromium-based browsers notifications - remove first line
        if (appName) {
            const lowerApp = appName.toLowerCase()
            const chromiumBrowsers = [
                "brave", "chrome", "chromium", "vivaldi", "opera", "microsoft edge"
            ]

            if (chromiumBrowsers.some(name => lowerApp.includes(name))) {
                const lines = body.split('\n\n')

                if (lines.length > 1 && lines[0].startsWith('<a')) {
                    processedBody = lines.slice(1).join('\n\n')
                }
            }
        }

        processedBody = processedBody.replace(/<img/gi, '\n\n<img');

        return root.formatBody(processedBody)
    }

    /// Light formatting for bodies that arrive as text with markup in it.
    /// KDE Connect double-escapes what the phone sends ("&lt;br/&gt;",
    /// "&lt;b&gt;"), so the tags showed literally. Only a safe set is
    /// unescaped - links and images stay text, so a notification cannot
    /// inject them. Then chat-style markdown and bare URLs.
    function formatBody(text) {
        let t = String(text ?? "");
        // 1. Escaped safe tags -> real tags.
        t = t.replace(/&lt;(\/?)(b|i|u|s|em|strong|code|br)\s*\/?&gt;/gi,
            (m, close, tag) => tag.toLowerCase() === "br" ? "<br/>" : `<${close}${tag.toLowerCase()}>`);
        // 2. Empty pairs, e.g. "<b></b>" from an empty bold span.
        t = t.replace(/<(b|i|u|s|em|strong|code)>\s*<\/\1>/gi, "");
        // 3. Markdown, outside existing tags only (split keeps tags intact).
        t = t.split(/(<[^>]+>)/).map(part => part.startsWith("<") ? part : part
            .replace(/`([^`\n]+)`/g, "<code>$1</code>")
            .replace(/\*\*([^*\n]+)\*\*/g, "<b>$1</b>")
            .replace(/~~([^~\n]+)~~/g, "<s>$1</s>")
            .replace(/(^|[\s(])\*([^*\s][^*\n]*?)\*(?=[\s).,!?]|$)/g, "$1<i>$2</i>")
            .replace(/(^|[\s(])(https?:\/\/[^\s<>"')]+)/g, '$1<a href="$2">$2</a>')
        ).join("");
        // 4. A body already carrying its own <a> must not get links inside links.
        return t.replace(/<a href="([^"]+)">(<a [^>]+>)([^<]*)<\/a><\/a>/g, "$2$3</a>");
    }
}
