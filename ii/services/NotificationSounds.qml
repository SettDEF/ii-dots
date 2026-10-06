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

    // Directories.state is already .../state/quickshell — adding it again gave
    // .../state/quickshell/quickshell and the map never loaded.
    // The sound files' directory is the script's business alone; duplicating
    // it here would be a second place for it to be wrong.
    readonly property string mapPath:
        FileUtils.trimFileProtocol(`${Directories.state}/app-sounds.json`)
    readonly property string addScript:
        FileUtils.trimFileProtocol(`${Directories.scriptPath}/notifications/sound-add.sh`)

    /// appName -> sound reference, or { sound, pan } once a pan is set. A bare
    /// string is the older shape and still reads. Absent = use the defaults.
    property var appSounds: ({})
    /// Event ids from the active sound theme, plus files the user added.
    property var library: []
    property bool ready: false

    function isFile(ref) { return !!ref && ref.startsWith("/"); }

    function _entry(appName) {
        const e = appName ? root.appSounds[appName] : null;
        if (typeof e === "string") return { sound: e, pan: null };
        return { sound: e?.sound ?? "", pan: typeof e?.pan === "number" ? e.pan : null };
    }

    /// The app's own choice, "" when it follows the default.
    function ownSound(appName) { return root._entry(appName).sound; }
    /// The app's own pan, null when it follows the default.
    function ownPan(appName) { return root._entry(appName).pan; }

    /// What a given app should play. Falls back to the global setting.
    function soundFor(appName) {
        const own = root.ownSound(appName);
        if (own.length > 0) return own;
        return Config?.options.notifications.soundName ?? "message-new-instant";
    }

    /// -1 (left) .. 1 (right).
    function panFor(appName) {
        return root.ownPan(appName) ?? Config?.options.notifications.soundPan ?? 0;
    }

    function _save(appName, sound, pan) {
        if (!appName) return;
        const m = Object.assign({}, root.appSounds);
        if (!sound && pan === null) delete m[appName];
        else m[appName] = pan === null ? sound : { sound: sound ?? "", pan };
        root.appSounds = m;
        mapView.setText(JSON.stringify(root.appSounds, null, 2));
    }

    function setAppSound(appName, ref) {
        root._save(appName, ref ?? "", root.ownPan(appName));
    }

    function setAppPan(appName, pan) {
        root._save(appName, root.ownSound(appName), pan);
    }

    function resetApp(appName) { root._save(appName, "", null); }

    /// Plays a reference, placed from -1 (left) to 1 (right). Quoting matters:
    /// app names and file names are not ours.
    ///
    /// Neither pw-play nor canberra can pan, so a panned sound is mixed to mono
    /// and re-split by ffmpeg with a constant-power law (the two gains always
    /// square-sum to 1, so it does not get quieter toward the middle of the
    /// range), then played by pw-play. Centre skips all of it and plays the
    /// original, stereo and untouched.
    function play(ref, pan) {
        if (!ref || ref.length === 0) return;
        const q = String(ref).replace(/'/g, "'\\''");
        const p = Math.max(-1, Math.min(1, Number(pan) || 0));
        const plain = root.isFile(ref)
            ? `pw-play '${q}' 2>/dev/null || paplay '${q}' 2>/dev/null`
            : `canberra-gtk-play -i '${q}' 2>/dev/null`
              + ` || paplay /usr/share/sounds/freedesktop/stereo/message.oga 2>/dev/null`;
        if (Math.abs(p) < 0.01) {
            Quickshell.execDetached(["bash", "-c", plain]);
            return;
        }
        const a = (p + 1) * Math.PI / 4;
        const left = Math.cos(a).toFixed(4), right = Math.sin(a).toFixed(4);
        const file = root.isFile(ref) ? q : `/usr/share/sounds/freedesktop/stereo/${q}.oga`;
        // A temp file, not a pipe: a streamed WAV has no length in its header.
        Quickshell.execDetached(["bash", "-c",
            `t=$(mktemp --suffix=.wav) && trap 'rm -f "$t"' EXIT; `
            + `if ffmpeg -v quiet -y -i '${file}' -af 'aformat=channel_layouts=mono,`
            + `pan=stereo|c0=${left}*c0|c1=${right}*c0' "$t" 2>/dev/null`
            + ` && pw-play "$t" 2>/dev/null; then :; else ${plain}; fi`]);
    }

    function playForApp(appName) {
        root.play(root.soundFor(appName), root.panFor(appName));
    }

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
        // Absent until the first per-app sound is set, which is normal and
        // not worth a warning on every load.
        printErrors: false
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
