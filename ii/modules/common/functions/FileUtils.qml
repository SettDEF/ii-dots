pragma Singleton
import Quickshell

Singleton {
    id: root

    /**
     * Icon source for a desktop entry's Icon= value.
     *
     * Icon= is allowed to be a literal file path, not just a theme name —
     * Lutris writes one cover-art path per game. Quickshell.iconPath only
     * resolves theme names, so those paths silently became image-missing.
     *
     * @param {string} name  theme name or absolute path
     * @param {string} fallback  theme name used when `name` resolves to nothing
     * @returns {string} a source usable by IconImage/Image
     */
    function iconSource(name, fallback) {
        const fb = fallback ?? "";
        if (!name || name.length === 0)
            return Quickshell.iconPath(fb, "");
        if (name.startsWith("file:"))
            return name;
        if (name.startsWith("/"))
            return "file://" + name;
        return Quickshell.iconPath(name, fb);
    }

    /**
     * Trims the File protocol off the input string
     * @param {string} str
     * @returns {string}
     */
    /**
     * A path as a file:// address that keeps ? # % and spaces in file names (a bare path is read as
     * an address, so "Forgive Me? .png" lost everything after its ?). Other addresses pass as they are.
     */
    function fileUrl(path) {
        if (!path) return "";
        const s = String(path);
        if (/^[a-z][a-z0-9+.-]*:\/\//i.test(s) && !s.startsWith("file://")) return s;
        const p = s.startsWith("file://") ? s.slice(7) : s;
        return "file://" + p.split("/").map(encodeURIComponent).join("/");
    }

    function trimFileProtocol(str) {
        let s = str;
        if (typeof s !== "string") s = str.toString(); // Convert to string if it's an url or whatever
        return s.startsWith("file://") ? s.slice(7) : s;
    }

    /**
     * Extracts the file name from a file path
     * @param {string} str
     * @returns {string}
     */
    function fileNameForPath(str) {
        if (typeof str !== "string") return "";
        const trimmed = trimFileProtocol(str);
        return trimmed.split(/[\\/]/).pop();
    }

    /**
     * Extracts the folder name from a directory path
     * @param {string} str
     * @returns {string}
     */
    function folderNameForPath(str) {
        if (typeof str !== "string") return "";
        const trimmed = trimFileProtocol(str);
        // Remove trailing slash if present
        const noTrailing = trimmed.endsWith("/") ? trimmed.slice(0, -1) : trimmed;
        if (!noTrailing) return "";
        return noTrailing.split(/[\\/]/).pop();
    }

    /**
     * Removes the file extension from a file path or name
     * @param {string} str
     * @returns {string}
     */
    function trimFileExt(str) {
        if (typeof str !== "string") return "";
        const trimmed = trimFileProtocol(str);
        const lastDot = trimmed.lastIndexOf(".");
        if (lastDot > -1 && lastDot > trimmed.lastIndexOf("/")) {
            return trimmed.slice(0, lastDot);
        }
        return trimmed;
    }

    /**
     * Returns the parent directory of a given file path
     * @param {string} str
     * @returns {string}
     */
    function parentDirectory(str) {
        if (typeof str !== "string") return "";
        const trimmed = trimFileProtocol(str);
        const parts = trimmed.split(/[\\/]/);
        if (parts.length <= 1) return "";
        parts.pop();
        return parts.join("/");
    }

    /**
     * Single-quotes a string for safe interpolation into a `bash -c` command.
     *
     * Every caller that built a download command was wrapping values in single
     * quotes by hand, which holds right up until a URL or filename contains one
     * — booru filenames routinely do. Closing the quote, escaping the literal,
     * and reopening is the only form that survives arbitrary input.
     * @param {string} str
     * @returns {string}
     */
    function shQuote(str) {
        return "'" + String(str ?? "").replace(/'/g, "'\\''") + "'";
    }

    /**
     * Builds the `mkdir -p … && curl …` half of a download command.
     *
     * Three call sites had grown their own copy of this — the booru download
     * item, the wallpaper apply, and the wallpaper save — each with slightly
     * different flags, its own user-agent literal, and its own quoting. The
     * success action differs per caller, so that stays with the caller: append
     * `&& whatever` to the returned string.
     * @param {string} url
     * @param {string} targetPath  absolute destination path
     * @param {object} [opts]      { userAgent, timeout }
     * @returns {string}
     */
    property string defaultDownloadUserAgent: "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/125.0.0.0 Safari/537.36"
    /// Like fetchToFileCommand, but patient: for "apply this wallpaper" while
    /// the network is down or flaky. It keeps retrying until the network is
    /// back (up to `waitSeconds`, default 300), gives up on an attempt only
    /// when the transfer STALLS (under 1 KB/s for 20 s) rather than after a
    /// fixed time — a big image on a slow link is not a failure — and writes
    /// to a temp file that is renamed only when complete, so a cut-off attempt
    /// never leaves a half image behind to be applied.
    /// `waitingNotice`: a command run once when the first attempt fails.
    function fetchToFileWaitingCommand(url, targetPath, opts) {
        const o = opts ?? {};
        const ua = o.userAgent ?? root.defaultDownloadUserAgent;
        const wait = o.waitSeconds ?? 300;
        const tmp = targetPath + ".part";
        const notice = o.waitingNotice ? `${o.waitingNotice}; ` : "";
        return `mkdir -p ${root.shQuote(root.parentDirectory(targetPath))} && `
             + `[ -s ${root.shQuote(targetPath)} ] || { `
             + `deadline=$(( $(date +%s) + ${wait} )); warned=0; `
             + `until curl -sLf --connect-timeout 10 --speed-limit 1024 --speed-time 20 -A ${root.shQuote(ua)} `
             + `-o ${root.shQuote(tmp)} ${root.shQuote(url)}; do `
             + `rm -f ${root.shQuote(tmp)}; `
             + `[ $(date +%s) -ge $deadline ] && exit 1; `
             + `[ $warned = 0 ] && { warned=1; ${notice}true; }; `
             + `sleep 4; done; mv -f ${root.shQuote(tmp)} ${root.shQuote(targetPath)}; }`;
    }

    function fetchToFileCommand(url, targetPath, opts) {
        const o = opts ?? {};
        const ua = o.userAgent ?? root.defaultDownloadUserAgent;
        const timeout = o.timeout ?? 30;
        return `mkdir -p ${root.shQuote(root.parentDirectory(targetPath))} && `
             + `curl -sL --max-time ${timeout} -A ${root.shQuote(ua)} `
             + `-o ${root.shQuote(targetPath)} ${root.shQuote(url)}`;
    }
}
