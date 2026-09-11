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
    function fetchToFileCommand(url, targetPath, opts) {
        const o = opts ?? {};
        const ua = o.userAgent ?? root.defaultDownloadUserAgent;
        const timeout = o.timeout ?? 30;
        return `mkdir -p ${root.shQuote(root.parentDirectory(targetPath))} && `
             + `curl -sL --max-time ${timeout} -A ${root.shQuote(ua)} `
             + `-o ${root.shQuote(targetPath)} ${root.shQuote(url)}`;
    }
}
