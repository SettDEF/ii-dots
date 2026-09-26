pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

/*
 * QUARRY, OVER ONE SOCKET, FOR THE LIFE OF THE SHELL.
 *
 * The wallpaper picker used to reach quarry by spawning `bash -c` with a
 * helper script for every page: a process, a socat, a JSON parse and a pipe
 * teardown per scroll — forty to eighty milliseconds of nothing but ceremony,
 * request/response only, with no way for the daemon to say anything on its own.
 *
 * This is the connection quarry's own UI uses, ported: one long-lived unix
 * socket, newline-delimited JSON frames, every call answered by id so a slow
 * `items` can never be mistaken for the answer to a later `query`. Queries come
 * back in single-digit milliseconds and the daemon can push — a crawl
 * finishing, new rows arriving — instead of being polled.
 *
 * The awkward parts are all load-bearing and were learned the hard way in
 * quarry's client; each one is commented where it happens.
 */
Singleton {
    id: root

    readonly property string socketPath: Quickshell.env("QUARRY_SOCK")
        || `${Quickshell.env("XDG_RUNTIME_DIR") || "/tmp"}/quarry/sock`

    property bool connected: false
    property string backend: ""
    property int daemonItems: 0
    property string error: ""

    signal event(string name, var payload)
    signal ready

    property int _nextId: 1
    property var _pending: ({})
    property var _deadlines: ({})

    // ── the wire ────────────────────────────────────────────────────────────

    function call(method, params, callback) {
        if (!root.connected) {
            if (callback)
                callback("not connected", null);
            return -1;
        }
        const id = root._nextId++;
        root._pending[id] = callback;
        // Generous on purpose: a cold thumbnail is a network fetch and `more`
        // crawls live sources before it answers.
        root._deadlines[id] = Date.now() + 60000;

        const socket = socketLoader.item;
        if (!socket) {
            delete root._pending[id];
            delete root._deadlines[id];
            if (callback)
                callback("not connected", null);
            return -1;
        }
        socket.write(JSON.stringify({ t: "req", id: id, m: method, p: params || {} }) + "\n");
        socket.flush();
        return id;
    }

    function _dispatch(line) {
        let frame;
        try {
            frame = JSON.parse(line);
        } catch (e) {
            return;
        }
        if (frame.t === "ev") {
            root.event(frame.m, frame.p);
            return;
        }
        const callback = root._pending[frame.id];
        delete root._pending[frame.id];
        delete root._deadlines[frame.id];
        if (callback)
            callback(frame.ok ? null : (frame.err || "error"), frame.p || null);
    }

    /*
     * A request that is never answered.
     *
     * A unix socket whose peer has gone does not always report itself closed:
     * the daemon restarts, `connected` stays true, and every call is written
     * into a socket nobody reads. Nothing fails — the tab just stops filling
     * in, which looks like a bug in the view. So every call carries a deadline,
     * and several expiring at once means the connection is gone rather than a
     * source being slow.
     */
    property Timer _watchdog: Timer {
        interval: 2000
        running: true
        repeat: true
        onTriggered: {
            const now = Date.now();
            let expired = 0;
            for (const id in root._deadlines) {
                if (root._deadlines[id] > now)
                    continue;
                const callback = root._pending[id];
                delete root._pending[id];
                delete root._deadlines[id];
                expired++;
                if (callback)
                    callback("timed out", null);
            }
            if (expired >= 3 || (expired > 0 && Object.keys(root._pending).length === 0))
                root.reconnect();
        }
    }

    function reconnect() {
        root.connected = false;
        root.backend = "";
        root._pending = ({});
        root._deadlines = ({});
        socketLoader.active = false;
        Qt.callLater(function () {
            socketLoader.active = true;
        });
    }

    /*
     * The socket is rebuilt, not reopened.
     *
     * Quickshell's Socket does not come back once its peer has gone — setting
     * `connected = true` again is accepted and does nothing. Recreating the
     * object is what actually reconnects.
     */
    property Loader _socket: Loader {
        id: socketLoader
        active: true

        sourceComponent: Socket {
            path: root.socketPath
            connected: true

            onConnectionStateChanged: {
                if (connected) {
                    root.error = "";
                    root.connected = true;
                    // One turn later: this signal arrives while the Loader is
                    // still creating the object, so `socketLoader.item` is null
                    // and a handshake sent from here goes nowhere.
                    Qt.callLater(root.hello);
                } else {
                    root.connected = false;
                    root.backend = "";
                    root._pending = ({});
                    root._deadlines = ({});
                }
            }

            onError: err => {
                root.error = `socket error ${err}`;
                root.connected = false;
            }

            parser: SplitParser {
                splitMarker: "\n"
                onRead: line => root._dispatch(line)
            }
        }
    }

    function hello() {
        root.call("hello", { client: "ii-skwdwall", protocol: 1 }, function (err, payload) {
            if (err) {
                root.error = err;
                return;
            }
            root.backend = payload.backend;
            root.daemonItems = payload.items;
            root.ready();
        });
    }

    /*
     * Reconnect until it works, not once.
     *
     * Toggling `active` false and true inside one handler is collapsed by the
     * property system into no change at all, so a single attempt did nothing.
     * Driven by `running` instead, across two turns of the event loop.
     */
    // Backs off to 30 s while the daemon is down; poke() when something needs it now.
    function poke() {
        root._retry.interval = 1500;
        if (!root.connected) root._retry.restart();
    }
    onConnectedChanged: if (connected) root._retry.interval = 1500
    property Timer _retry: Timer {
        interval: 1500
        repeat: true
        running: !root.connected
        onTriggered: {
            interval = Math.min(30000, interval * 2);
            socketLoader.active = false;
            Qt.callLater(function () {
                socketLoader.active = true;
            });
        }
    }

    // ── what the wallpaper picker asks for ──────────────────────────────────

    /*
     * A page of rows, shaped the way the picker already parses.
     *
     * The same object the Wallhaven API returns — `data[]` and `meta` — so the
     * dedupe, the pagination and the palette glow around it are untouched. The
     * difference is where it comes from and how fast: quarry's catalogue,
     * across every source it crawls, with thumbnails handed over as local
     * `file://` paths that are already the right size and already decoded once.
     */
    function page(query, pageNo, limit, callback) {
        const perPage = limit || 24;
        const offset = Math.max(0, (pageNo - 1) * perPage);

        root.call("query", { q: query }, function (err, result) {
            if (err || !result) {
                callback(err || "no result", null);
                return;
            }

            const total = result.count || 0;

            // A short page means the catalogue has not been asked to look yet,
            // not that there is nothing — crawl, then ask again. Without this a
            // query nobody has run returns the handful of rows that happened to
            // be there and reads as an empty source.
            if (total - offset < perPage) {
                root.call("more", { q: query, pages: 2 }, function () {
                    root._fetchPage(query, offset, perPage, pageNo, callback);
                });
                return;
            }
            root._fetchPage(query, offset, perPage, pageNo, callback);
        });
    }

    function _fetchPage(query, offset, perPage, pageNo, callback) {
        root.call("query", { q: query }, function (err, result) {
            if (err || !result) {
                callback(err || "no result", null);
                return;
            }
            const total = result.count || 0;
            root.call("items", { queryId: 0, offset: offset, limit: perPage }, function (e2, page) {
                if (e2 || !page) {
                    callback(e2 || "no items", null);
                    return;
                }
                root._withThumbs(page.items || [], total, pageNo, perPage, callback);
            });
        });
    }

    /// Thumbnails for a whole page in ONE call: the daemon fetches what it is
    /// missing in parallel and answers with local paths for everything it has.
    /// Asking per row is what made the old bridge feel slow.
    function _withThumbs(items, total, pageNo, perPage, callback) {
        if (items.length === 0) {
            callback(null, { data: [], meta: { current_page: pageNo, last_page: pageNo, total: total } });
            return;
        }
        const ids = items.map(i => i.id);
        root.call("thumbs", { ids: ids, size: root.thumbSize }, function (err, payload) {
            const ready = (payload && payload.thumbs) || {};
            const data = items.map(function (item) {
                const local = ready[item.id] || "";
                return {
                    id: item.id,
                    // A booru id is not a title; fall back to the source rather
                    // than to an empty caption.
                    title: item.title || item.slug || item.source || "",
                    path: item.url || "",
                    thumbs: {
                        small: local.length > 0 ? "file://" + local : (item.thumb || ""),
                        original: item.sample || item.url || ""
                    },
                    // Quarry stores one dominant colour where Wallhaven gives
                    // five; the picker slices to five, so this is a shorter
                    // list rather than a broken one.
                    colors: item.dominant ? [item.dominant] : [],
                    kind: item.family === "video" ? "vid" : "pic",
                    source: item.source || "",
                    width: item.w || 0,
                    height: item.h || 0
                };
            });
            callback(null, {
                data: data,
                meta: {
                    current_page: pageNo,
                    last_page: Math.max(1, Math.ceil(total / perPage)),
                    total: total
                }
            });
        });
    }

    /// The rung the picker draws at. One step of quarry's ladder, so asking for
    /// it is a cache hit rather than a resize.
    property int thumbSize: 640
}
