pragma Singleton
pragma ComponentBehavior: Bound
import qs.modules.common
import qs.modules.common.functions
import QtQuick
import Quickshell
import Quickshell.Io

/**
 * Per-app notification sounds.
 *
 * A sound reference is either a freedesktop event id ("message-new-instant"),
 * played through canberra so it honours the user's sound theme, or an absolute
 * path to a file added by scripts/notifications/sound-add.sh. Which one it is
 * is decided by the leading slash, so no second field has to be kept in sync.
 *
 * Per-app entries live in their own file rather than beside the mute map,
 * which is written from a different code path on a different trigger.
 */
Singleton {
    id: root

    readonly property string dir: `${Directories.state}/quickshell/notification-sounds`
    readonly property string mapPath: `${Directories.state}/quickshell/app-sounds.json`
    readonly property string addScript:
        FileUtils.trimFileProtocol(`${Directories.scriptPath}/notifications/sound-add.sh`)

    /// appName -> sound reference. Absent means "use the global default".
    property var appSounds: ({})
    /// Event ids from the active sound theme, plus files the user added.
    property var library: []
    property bool ready: false

    function isFile(ref) { return !!ref && ref.startsWith("/"); }

    /// What a given app should play. Falls back to the global setting.
    function soundFor(appName) {
        const own = appName ? root.appSounds[appName] : "";
        if (own && own.length > 0) return own;
        return Config?.options.notifications.soundName ?? "message-new-instant";
    }

    function setAppSound(appName, ref) {
        if (!appName) return;
        const m = Object.assign({}, root.appSounds);
        if (!ref || ref.length === 0) delete m[appName]; else m[appName] = ref;
        root.appSounds = m;
        mapView.setText(JSON.stringify(root.appSounds, null, 2));
    }

    /// Plays a reference. Quoting matters: app names and file names are not ours.
    function play(ref) {
        if (!ref || ref.length === 0) return;
        const q = String(ref).replace(/'/g, "'\\''");
        const cmd = root.isFile(ref)
            ? `pw-play '${q}' 2>/dev/null || paplay '${q}' 2>/dev/null`
            : `canberra-gtk-play -i '${q}' 2>/dev/null`
              + ` || paplay /usr/share/sounds/freedesktop/stereo/message.oga 2>/dev/null`;
        Quickshell.execDetached(["bash", "-c", cmd]);
    }

    function playForApp(appName) { root.play(root.soundFor(appName)); }

    /// Fetch a sound from a URL. Validation lives in the script, which refuses
    /// anything without an audio stream — a saved error page is silent exactly
    /// where you would not notice.
    signal added(string name)
    signal addFailed(string reason)
    function addFromUrl(url, name) {
        if (!url || url.length === 0) return;
        addProc.buffer = "";
        addProc.command = ["bash", "-c",
            `'${root.addScript}' '${String(url).replace(/'/g, "'\\''")}'`
            + (name && name.length > 0 ? ` '${String(name).replace(/'/g, "'\\''")}'` : "")];
        addProc.running = true;
    }

    function refresh() { libraryProc.running = true; }

    Process {
        id: addProc
        property string buffer: ""
        stdout: SplitParser { onRead: data => addProc.buffer += data + "\n" }
        stderr: SplitParser { onRead: data => addProc.buffer += data + "\n" }
        onExited: exitCode => {
            if (exitCode === 0) {
                const m = addProc.buffer.match(/^added: (.+)$/m);
                root.added(m ? m[1] : "");
                root.refresh();
            } else {
                root.addFailed(addProc.buffer.trim().split("\n").pop() ?? "failed");
            }
        }
    }

    // Theme events and added files in one list, each "label\tref".
    Process {
        id: libraryProc
        running: true
        command: ["bash", "-c",
            `for f in /usr/share/sounds/freedesktop/stereo/*.oga; do `
            + `n=$(basename "$f" .oga); printf '%s\\t%s\\n' "$n" "$n"; done; `
            + `'${root.addScript}' --list 2>/dev/null`]
        property string buffer: ""
        stdout: SplitParser { onRead: data => libraryProc.buffer += data + "\n" }
        onExited: {
            const out = [];
            for (const line of libraryProc.buffer.split("\n")) {
                const parts = line.split("\t");
                if (parts.length === 2 && parts[0].length > 0)
                    out.push({ label: parts[0], ref: parts[1] });
            }
            libraryProc.buffer = "";
            root.library = out;
            root.ready = true;
        }
    }

    FileView {
        id: mapView
        path: Qt.resolvedUrl(root.mapPath)
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            try {
                const o = JSON.parse(mapView.text());
                if (o && typeof o === "object") root.appSounds = o;
            } catch (e) { /* malformed: keep what we have */ }
        }
        onLoadFailed: root.appSounds = ({})
    }
}
