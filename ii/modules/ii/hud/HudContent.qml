pragma ComponentBehavior: Bound
import qs
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import qs.modules.ii.sidebarRight
import qs.modules.ii.sidebarRight.notifications
import qs.modules.ii.sidebarRight.calendar
import qs.modules.ii.sidebarRight.todo
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import QtQuick.Shapes
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import Quickshell.Services.Mpris

Item {
    id: root
    implicitHeight: hudBg.implicitHeight
    implicitWidth:  parent?.width ?? 860

    // Hard cap on the scrollable page area — set by Hud.qml from the
    // screen height so the HUD can never grow taller than the display.
    property int maxContentHeight: 800

    // The StackLayout can latch a stale, too-tall page height on the very
    // first frame (before layouts settle), leaving the HUD oversized until
    // a tab switch. Bumping this a few times right after open forces the
    // page-height binding to re-read once everything has settled.
    property int _relayoutTick: 0
    // Stays false until the page layout has settled. The HUD enter
    // animation waits for this, so the HUD never fades in at a stale
    // (too-tall) size and visibly snaps down.
    property bool ready: false
    Timer {
        interval: 40; repeat: true; running: true
        property int _n: 0
        onTriggered: {
            root._relayoutTick++
            if (++_n >= 3) { running = false; root.ready = true }
        }
    }

    // _gone guard: HUD is a transient lazy-loaded component, but the system
    // Process objects below tick on a 1 s timer. Closing the HUD while a
    // Process is mid-flight makes Process::onFinished fire on a destroyed
    // scope object → V4 GC crash. Every handler bails when _gone is true.
    property bool _gone: false
    Component.onDestruction: _gone = true

    // ── System data ───────────────────────────────────────────────────────
    property var  cpuHistory:    []
    property var  ramHistory:    []
    property var  gpuHistory:    []
    property var  netUpHistory:  []
    property var  netDnHistory:  []
    property var  diskHistory:   []
    property real cpuVal:    0
    property real ramVal:    0
    property real gpuVal:    0
    property real gpuMem:    0
    property real netUp:     0
    property real netDn:     0
    property real diskUsed:  0
    property real diskTotal: 1
    property var  topProcs:  []

    // Per-device storage: [{name, model, sizeGB, readBps, writeBps, tempC}, …]
    // Driven by /sys/block/<dev>/stat + /sys/class/nvme/<dev>/hwmon*/temp1_input.
    // Rates are computed from successive deltas in disksProc.onStreamFinished;
    // first sample shows 0 B/s, every subsequent sample is real.
    property var  disks: []
    property var  _prevDiskStat: ({})   // {name: {readSec, writeSec, ts}}

    readonly property string lastKey:  KeyTracker.lastKey
    readonly property real   xpTotal: KeyTracker.xpTotal
    readonly property int    xpLevel: KeyTracker.xpLevel
    property int    _keyPresses: 0
    property int    _mouseClicks:0
    property var    wsColors: ({})

    readonly property int maxHistory: 60
    function _push(arr, v) {
        const a = arr.concat([v])
        return a.length > maxHistory ? a.slice(a.length - maxHistory) : a
    }

    // Fixed per-metric colors
    readonly property color colCpu:   Appearance.colors.colPrimary
    readonly property color colGpu:   Appearance.colors.colTertiary
    readonly property color colRam:   Appearance.colors.colSecondary
    readonly property color colNetUp: Appearance.m3colors.m3tertiary
    readonly property color colNetDn: Appearance.m3colors.m3secondary
    readonly property color colDisk:  Appearance.m3colors.m3error
    // Brand red used by the Last.fm UI accents (logo, loading dot, scrobble count).
    readonly property color colLastFm: "#d51007"

    function procAccent(cpu) {
        if (cpu >= 50) return Appearance.m3colors.m3error
        if (cpu >= 20) return Appearance.m3colors.m3tertiary
        return Appearance.colors.colPrimary
    }

    // ── Tab state ─────────────────────────────────────────────────────────
    // mainTab mirrors the shared GlobalStates value — the bar's HUD-tab
    // PillTabBar drives it while the HUD is open. The internal tab bar
    // (below, shown only when the bar is hidden) writes the same state.
    property int mainTab:            GlobalStates.hudActiveTab
    // 7 content pages collapse into 3 main tab groups; the blob sub-tab
    // tray below the bar reaches each group's pages.
    //   Home   = {Dashboard 0, Essentials 6, Screen Time 5}
    //   System = {Performance 1, Gaming 2}    (was "Essentials" at 1)
    //   Hub    = {Media 4, Settings 3}
    readonly property int mainGroup: (mainTab === 0 || mainTab === 5 || mainTab === 6) ? 0
                                   : (mainTab === 1 || mainTab === 2) ? 1 : 2
    // Sub-tab indices mirror GlobalStates — the bar hosts the sub-tab
    // selector (blob tray below the bar) and writes these.
    property int perfTab:            GlobalStates.hudPerfTab
    property int gamingTab:          GlobalStates.hudGamingTab
    property int mediaTab:           GlobalStates.hudMediaTab
    property int _displayedTab:      0
    property int _displayedPerfTab:  0
    property int _displayedMediaTab: 0

    property int pinnedTab: 0
    // Persisted sub-tab indices — restored alongside pinnedTab on HUD open.
    // Loaded from ~/.local/share/qs-hud-tabs.json (single JSON write per
    // change). Kept separate from GlobalStates so the values survive even
    // when the GlobalStates singleton resets between sessions.
    property int _persistedPerfTab:   0
    property int _persistedGamingTab: 0
    property int _persistedMediaTab:  0

    Process { id: pinnedTabLoadProc; stdout: StdioCollector { onStreamFinished: {
        if (root._gone) return
        const v = parseInt(text.trim())
        if (!isNaN(v) && v >= 0 && v <= 6) root.pinnedTab = v
    }}}
    Process { id: pinnedTabSaveProc }
    function setPinnedTab(idx) {
        pinnedTab = idx
        pinnedTabSaveProc.exec({ command: ["bash","-c",`echo ${idx} > ~/.local/share/qs-hud-pinned-tab`] })
    }

    // Auto-persist all tab + sub-tab indices to one JSON file. Called from
    // each onXxxTabChanged handler, so every navigation writes the current
    // state. On HUD open we restore from this file so the user lands back
    // exactly where they left off (incl. sub-tab inside System / Media).
    Process { id: tabStateLoadProc; stdout: StdioCollector { onStreamFinished: {
        if (root._gone) return
        try {
            const s = JSON.parse(text.trim() || "{}")
            if (Number.isInteger(s.perf))   root._persistedPerfTab   = s.perf
            if (Number.isInteger(s.gaming)) root._persistedGamingTab = s.gaming
            if (Number.isInteger(s.media))  root._persistedMediaTab  = s.media
        } catch (e) { /* corrupt file — ignore, defaults stay */ }
    }}}
    Process { id: tabStateSaveProc }
    function savePersistedTabs() {
        const state = {
            main:   root.mainTab,
            perf:   root.perfTab,
            gaming: root.gamingTab,
            media:  root.mediaTab,
        }
        tabStateSaveProc.exec({ command: ["bash","-c",
            `echo '${JSON.stringify(state)}' > ~/.local/share/qs-hud-tabs.json`] })
    }

    Connections {
        target: GlobalStates
        function onHudOpenChanged() {
            if (GlobalStates.hudOpen) {
                GlobalStates.hudActiveTab = root.pinnedTab
                GlobalStates.hudPerfTab   = root._persistedPerfTab
                GlobalStates.hudGamingTab = root._persistedGamingTab
                GlobalStates.hudMediaTab  = root._persistedMediaTab
            }
        }
    }

    // Fast tab switch: the old code faded the content OUT (80ms), then swapped
    // the page, then faded IN (160ms) — so you stared at a blank panel for 80ms
    // before the new tab even appeared. Now we swap the page immediately and
    // play one quick subtle fade-in, so the switch reads as instant.
    NumberAnimation {
        id: mainFadeIn
        target: contentStack; property: "opacity"
        from: 0.4; to: 1; duration: 70; easing.type: Easing.OutCubic
    }
    NumberAnimation {
        id: mediaFadeIn
        target: mediaContentStack; property: "opacity"
        from: 0.4; to: 1; duration: 70; easing.type: Easing.OutCubic
    }
    onMainTabChanged: {
        root._displayedTab = root.mainTab   // swap now, no fade-out wait
        mainFadeIn.restart()
        if (mainTab !== 1) GlobalStates.essentialsRadarOpen = false
        if (mainTab === 4 && lfmUsername && lfmApiKey) fetchLastFm()
        // Auto-pin the new tab so reopening the HUD lands here.
        setPinnedTab(mainTab)
        savePersistedTabs()
    }
    onMediaTabChanged: {
        root._displayedMediaTab = root.mediaTab
        mediaFadeIn.restart();
        if (mainTab === 4 && lfmUsername && lfmApiKey) fetchLastFm()
        savePersistedTabs()
    }
    onPerfTabChanged:   savePersistedTabs()
    onGamingTabChanged: savePersistedTabs()

    // ── Processes ─────────────────────────────────────────────────────────
    property var _prevCpuIdle:  -1
    property var _prevCpuTotal: -1

    Process { id: cpuProc; stdout: StdioCollector { onStreamFinished: {
        if (root._gone) return
        const p = text.trim().split(" "); if (p.length < 2) return
        const total = parseFloat(p[0]), idle = parseFloat(p[1])
        if (root._prevCpuTotal >= 0) {
            const dt = total - root._prevCpuTotal, di = idle - root._prevCpuIdle
            root.cpuVal = dt > 0 ? Math.round((1 - di/dt)*100) : 0
        }
        root._prevCpuTotal = total; root._prevCpuIdle = idle
        root.cpuHistory = root._push(root.cpuHistory, root.cpuVal)
    }}}
    Process { id: ramProc; stdout: StdioCollector { onStreamFinished: {
        if (root._gone) return
        const p = text.trim().split(" "); if (p.length < 2) return
        const t = parseFloat(p[0]), a = parseFloat(p[1])
        root.ramVal = t > 0 ? Math.round((1 - a/t)*100) : 0
        root.ramHistory = root._push(root.ramHistory, root.ramVal)
    }}}
    Process { id: gpuProc; stdout: StdioCollector { onStreamFinished: {
        if (root._gone) return
        const line = text.trim().replace(/,/g," ").replace(/\s+/g," "), p = line.split(" ")
        root.gpuVal = parseFloat(p[0])||0
        root.gpuMem = Math.round((parseFloat(p[1])||0)/(parseFloat(p[2])||1)*100)
        root.gpuHistory = root._push(root.gpuHistory, root.gpuVal)
    }}}
    property var _prevRx: -1; property var _prevTx: -1
    Process { id: netProc; stdout: StdioCollector { onStreamFinished: {
        if (root._gone) return
        const p = text.trim().split(" "); if (p.length < 2) return
        const rx = parseFloat(p[0]), tx = parseFloat(p[1])
        if (root._prevRx >= 0) {
            root.netDn = Math.max(0, Math.round((rx - root._prevRx)/1024))
            root.netUp = Math.max(0, Math.round((tx - root._prevTx)/1024))
        }
        root._prevRx = rx; root._prevTx = tx
        root.netDnHistory = root._push(root.netDnHistory, root.netDn)
        root.netUpHistory = root._push(root.netUpHistory, root.netUp)
    }}}
    Process { id: diskProc; stdout: StdioCollector { onStreamFinished: {
        if (root._gone) return
        const p = text.trim().split(/\s+/); if (p.length < 2) return
        root.diskUsed  = parseFloat(p[0])||0
        root.diskTotal = parseFloat(p[1])||1
        root.diskHistory = root._push(root.diskHistory, Math.round(root.diskUsed/root.diskTotal*100))
    }}}
    // Per-device storage reader. Reads NVMes, eMMC, and any sd*/sda-style
    // SATA/USB blocks. Output rows: name|model|sizeSectors|readSec|writeSec|tempMilliC.
    // Temperature only populated for nvme via /sys/class/nvme/<dev>/hwmon*/temp1_input
    // (the hwmon directory number varies per boot — globbing keeps the read stable).
    Process { id: disksProc; stdout: StdioCollector { onStreamFinished: {
        if (root._gone) return
        const now = Date.now()
        const out = []
        for (const line of text.trim().split("\n")) {
            const parts = line.split("|")
            if (parts.length < 6) continue
            const name      = parts[0]
            const model     = parts[1] || name
            const sectors   = parseInt(parts[2]) || 0
            const readSec   = parseInt(parts[3]) || 0
            const writeSec  = parseInt(parts[4]) || 0
            const tempMilli = parseInt(parts[5]) || 0
            // Sector = 512 bytes. /sys/block/<x>/size is in 512-byte sectors.
            const sizeGB = sectors * 512 / 1e9
            const tempC  = tempMilli / 1000
            // Δ vs last sample → bytes/sec.
            const prev = root._prevDiskStat[name]
            let readBps = 0, writeBps = 0
            if (prev) {
                const dtSec = Math.max(0.001, (now - prev.ts) / 1000)
                readBps  = Math.max(0, (readSec  - prev.readSec)  * 512) / dtSec
                writeBps = Math.max(0, (writeSec - prev.writeSec) * 512) / dtSec
            }
            root._prevDiskStat[name] = { readSec: readSec, writeSec: writeSec, ts: now }
            out.push({
                name: name, model: model, sizeGB: sizeGB,
                readBps: readBps, writeBps: writeBps, tempC: tempC,
            })
        }
        root.disks = out
    }}}
    Process { id: topProcsProc; stdout: StdioCollector { onStreamFinished: {
        if (root._gone) return
        const lines = text.trim().split("\n").filter(l => l.trim())
        root.topProcs = lines.map(l => { const p = l.trim().split(/\s+/); return { name: p[0]??"", cpu: p[1]??"0", mem: p[2]??"0" } })
    }}}
    Process { id: wsColorLoadProc; stdout: StdioCollector { onStreamFinished: {
        if (root._gone) return
        try { root.wsColors = JSON.parse(text.trim()) } catch(e) {}
    }}}
    Process { id: wsColorSaveProc }
    function saveWsColors() {
        wsColorSaveProc.exec({ command: ["bash","-c",`echo '${JSON.stringify(root.wsColors)}' > ~/.local/share/qs-workspace-colors.json`] })
    }

    // ── Last.fm ───────────────────────────────────────────────────────────
    property string lfmUsername:   ""
    // API key — read from ~/.secure/apikeys (LASTFM_API_KEY). The username
    // is not a secret and stays editable in ~/.local/share/qs-lastfm.conf.
    readonly property string lfmApiKey: ApiKeys.get("LASTFM_API_KEY")
    property var    lfmRecentTrack: null
    property var    lfmTopArtists: []
    property bool   lfmLoading:    false

    Process { id: lfmConfigProc; stdout: StdioCollector { onStreamFinished: {
        if (root._gone) return
        const lines = text.trim().split("\n")
        lines.forEach(l => {
            const [k, v] = l.split("=")
            if (k === "username") root.lfmUsername = v ?? ""
        })
        if (root.lfmUsername && root.lfmApiKey) root.fetchLastFm()
    }}}
    Process { id: lfmSaveProc }
    Process { id: lfmFetchProc; stdout: StdioCollector { onStreamFinished: {
        if (root._gone) return
        root.lfmLoading = false
        try {
            const j = JSON.parse(text.trim())
            const tracks = j?.recenttracks?.track
            if (tracks && tracks.length > 0) root.lfmRecentTrack = tracks[0]
        } catch(e) {}
    }}}
    Process { id: lfmArtistProc; stdout: StdioCollector { onStreamFinished: {
        if (root._gone) return
        try {
            const j = JSON.parse(text.trim())
            root.lfmTopArtists = j?.topartists?.artist?.slice(0, 5) ?? []
        } catch(e) {}
    }}}

    function fetchLastFm() {
        if (!lfmUsername || !lfmApiKey) return
        lfmLoading = true
        const u = encodeURIComponent(lfmUsername)
        lfmFetchProc.exec({ command: ["bash","-c",
            `curl -sf "https://ws.audioscrobbler.com/2.0/?method=user.getrecenttracks&user=${u}&api_key=${lfmApiKey}&format=json&limit=1"`] })
        lfmArtistProc.exec({ command: ["bash","-c",
            `curl -sf "https://ws.audioscrobbler.com/2.0/?method=user.gettopartists&user=${u}&api_key=${lfmApiKey}&format=json&limit=5&period=7day"`] })
    }
    function saveLastFmConfig() {
        lfmSaveProc.exec({ command: ["bash","-c",
            `printf 'username=%s\n' '${lfmUsername}' > ~/.local/share/qs-lastfm.conf`] })
    }

    Timer {
        interval: 2000; running: GlobalStates.hudOpen; repeat: true; triggeredOnStart: true
        onTriggered: {
            cpuProc.exec({  command: ["bash","-c","awk '/^cpu / {print $2+$3+$4+$5+$6+$7+$8, $5}' /proc/stat"] })
            ramProc.exec({  command: ["bash","-c","awk '/MemTotal/{t=$2} /MemAvailable/{a=$2} END{print t, a}' /proc/meminfo"] })
            gpuProc.exec({  command: ["bash","-c","echo \"$(cat /sys/class/drm/card1/device/gpu_busy_percent 2>/dev/null||echo 0) $(cat /sys/class/drm/card1/device/mem_info_vram_used 2>/dev/null||echo 0) $(cat /sys/class/drm/card1/device/mem_info_vram_total 2>/dev/null||echo 1)\""] })
            netProc.exec({  command: ["bash","-c","awk '/^ *(e|w)/{rx+=$2; tx+=$10} END{print rx, tx}' /proc/net/dev"] })
            diskProc.exec({ command: ["bash","-c","df / --output=used,size -BM | tail -1 | tr -d M"] })
            // Per-device disk telemetry (NVMe + eMMC + SATA/USB sd*).
            // Outputs one row per device: name|model|size|readSec|writeSec|tempMilliC.
            // Globbing /sys/class/nvme/.../hwmon*/ keeps temp read stable
            // across boots (hwmon number varies).
            disksProc.exec({ command: ["bash","-c",`
                for d in /sys/block/nvme*n1 /sys/block/mmcblk0 /sys/block/sd?; do
                    [ -e "$d" ] || continue
                    name=$(basename "$d")
                    model=$(cat "$d/device/model" 2>/dev/null | tr -d '\\n' | sed 's/  */ /g; s/ $//')
                    [ -z "$model" ] && model="$name"
                    size=$(cat "$d/size" 2>/dev/null)
                    rs=$(awk '{print $3}' "$d/stat" 2>/dev/null)
                    ws=$(awk '{print $7}' "$d/stat" 2>/dev/null)
                    temp=0
                    if [[ $name == nvme* ]]; then
                        base=\${name%n1}
                        t=$(cat /sys/class/nvme/$base/hwmon*/temp1_input 2>/dev/null | head -1)
                        [ -n "$t" ] && temp=$t
                    fi
                    echo "$name|$model|$size|$rs|$ws|$temp"
                done
            `] })
            topProcsProc.exec({ command: ["bash","-c","ps --no-headers -ax -o comm,%cpu,%mem --sort=-%cpu 2>/dev/null | head -7"] })
        }
    }
    Component.onCompleted: {
        wsColorLoadProc.exec({ command: ["bash","-c","cat ~/.local/share/qs-workspace-colors.json 2>/dev/null || echo '{}'"] })
        lfmConfigProc.exec({ command: ["bash","-c","cat ~/.local/share/qs-lastfm.conf 2>/dev/null || true"] })
        pinnedTabLoadProc.exec({ command: ["bash","-c","cat ~/.local/share/qs-hud-pinned-tab 2>/dev/null || echo '0'"] })
        tabStateLoadProc.exec({ command: ["bash","-c","cat ~/.local/share/qs-hud-tabs.json 2>/dev/null || echo '{}'"] })
    }

    // ── Panel ─────────────────────────────────────────────────────────────
    // Asymmetric rounded rectangle: bigger rounding on the TOP corners
    // (curving outward up into the bar) than the bottom.
    Rectangle {
        id: hudBg
        anchors { left: parent.left; right: parent.right; top: parent.top }
        implicitHeight: mainCol.implicitHeight
        color: Appearance.colors.colLayer0
        border.width: 1
        border.color: Appearance.colors.colLayer0Border
        clip: true

        topLeftRadius:     30                                // bigger
        topRightRadius:    30                                // bigger
        bottomLeftRadius:  Appearance.rounding.large         // 23 px
        bottomRightRadius: Appearance.rounding.large

        Behavior on implicitHeight {
            NumberAnimation { duration: 110; easing.type: Easing.OutCubic }
        }

        ColumnLayout {
            id: mainCol
            anchors {
                left: parent.left; right: parent.right; top: parent.top
            }
            spacing: 0

            // ── Tab bar ──────────────────────────────────────────────────
            // Shown ONLY when the bar is hidden. While the bar is up it
            // hosts the HUD tabs (Workspaces widget → HUD PillTabBar), so
            // this internal bar collapses to zero height to avoid the
            // duplicate, "too spacy" row.
            Item {
                Layout.fillWidth: true
                clip: true
                visible: !GlobalStates.barOpen
                implicitHeight: GlobalStates.barOpen ? 0 : tabBox.implicitHeight + 16

                Item {
                    id: tabBox
                    anchors {
                        left: parent.left; right: parent.right
                        verticalCenter: parent.verticalCenter
                        leftMargin: 10; rightMargin: 10
                    }
                    implicitHeight: mainTabRow.implicitHeight + 8

                    // Sliding pill — sized to the active tab's *content*
                    // (icon + label), not the whole cell, so it doesn't
                    // bloat across the entire 1/N column.
                    Rectangle {
                        z: 0
                        readonly property var activeTab: mainTabRow.children[root.mainTab]
                        readonly property real pillW: activeTab ? activeTab.pillWidth : 0
                        x: activeTab ? activeTab.x + (activeTab.width - pillW) / 2 : 0
                        y: 4
                        width: pillW
                        height: mainTabRow.implicitHeight
                        radius: height / 2
                        color: Appearance.colors.colPrimary
                        Behavior on x     { NumberAnimation { duration: 130; easing.type: Easing.OutCubic } }
                        Behavior on width { NumberAnimation { duration: 130; easing.type: Easing.OutCubic } }
                    }

                    RowLayout {
                        id: mainTabRow
                        z: 1
                        anchors { left: parent.left; right: parent.right; top: parent.top; topMargin: 4 }
                        spacing: 0

                        HudTabButton { icon: "home";    label: "Home";   active: root.mainGroup === 0; labelVisible: root.mainGroup === 0; onClicked: if (root.mainGroup !== 0) GlobalStates.hudActiveTab = 0 }
                        HudTabButton { icon: "tune";    label: "System"; active: root.mainGroup === 1; labelVisible: root.mainGroup === 1; onClicked: if (root.mainGroup !== 1) GlobalStates.hudActiveTab = 1 }
                        HudTabButton { icon: "widgets"; label: "Hub";    active: root.mainGroup === 2; labelVisible: root.mainGroup === 2; onClicked: if (root.mainGroup !== 2) GlobalStates.hudActiveTab = 4 }
                    }
                }
            }

            // Sub-tab selector moved OUT of the HUD — the bar hosts it
            // as a blob tray fused below the bar (see Bar.qml).

            // ── Page content ──────────────────────────────────────────────
            // Capped to the screen via maxContentHeight — taller pages
            // scroll inside the HUD instead of overflowing the display.
            Flickable {
                id: contentFlick
                Layout.fillWidth: true
                Layout.preferredHeight: Math.min(contentStack.implicitHeight, root.maxContentHeight)
                contentWidth: width
                contentHeight: contentStack.implicitHeight
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                ScrollBar.vertical: ScrollBar {
                    policy: contentStack.implicitHeight > contentFlick.height
                        ? ScrollBar.AsNeeded : ScrollBar.AlwaysOff
                    width: 5
                }
                Behavior on Layout.preferredHeight {
                    NumberAnimation { duration: 110; easing.type: Easing.OutCubic }
                }

                StackLayout {
                    id: contentStack
                    width: contentFlick.width
                    height: implicitHeight
                    currentIndex: root._displayedTab
                    // Track only the current child's height (StackLayout
                    // otherwise sizes to the tallest page).
                    implicitHeight: {
                        root._relayoutTick   // re-read after open until layouts settle
                        return (currentIndex >= 0 && children[currentIndex])
                            ? children[currentIndex].implicitHeight : 0
                    }
                    Behavior on implicitHeight {
                        // Off until ready: the pre-show settle snaps silently;
                        // only later tab switches animate.
                        enabled: root.ready
                        NumberAnimation { duration: 110; easing.type: Easing.OutCubic }
                    }

                // ─ 0 · Dashboard ──────────────────────────────────────────
                LazyStackPage {
                    Component { Item {
                        implicitHeight: dashboardTab.implicitHeight
                        HudDashboard {
                            id: dashboardTab
                            anchors { left: parent.left; right: parent.right; top: parent.top }
                        }
                    } }
                }

                // ─ 1 · Performance ────────────────────────────────────────
                //   (was "Essentials". Renamed: this page now hosts the
                //    perf metrics, processes, and per-device storage.
                //    The NEW Essentials page (toggles, battery, sysinfo)
                //    lives at index 6 below, inside the Home group.)
                Item {
                    implicitHeight: GlobalStates.essentialsRadarOpen
                        ? 560 : perfContent.implicitHeight + 28

                    ColumnLayout {
                        id: perfContent
                        anchors { left: parent.left; right: parent.right; top: parent.top; margins: 14 }
                        spacing: 10
                        opacity: GlobalStates.essentialsRadarOpen ? 0 : 1
                        visible: opacity > 0
                        Behavior on opacity { NumberAnimation { duration: 140 } }

                        // Connectivity radar launcher removed from the HUD —
                        // EssentialsRadar is now opened from the configure
                        // popups on the Bluetooth and Wifi QuickToggles.

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 10

                            GridLayout {
                                    Layout.fillWidth: true
                                    columns: 3; columnSpacing: 10; rowSpacing: 10
                                    HudStatCard { label: qsTr("CPU");   value: root.cpuVal; unit: "%";    history: root.cpuHistory;   accent: root.colCpu    }
                                    HudStatCard { label: qsTr("GPU");   value: root.gpuVal; unit: "%";    history: root.gpuHistory;   accent: root.colGpu    }
                                    HudStatCard { label: qsTr("RAM");   value: root.ramVal; unit: "%";    history: root.ramHistory;   accent: root.colRam    }
                                    HudStatCard { label: qsTr("Net ↑"); value: root.netUp;  unit: "KB/s"; history: root.netUpHistory; accent: root.colNetUp  }
                                    HudStatCard { label: qsTr("Net ↓"); value: root.netDn;  unit: "KB/s"; history: root.netDnHistory; accent: root.colNetDn  }
                                    HudStatCard { label: qsTr("Disk");  value: Math.round(root.diskUsed/root.diskTotal*100); unit: "%"; history: root.diskHistory; accent: root.colDisk }
                                }

                                // Per-device storage panel — one row per detected
                                // disk (internal NVMe, external NVMe, eMMC/SD).
                                // Each row shows model, capacity, R/W throughput,
                                // and temperature with a color step (warm/hot).
                                Rectangle {
                                    Layout.fillWidth: true
                                    implicitHeight: storageCol.implicitHeight + 24
                                    radius: Appearance.rounding.normal
                                    color: Appearance.colors.colLayer1
                                    border.width: 1; border.color: Appearance.colors.colLayer0Border
                                    visible: root.disks.length > 0

                                    ColumnLayout {
                                        id: storageCol
                                        anchors { left: parent.left; right: parent.right; top: parent.top; margins: 14 }
                                        spacing: 6

                                        RowLayout {
                                            Layout.fillWidth: true; Layout.bottomMargin: 4
                                            StyledText { text: qsTr("Storage"); font.pixelSize: Appearance.font.pixelSize.small; color: Appearance.colors.colOnLayer0; opacity: 0.45; Layout.fillWidth: true }
                                            StyledText { text: qsTr("R/W"); font.pixelSize: Appearance.font.pixelSize.small; color: Appearance.colors.colOnLayer0; opacity: 0.32; Layout.preferredWidth: 110; horizontalAlignment: Text.AlignRight }
                                            StyledText { text: "°C";  font.pixelSize: Appearance.font.pixelSize.small; color: Appearance.colors.colOnLayer0; opacity: 0.32; Layout.preferredWidth: 44; horizontalAlignment: Text.AlignRight }
                                        }

                                        Repeater {
                                            model: root.disks
                                            delegate: RowLayout {
                                                required property var modelData
                                                Layout.fillWidth: true
                                                spacing: 8

                                                // Temperature color step: <40 cool, 40-55 warm, >55 hot.
                                                readonly property color tempColor: modelData.tempC >= 55
                                                        ? Appearance.m3colors.m3error
                                                        : modelData.tempC >= 40
                                                            ? Appearance.m3colors.m3tertiary
                                                            : Appearance.colors.colPrimary
                                                readonly property string sizeLabel: modelData.sizeGB >= 1000
                                                        ? (modelData.sizeGB / 1000).toFixed(1) + "T"
                                                        : Math.round(modelData.sizeGB) + "G"
                                                // bytes/s → KB/s or MB/s short form.
                                                function fmtRate(bps) {
                                                    if (bps < 1024) return "0"
                                                    if (bps < 1024 * 1024) return Math.round(bps / 1024) + "k"
                                                    return (bps / 1024 / 1024).toFixed(1) + "M"
                                                }

                                                Rectangle {
                                                    implicitWidth: 3; implicitHeight: 14; radius: 2
                                                    color: tempColor
                                                    opacity: modelData.tempC > 0 ? 1 : 0.25
                                                }
                                                ColumnLayout {
                                                    Layout.fillWidth: true
                                                    spacing: -2
                                                    StyledText {
                                                        text: modelData.model
                                                        font.pixelSize: Appearance.font.pixelSize.small
                                                        font.weight: Font.DemiBold
                                                        color: Appearance.colors.colOnLayer0
                                                        elide: Text.ElideRight
                                                        Layout.fillWidth: true
                                                    }
                                                    StyledText {
                                                        text: modelData.name + " · " + parent.parent.sizeLabel
                                                        font.pixelSize: Appearance.font.pixelSize.smaller
                                                        color: Appearance.colors.colOnLayer0
                                                        opacity: 0.5
                                                    }
                                                }
                                                StyledText {
                                                    text: parent.fmtRate(modelData.readBps) + " / " + parent.fmtRate(modelData.writeBps)
                                                    font.pixelSize: Appearance.font.pixelSize.small
                                                    color: Appearance.colors.colOnLayer0
                                                    Layout.preferredWidth: 110
                                                    horizontalAlignment: Text.AlignRight
                                                }
                                                StyledText {
                                                    text: modelData.tempC > 0 ? Math.round(modelData.tempC) + "°" : "—"
                                                    font.pixelSize: Appearance.font.pixelSize.small
                                                    font.weight: modelData.tempC >= 55 ? Font.Bold : Font.Normal
                                                    color: tempColor
                                                    Layout.preferredWidth: 44
                                                    horizontalAlignment: Text.AlignRight
                                                }
                                            }
                                        }
                                    }
                                }

                                Rectangle {
                                    Layout.fillWidth: true
                                    implicitHeight: procCol.implicitHeight + 24
                                    radius: Appearance.rounding.normal
                                    color: Appearance.colors.colLayer1
                                    border.width: 1; border.color: Appearance.colors.colLayer0Border

                                    ColumnLayout {
                                        id: procCol
                                        anchors { left: parent.left; right: parent.right; top: parent.top; margins: 14 }
                                        spacing: 0

                                        RowLayout {
                                            Layout.fillWidth: true; Layout.bottomMargin: 8
                                            StyledText { text: qsTr("Processes"); font.pixelSize: Appearance.font.pixelSize.small; color: Appearance.colors.colOnLayer0; opacity: 0.45; Layout.fillWidth: true }
                                            StyledText { text: "CPU%"; font.pixelSize: Appearance.font.pixelSize.small; color: Appearance.colors.colOnLayer0; opacity: 0.32; Layout.preferredWidth: 44; horizontalAlignment: Text.AlignRight }
                                            StyledText { text: "MEM%"; font.pixelSize: Appearance.font.pixelSize.small; color: Appearance.colors.colOnLayer0; opacity: 0.32; Layout.preferredWidth: 44; horizontalAlignment: Text.AlignRight }
                                        }

                                        Repeater {
                                            model: root.topProcs
                                            delegate: RowLayout {
                                                required property var modelData
                                                required property int index
                                                Layout.fillWidth: true; Layout.topMargin: index > 0 ? 5 : 0; spacing: 8
                                                readonly property real cpuF: parseFloat(modelData.cpu)||0
                                                readonly property color ac:  root.procAccent(cpuF)
                                                Rectangle { implicitWidth: 3; implicitHeight: 14; radius: 2; color: ac; opacity: cpuF > 3 ? 1 : 0.2 }
                                                StyledText { text: modelData.name; font.pixelSize: Appearance.font.pixelSize.small; color: Appearance.colors.colOnLayer0; Layout.fillWidth: true; elide: Text.ElideRight }
                                                StyledText { text: modelData.cpu; font.pixelSize: Appearance.font.pixelSize.small; font.weight: cpuF > 10 ? Font.Bold : Font.Normal; color: ac; Layout.preferredWidth: 44; horizontalAlignment: Text.AlignRight }
                                                StyledText { text: modelData.mem; font.pixelSize: Appearance.font.pixelSize.small; color: Appearance.colors.colOnLayer0; opacity: 0.5; Layout.preferredWidth: 44; horizontalAlignment: Text.AlignRight }
                                            }
                                        }
                                    }
                                }
                            }
                        }

                    Loader {
                        anchors.fill: parent
                        active: GlobalStates.essentialsRadarOpen
                        sourceComponent: EssentialsRadar {}
                    }
                }

                // ─ 2 · Gaming ─────────────────────────────────────────────
                Item {
                    implicitHeight: gamingStack.implicitHeight + gamingPills.height + 40
                    PillTabBar {
                        id: gamingPills
                        anchors { top: parent.top; horizontalCenter: parent.horizontalCenter; topMargin: 12 }
                        tabs: [
                            { id: "0", icon: "dashboard",     label: "Overview"     },
                            { id: "1", icon: "military_tech", label: "Achievements" }
                        ]
                        current: String(GlobalStates.hudGamingTab)
                        onTabSelected: id => GlobalStates.hudGamingTab = parseInt(id)
                    }
                    StackLayout {
                        id: gamingStack
                        anchors { left: parent.left; right: parent.right; top: gamingPills.bottom; leftMargin: 14; rightMargin: 14; topMargin: 12 }
                        currentIndex: root.gamingTab
                        implicitHeight: (currentIndex >= 0 && children[currentIndex])
                            ? children[currentIndex].implicitHeight : 0

                        // 2.0 · Key Visualizer
                        ColumnLayout {
                            spacing: 14
                            StyledText { Layout.alignment: Qt.AlignHCenter; text: qsTr("Key Visualizer"); font.pixelSize: Appearance.font.pixelSize.large; font.weight: Font.Bold; color: Appearance.colors.colOnLayer0 }
                            Rectangle {
                                Layout.alignment: Qt.AlignHCenter; implicitWidth: 140; implicitHeight: 68
                                radius: Appearance.rounding.large
                                color: root.lastKey !== "" ? Appearance.colors.colPrimary : Appearance.colors.colLayer1
                                border.width: 1; border.color: root.lastKey !== "" ? Appearance.colors.colPrimary : Appearance.colors.colLayer0Border
                                Behavior on color { animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this) }
                                StyledText {
                                    anchors.centerIn: parent
                                    text: root.lastKey !== "" ? root.lastKey : "—"
                                    font.pixelSize: Appearance.font.pixelSize.larger * 1.5; font.weight: Font.Bold
                                    color: root.lastKey !== "" ? Appearance.m3colors.m3onPrimary : Appearance.colors.colOnLayer0
                                    opacity: root.lastKey !== "" ? 1 : 0.25
                                }
                            }
                            StyledText { Layout.alignment: Qt.AlignHCenter; text: qsTr("Pipe key names to ~/.local/share/qs-hud-lastkey"); font.pixelSize: Appearance.font.pixelSize.small; color: Appearance.colors.colOnLayer0; opacity: 0.3; horizontalAlignment: Text.AlignHCenter; wrapMode: Text.WordWrap; Layout.fillWidth: true }
                        }

                        // 2.1 · Achievements
                        ColumnLayout {
                            spacing: 10

                            Rectangle {
                                Layout.fillWidth: true
                                implicitHeight: levelRow.implicitHeight + 28
                                radius: Appearance.rounding.normal
                                color: Appearance.colors.colLayer1
                                border.width: 1; border.color: Appearance.colors.colLayer0Border

                                RowLayout {
                                    id: levelRow
                                    anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter; margins: 16 }
                                    spacing: 16

                                    Item {
                                        id: lvlBadge
                                        implicitWidth: 76; implicitHeight: 76
                                        readonly property real progress: (root.xpTotal % 1000) / 1000

                                        // Subtle outer glow that intensifies as the player nears level-up
                                        Rectangle {
                                            anchors.centerIn: parent
                                            width: parent.width + 10; height: parent.height + 10
                                            radius: width / 2
                                            color: "transparent"
                                            border.width: 2
                                            border.color: Appearance.colors.colPrimary
                                            opacity: 0.10 + lvlBadge.progress * 0.20
                                            Behavior on opacity { NumberAnimation { duration: 300 } }
                                        }

                                        // GPU-accelerated XP progress arc (only repainted when progress changes)
                                        Shape {
                                            anchors.fill: parent
                                            asynchronous: true
                                            // Track ring (full circle, dim)
                                            ShapePath {
                                                strokeWidth: 4
                                                strokeColor: Appearance.colors.colLayer2
                                                fillColor: "transparent"
                                                capStyle: ShapePath.RoundCap
                                                PathAngleArc {
                                                    centerX: lvlBadge.width / 2
                                                    centerY: lvlBadge.height / 2
                                                    radiusX: lvlBadge.width / 2 - 4
                                                    radiusY: lvlBadge.height / 2 - 4
                                                    startAngle: -90
                                                    sweepAngle: 360
                                                }
                                            }
                                            // Progress ring
                                            ShapePath {
                                                strokeWidth: 4
                                                strokeColor: Appearance.colors.colPrimary
                                                fillColor: "transparent"
                                                capStyle: ShapePath.RoundCap
                                                PathAngleArc {
                                                    centerX: lvlBadge.width / 2
                                                    centerY: lvlBadge.height / 2
                                                    radiusX: lvlBadge.width / 2 - 4
                                                    radiusY: lvlBadge.height / 2 - 4
                                                    startAngle: -90
                                                    sweepAngle: lvlBadge.progress * 360
                                                    Behavior on sweepAngle { NumberAnimation { duration: 600; easing.type: Easing.OutCubic } }
                                                }
                                            }
                                        }

                                        // Inner badge
                                        Rectangle {
                                            anchors.centerIn: parent
                                            width: 58; height: 58; radius: 29
                                            color: Appearance.colors.colPrimary
                                            // Tiny pulse when level changes
                                            scale: 1
                                            Behavior on scale { NumberAnimation { duration: 250; easing.type: Easing.OutBack } }
                                            Connections {
                                                target: root
                                                function onXpLevelChanged() {
                                                    pulseUp.restart()
                                                }
                                            }
                                            SequentialAnimation {
                                                id: pulseUp
                                                NumberAnimation { target: lvlBadge.children[2]; property: "scale"; from: 1; to: 1.12; duration: 140; easing.type: Easing.OutCubic }
                                                NumberAnimation { target: lvlBadge.children[2]; property: "scale"; from: 1.12; to: 1; duration: 220; easing.type: Easing.InOutCubic }
                                            }
                                            ColumnLayout {
                                                anchors.centerIn: parent; spacing: -3
                                                StyledText { Layout.alignment: Qt.AlignHCenter; text: "LVL"; font.pixelSize: Appearance.font.pixelSize.smaller - 1; font.weight: Font.Bold; color: Appearance.m3colors.m3onPrimary; opacity: 0.65 }
                                                StyledText { Layout.alignment: Qt.AlignHCenter; text: root.xpLevel; font.pixelSize: Appearance.font.pixelSize.larger * 1.35; font.weight: Font.Black; color: Appearance.m3colors.m3onPrimary }
                                            }
                                        }
                                    }

                                    ColumnLayout {
                                        Layout.fillWidth: true; spacing: 8
                                        RowLayout {
                                            Layout.fillWidth: true
                                            StyledText { text: qsTr("Level %1").arg(root.xpLevel); font.pixelSize: Appearance.font.pixelSize.large; font.weight: Font.Bold; color: Appearance.colors.colOnLayer0 }
                                            Item { Layout.fillWidth: true }
                                            StyledText { text: qsTr("%1 XP").arg(root.xpTotal); font.pixelSize: Appearance.font.pixelSize.small; color: Appearance.colors.colOnLayer0; opacity: 0.38 }
                                        }
                                        Item {
                                            Layout.fillWidth: true; implicitHeight: 12
                                            Rectangle {
                                                anchors.fill: parent; radius: 6; color: Appearance.colors.colLayer2
                                                Rectangle {
                                                    width: parent.width * ((root.xpTotal % 1000) / 1000)
                                                    height: parent.height; radius: parent.radius; color: Appearance.colors.colPrimary
                                                    Behavior on width { NumberAnimation { duration: 600; easing.type: Easing.OutCubic } }
                                                }
                                            }
                                        }
                                        StyledText { text: qsTr("%1 / 1000 XP to level %2").arg(Math.round(root.xpTotal % 1000)).arg(root.xpLevel + 1); font.pixelSize: Appearance.font.pixelSize.small; color: Appearance.colors.colOnLayer0; opacity: 0.38 }
                                    }
                                }
                            }

                            RowLayout {
                                Layout.fillWidth: true; spacing: 10
                                Repeater {
                                    model: [
                                        { icon: "keyboard", label: qsTr("Keystrokes"), value: root._keyPresses },
                                        { icon: "mouse",    label: qsTr("Clicks"),     value: root._mouseClicks },
                                    ]
                                    delegate: Rectangle {
                                        required property var modelData
                                        Layout.fillWidth: true
                                        implicitHeight: achStat.implicitHeight + 20
                                        radius: Appearance.rounding.normal; color: Appearance.colors.colLayer1
                                        border.width: 1; border.color: Appearance.colors.colLayer0Border
                                        ColumnLayout {
                                            id: achStat; anchors.centerIn: parent; spacing: 2
                                            MaterialSymbol { Layout.alignment: Qt.AlignHCenter; text: modelData.icon; iconSize: Appearance.font.pixelSize.larger; color: Appearance.colors.colPrimary }
                                            StyledText { Layout.alignment: Qt.AlignHCenter; text: modelData.value; font.pixelSize: Appearance.font.pixelSize.larger; font.weight: Font.Bold; color: Appearance.colors.colOnLayer0 }
                                            StyledText { Layout.alignment: Qt.AlignHCenter; text: modelData.label; font.pixelSize: Appearance.font.pixelSize.small; color: Appearance.colors.colOnLayer0; opacity: 0.55 }
                                        }
                                    }
                                }
                            }

                            Rectangle {
                                Layout.fillWidth: true
                                implicitHeight: badgesCol.implicitHeight + 24
                                radius: Appearance.rounding.normal
                                color: Appearance.colors.colLayer1
                                border.width: 1; border.color: Appearance.colors.colLayer0Border

                                ColumnLayout {
                                    id: badgesCol
                                    anchors { left: parent.left; right: parent.right; top: parent.top; margins: 14 }
                                    spacing: 10

                                    StyledText { text: qsTr("Milestones"); font.pixelSize: Appearance.font.pixelSize.small; color: Appearance.colors.colOnLayer0; opacity: 0.45 }

                                    RowLayout {
                                        Layout.fillWidth: true; spacing: 8
                                        Repeater {
                                            model: [
                                                { icon: "emoji_events",          label: "First Steps", xpReq: 100   },
                                                { icon: "local_fire_department", label: "Dedicated",   xpReq: 1000  },
                                                { icon: "star",                  label: "Veteran",     xpReq: 5000  },
                                                { icon: "diamond",               label: "Master",      xpReq: 10000 },
                                                { icon: "rocket_launch",         label: "Legend",      xpReq: 50000 },
                                            ]
                                            delegate: ColumnLayout {
                                                required property var modelData
                                                Layout.fillWidth: true
                                                readonly property bool unlocked: root.xpTotal >= modelData.xpReq
                                                readonly property real progress: Math.min(1, root.xpTotal / modelData.xpReq)
                                                spacing: 5
                                                Item {
                                                    Layout.alignment: Qt.AlignHCenter
                                                    implicitWidth: 50; implicitHeight: 50

                                                    // Progress ring (only painted when value changes)
                                                    Shape {
                                                        anchors.fill: parent
                                                        asynchronous: true
                                                        visible: !parent.parent.unlocked
                                                        ShapePath {
                                                            strokeWidth: 3
                                                            strokeColor: Appearance.colors.colPrimary
                                                            fillColor: "transparent"
                                                            capStyle: ShapePath.RoundCap
                                                            PathAngleArc {
                                                                centerX: 25; centerY: 25
                                                                radiusX: 23; radiusY: 23
                                                                startAngle: -90
                                                                sweepAngle: parent.parent.parent.progress * 360
                                                                Behavior on sweepAngle { NumberAnimation { duration: 500; easing.type: Easing.OutCubic } }
                                                            }
                                                        }
                                                    }

                                                    Rectangle {
                                                        anchors.centerIn: parent
                                                        width: 40; height: 40; radius: 20
                                                        color: parent.parent.unlocked ? Appearance.colors.colPrimary : Appearance.colors.colLayer2
                                                        border.width: 1; border.color: parent.parent.unlocked ? Appearance.colors.colPrimary : Appearance.colors.colLayer0Border
                                                        Behavior on color { animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this) }
                                                        MaterialSymbol {
                                                            anchors.centerIn: parent; text: parent.parent.parent.modelData.icon; iconSize: 19
                                                            color: parent.parent.parent.unlocked ? Appearance.m3colors.m3onPrimary : Appearance.colors.colOnLayer0
                                                            opacity: parent.parent.parent.unlocked ? 1 : 0.32
                                                            Behavior on color { animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this) }
                                                        }
                                                    }
                                                }
                                                StyledText {
                                                    Layout.alignment: Qt.AlignHCenter
                                                    text: modelData.label; font.pixelSize: 8; font.weight: Font.Medium
                                                    color: Appearance.colors.colOnLayer0
                                                    opacity: unlocked ? 0.65 : 0.22
                                                    horizontalAlignment: Text.AlignHCenter
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

                // ─ 3 · Settings ───────────────────────────────────────────
                Item {
                    implicitHeight: wsLayout.implicitHeight + 28
                    ColumnLayout {
                        id: wsLayout
                        anchors { left: parent.left; right: parent.right; top: parent.top; margins: 14 }
                        spacing: 8

                        // Page title
                        StyledText {
                            text: qsTr("Settings")
                            font.pixelSize: Appearance.font.pixelSize.huge
                            font.weight: Font.Bold
                            color: Appearance.colors.colOnLayer0
                            Layout.bottomMargin: 2
                        }

                        // ── Workspaces section ──
                        ColumnLayout {
                            spacing: 2; Layout.bottomMargin: 4
                            StyledText { text: qsTr("Workspaces"); font.pixelSize: Appearance.font.pixelSize.normal; font.weight: Font.Bold; color: Appearance.colors.colOnLayer0 }
                            StyledText { text: qsTr("Click  to rename · swatch to tag · arrow to jump"); font.pixelSize: Appearance.font.pixelSize.small; color: Appearance.colors.colOnLayer0; opacity: 0.38 }
                        }

                        Repeater {
                            model: {
                                const ws = Hyprland.workspaces.values
                                return ws ? ws.slice().sort((a,b) => a.id - b.id) : []
                            }
                            delegate: Rectangle {
                                required property var modelData
                                Layout.fillWidth: true
                                implicitHeight: wsRow.implicitHeight + 16
                                radius: Appearance.rounding.normal
                                color: Appearance.colors.colLayer1
                                border.width: 1; border.color: Appearance.colors.colLayer0Border
                                property string wsCustomColor: root.wsColors[modelData.id] ?? ""
                                property bool   isEditing:     false

                                RowLayout {
                                    id: wsRow
                                    anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter; leftMargin: 12; rightMargin: 12 }
                                    spacing: 8

                                    Rectangle {
                                        implicitWidth: chipTxt.implicitWidth + 14; implicitHeight: chipTxt.implicitHeight + 8
                                        radius: Appearance.rounding.full
                                        color: parent.parent.wsCustomColor !== "" ? parent.parent.wsCustomColor : Appearance.colors.colPrimary
                                        Behavior on color { animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this) }
                                        StyledText { id: chipTxt; anchors.centerIn: parent; text: modelData.id; font.pixelSize: Appearance.font.pixelSize.small; font.weight: Font.Bold; color: Appearance.m3colors.m3onPrimary }
                                    }

                                    StyledText {
                                        text: modelData.windows > 0 ? qsTr("%1w").arg(modelData.windows) : "—"
                                        font.pixelSize: Appearance.font.pixelSize.small; color: Appearance.colors.colOnLayer0; opacity: 0.3
                                        Layout.preferredWidth: 22
                                    }

                                    Item {
                                        Layout.fillWidth: true; implicitHeight: nameLbl.implicitHeight + 8
                                        Rectangle {
                                            anchors.fill: parent; radius: Appearance.rounding.small
                                            color: parent.parent.parent.isEditing ? Appearance.colors.colLayer2 : ColorUtils.transparentize(Appearance.colors.colLayer2)
                                            border.width: parent.parent.parent.isEditing ? 1 : 0
                                            border.color: Appearance.colors.colPrimary
                                            Behavior on color { animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this) }
                                        }
                                        StyledText {
                                            id: nameLbl
                                            anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter; margins: 4 }
                                            visible: !parent.parent.parent.isEditing
                                            text: modelData.name ?? String(modelData.id)
                                            font.pixelSize: Appearance.font.pixelSize.normal
                                            color: Appearance.colors.colOnLayer0
                                            elide: Text.ElideRight
                                        }
                                        TextInput {
                                            id: nameIn
                                            anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter; margins: 6 }
                                            visible: parent.parent.parent.isEditing
                                            text: modelData.name ?? String(modelData.id)
                                            color: Appearance.colors.colOnLayer0
                                            font.pixelSize: Appearance.font.pixelSize.normal
                                            selectByMouse: true
                                            onAccepted: {
                                                const t = text.trim()
                                                if (t) HyprDispatch.run(`renameworkspace ${modelData.id} ${t}`)
                                                parent.parent.parent.isEditing = false
                                            }
                                            Keys.onEscapePressed: {
                                                text = modelData.name ?? String(modelData.id)
                                                parent.parent.parent.isEditing = false
                                            }
                                            onVisibleChanged: if (visible) { selectAll(); forceActiveFocus() }
                                        }
                                    }

                                    Rectangle {
                                        implicitWidth: 26; implicitHeight: 26; radius: Appearance.rounding.full
                                        color: parent.parent.isEditing ? Appearance.colors.colPrimary : Appearance.colors.colLayer2
                                        border.width: 1; border.color: parent.parent.isEditing ? Appearance.colors.colPrimary : Appearance.colors.colLayer0Border
                                        Behavior on color { animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this) }
                                        MaterialSymbol {
                                            anchors.centerIn: parent
                                            text: parent.parent.parent.isEditing ? "check" : "edit"
                                            iconSize: Appearance.font.pixelSize.normal
                                            color: parent.parent.parent.isEditing ? Appearance.m3colors.m3onPrimary : Appearance.colors.colOnLayer0
                                            Behavior on color { animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this) }
                                        }
                                        TapHandler {
                                            margin: Appearance.sizes.touchSlop
                                            onTapped: {
                                                const c = parent.parent.parent
                                                if (c.isEditing) {
                                                    const t = nameIn.text.trim()
                                                    if (t) HyprDispatch.run(`renameworkspace ${c.modelData.id} ${t}`)
                                                    c.isEditing = false
                                                } else {
                                                    c.isEditing = true
                                                }
                                            }
                                        }
                                    }

                                    Row {
                                        spacing: 5
                                        Repeater {
                                            model: 8
                                            delegate: Rectangle {
                                                required property int index
                                                readonly property color swatchColor: {
                                                    switch(index) {
                                                        case 0: return Appearance.m3colors.m3primary
                                                        case 1: return Appearance.m3colors.m3secondary
                                                        case 2: return Appearance.m3colors.m3tertiary
                                                        case 3: return Appearance.m3colors.m3error
                                                        case 4: return "#22c55e"
                                                        case 5: return "#f97316"
                                                        case 6: return "#6366f1"
                                                        default: return "#ec4899"
                                                    }
                                                }
                                                width: 14; height: 14; radius: 7; color: swatchColor
                                                border.width: wsRow.parent.wsCustomColor.toString() === swatchColor.toString() ? 2 : 0
                                                border.color: Appearance.colors.colOnLayer0
                                                TapHandler {
                                                    margin: Appearance.sizes.touchSlop
                                                    onTapped: {
                                                        const id = wsRow.parent.modelData.id
                                                        const nc = Object.assign({}, root.wsColors)
                                                        nc[id] = parent.swatchColor.toString()
                                                        root.wsColors = nc
                                                        root.saveWsColors()
                                                    }
                                                }
                                            }
                                        }
                                        Rectangle {
                                            width: 14; height: 14; radius: 7; color: Appearance.colors.colLayer2
                                            border.width: 1; border.color: Appearance.colors.colLayer0Border
                                            MaterialSymbol { anchors.centerIn: parent; text: "close"; iconSize: 9; color: Appearance.colors.colOnLayer0; opacity: 0.55 }
                                            TapHandler {
                                                margin: Appearance.sizes.touchSlop
                                                onTapped: {
                                                    const id = wsRow.parent.modelData.id
                                                    const nc = Object.assign({}, root.wsColors)
                                                    delete nc[id]
                                                    root.wsColors = nc
                                                    root.saveWsColors()
                                                }
                                            }
                                        }
                                    }

                                    Rectangle {
                                        implicitWidth: 26; implicitHeight: 26; radius: Appearance.rounding.full
                                        color: Appearance.colors.colLayer2
                                        border.width: 1; border.color: Appearance.colors.colLayer0Border
                                        MaterialSymbol { anchors.centerIn: parent; text: "arrow_forward"; iconSize: Appearance.font.pixelSize.normal; color: Appearance.colors.colOnLayer0 }
                                        TapHandler {
                                            margin: Appearance.sizes.touchSlop
                                            onTapped: {
                                                HyprDispatch.run(`workspace ${wsRow.parent.modelData.id}`)
                                                GlobalStates.hudOpen = false
                                            }
                                        }
                                    }
                                }
                            }
                        }

                        StyledText {
                            visible: Hyprland.workspaces.values.length === 0
                            text: qsTr("No workspaces open")
                            font.pixelSize: Appearance.font.pixelSize.normal
                            color: Appearance.colors.colOnLayer0; opacity: 0.3
                            Layout.alignment: Qt.AlignHCenter
                        }
                    }
                }

                // ─ 4 · Media ──────────────────────────────────────────────
                Item {
                    implicitHeight: mediaPageCol.implicitHeight + 28

                    Timer {
                        running: MprisController.activePlayer?.playbackState === MprisPlaybackState.Playing && root.mainTab === 4
                        interval: 1000; repeat: true
                        onTriggered: MprisController.activePlayer?.positionChanged()
                    }

                    ColumnLayout {
                        id: mediaPageCol
                        anchors { left: parent.left; right: parent.right; top: parent.top; margins: 14 }
                        spacing: 10

                        PillTabBar {
                            Layout.alignment: Qt.AlignHCenter
                            tabs: [
                                { id: "0", icon: "dashboard",   label: "Overview" },
                                { id: "1", icon: "play_circle", label: "Player"   },
                                { id: "2", icon: "person",      label: "Last.fm"  },
                                { id: "3", icon: "graphic_eq",  label: "EQ"       }
                            ]
                            current: String(GlobalStates.hudMediaTab)
                            onTabSelected: id => GlobalStates.hudMediaTab = parseInt(id)
                        }

                        StackLayout {
                            id: mediaContentStack
                            currentIndex: root._displayedMediaTab
                            implicitHeight: (currentIndex >= 0 && children[currentIndex])
                                ? children[currentIndex].implicitHeight : 0
                            Layout.fillWidth: true

                            // 0 · Overview
                            RowLayout {
                                spacing: 10

                                Rectangle {
                                    Layout.fillWidth: true
                                    implicitHeight: npOverviewCol.implicitHeight + 24
                                    radius: Appearance.rounding.normal
                                    color: Appearance.colors.colLayer1
                                    border.width: 1; border.color: Appearance.colors.colLayer0Border

                                    ColumnLayout {
                                        id: npOverviewCol
                                        anchors { left: parent.left; right: parent.right; top: parent.top; margins: 14 }
                                        spacing: 10

                                        StyledText { text: qsTr("Now Playing"); font.pixelSize: Appearance.font.pixelSize.small; color: Appearance.colors.colOnLayer0; opacity: 0.45 }

                                        RowLayout {
                                            spacing: 10
                                            Rectangle {
                                                implicitWidth: 44; implicitHeight: 44
                                                radius: Appearance.rounding.normal; color: Appearance.colors.colLayer2; clip: true
                                                Image { anchors.fill: parent; source: MprisController.activeTrack?.artUrl ?? ""; fillMode: Image.PreserveAspectCrop; visible: status === Image.Ready }
                                                MaterialSymbol { anchors.centerIn: parent; text: "album"; iconSize: Appearance.font.pixelSize.larger; color: Appearance.colors.colOnLayer0; opacity: 0.2 }
                                            }
                                            ColumnLayout {
                                                Layout.fillWidth: true; spacing: 2
                                                StyledText { Layout.fillWidth: true; text: MprisController.activeTrack?.title ?? qsTr("No media"); font.pixelSize: Appearance.font.pixelSize.small; font.weight: Font.Bold; color: Appearance.colors.colOnLayer0; elide: Text.ElideRight }
                                                StyledText { Layout.fillWidth: true; text: MprisController.activeTrack?.artist ?? ""; font.pixelSize: Appearance.font.pixelSize.small; color: Appearance.colors.colOnLayer0; opacity: 0.5; elide: Text.ElideRight }
                                            }
                                        }

                                        Rectangle {
                                            Layout.fillWidth: true; implicitHeight: 3; radius: 2; color: Appearance.colors.colLayer2
                                            Rectangle {
                                                radius: parent.radius; height: parent.height; color: Appearance.colors.colPrimary
                                                width: { const p = MprisController.activePlayer; return p && p.length > 0 ? parent.width * Math.min(p.position/p.length,1) : 0 }
                                                Behavior on width { NumberAnimation { duration: 900; easing.type: Easing.Linear } }
                                            }
                                        }

                                        RowLayout {
                                            Layout.alignment: Qt.AlignHCenter; spacing: 6
                                            Repeater {
                                                model: ["skip_previous", MprisController.activePlayer?.isPlaying ? "pause" : "play_arrow", "skip_next"]
                                                delegate: Rectangle {
                                                    required property string modelData
                                                    required property int index
                                                    implicitWidth: 32; implicitHeight: 32; radius: 16
                                                    color: index === 1 ? Appearance.colors.colPrimary : Appearance.colors.colLayer2
                                                    border.width: 1; border.color: Appearance.colors.colLayer0Border
                                                    MaterialSymbol { anchors.centerIn: parent; text: parent.modelData; iconSize: Appearance.font.pixelSize.normal; color: parent.index === 1 ? Appearance.m3colors.m3onPrimary : Appearance.colors.colOnLayer0 }
                                                    TapHandler {
                                                        margin: Appearance.sizes.touchSlop
                                                        onTapped: {
                                                            const p = MprisController.activePlayer
                                                            if (!p) return
                                                            if (parent.index === 0) p.previous()
                                                            else if (parent.index === 2) p.next()
                                                            else p.togglePlaying()
                                                        }
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }

                                Rectangle {
                                    Layout.fillWidth: true
                                    implicitHeight: lfmOverviewCol.implicitHeight + 24
                                    radius: Appearance.rounding.normal
                                    color: Appearance.colors.colLayer1
                                    border.width: 1; border.color: Appearance.colors.colLayer0Border

                                    ColumnLayout {
                                        id: lfmOverviewCol
                                        anchors { left: parent.left; right: parent.right; top: parent.top; margins: 14 }
                                        spacing: 8

                                        RowLayout {
                                            StyledText { text: "Last.fm"; font.pixelSize: Appearance.font.pixelSize.small; font.weight: Font.Bold; color: root.colLastFm; Layout.fillWidth: true }
                                            StyledText { text: root.lfmUsername || qsTr("not set"); font.pixelSize: Appearance.font.pixelSize.small; color: Appearance.colors.colOnLayer0; opacity: 0.4 }
                                        }

                                        RowLayout {
                                            visible: root.lfmRecentTrack !== null
                                            Layout.fillWidth: true; spacing: 8
                                            Rectangle {
                                                implicitWidth: 36; implicitHeight: 36; radius: 4; color: Appearance.colors.colLayer2; clip: true
                                                Image {
                                                    anchors.fill: parent
                                                    source: {
                                                        const imgs = root.lfmRecentTrack?.image ?? []
                                                        return imgs.find(i => i.size === "medium")?.["#text"] ?? ""
                                                    }
                                                    fillMode: Image.PreserveAspectCrop
                                                    visible: status === Image.Ready
                                                }
                                            }
                                            ColumnLayout {
                                                Layout.fillWidth: true; spacing: 1
                                                StyledText { text: root.lfmRecentTrack?.["@attr"]?.nowplaying === "true" ? "▶ scrobbling" : "last played"; font.pixelSize: Appearance.font.pixelSize.small-1; color: root.lfmRecentTrack?.["@attr"]?.nowplaying === "true" ? root.colLastFm : Appearance.colors.colOnLayer0; opacity: root.lfmRecentTrack?.["@attr"]?.nowplaying === "true" ? 1 : 0.45 }
                                                StyledText { Layout.fillWidth: true; text: root.lfmRecentTrack?.name ?? ""; font.pixelSize: Appearance.font.pixelSize.small; color: Appearance.colors.colOnLayer0; elide: Text.ElideRight }
                                            }
                                        }

                                        Repeater {
                                            model: root.lfmTopArtists.slice(0,3)
                                            delegate: RowLayout {
                                                required property var modelData
                                                required property int index
                                                Layout.fillWidth: true
                                                StyledText { text: String(index+1)+"."; font.pixelSize: Appearance.font.pixelSize.small; color: Appearance.colors.colOnLayer0; opacity: 0.3; Layout.preferredWidth: 18 }
                                                StyledText { text: modelData.name; font.pixelSize: Appearance.font.pixelSize.small; color: Appearance.colors.colOnLayer0; Layout.fillWidth: true; elide: Text.ElideRight }
                                                StyledText { text: modelData.playcount; font.pixelSize: Appearance.font.pixelSize.small; color: Appearance.colors.colOnLayer0; opacity: 0.35 }
                                            }
                                        }

                                        StyledText { visible: !root.lfmUsername; text: qsTr("Configure in Last.fm tab →"); font.pixelSize: Appearance.font.pixelSize.small; color: Appearance.colors.colOnLayer0; opacity: 0.35 }
                                    }
                                }
                            }

                            // 1 · Player
                            Rectangle {
                                implicitHeight: playerCol.implicitHeight + 24
                                radius: Appearance.rounding.normal
                                color: Appearance.colors.colLayer1
                                border.width: 1; border.color: Appearance.colors.colLayer0Border

                                RowLayout {
                                    id: playerCol
                                    anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter; margins: 14 }
                                    spacing: 16

                                    Rectangle {
                                        implicitWidth: 96; implicitHeight: 96
                                        radius: Appearance.rounding.large; color: Appearance.colors.colLayer2; clip: true
                                        Image { anchors.fill: parent; source: MprisController.activeTrack?.artUrl ?? ""; fillMode: Image.PreserveAspectCrop; visible: status === Image.Ready }
                                        MaterialSymbol { anchors.centerIn: parent; text: "album"; iconSize: Appearance.font.pixelSize.larger*2; color: Appearance.colors.colOnLayer0; opacity: 0.15 }
                                    }

                                    ColumnLayout {
                                        Layout.fillWidth: true; spacing: 8

                                        StyledText { Layout.fillWidth: true; text: MprisController.activeTrack?.title ?? qsTr("No media"); font.pixelSize: Appearance.font.pixelSize.larger; font.weight: Font.Bold; color: Appearance.colors.colOnLayer0; elide: Text.ElideRight }
                                        StyledText { Layout.fillWidth: true; text: [MprisController.activeTrack?.artist, MprisController.activeTrack?.album].filter(s=>s).join(" · "); font.pixelSize: Appearance.font.pixelSize.small; color: Appearance.colors.colOnLayer0; opacity: 0.55; elide: Text.ElideRight }

                                        Item {
                                            Layout.fillWidth: true; implicitHeight: 6
                                            Rectangle {
                                                anchors.fill: parent; radius: 3; color: Appearance.colors.colLayer2
                                                Rectangle {
                                                    radius: parent.radius; height: parent.height; color: Appearance.colors.colPrimary
                                                    width: { const p = MprisController.activePlayer; return p && p.length > 0 ? parent.width * Math.min(p.position/p.length,1) : 0 }
                                                    Behavior on width { NumberAnimation { duration: 900; easing.type: Easing.Linear } }
                                                }
                                            }
                                            MouseArea {
                                                anchors.fill: parent
                                                onClicked: mouse => {
                                                    const p = MprisController.activePlayer
                                                    if (p && p.length > 0) p.position = (mouse.x/width)*p.length
                                                }
                                            }
                                        }

                                        RowLayout {
                                            Layout.fillWidth: true
                                            function fmt(s) { const m=Math.floor(s/60),ss=Math.floor(s%60); return `${m}:${String(ss).padStart(2,"0")}` }
                                            StyledText { text: parent.fmt(MprisController.activePlayer?.position??0); font.pixelSize: Appearance.font.pixelSize.small-1; color: Appearance.colors.colOnLayer0; opacity: 0.4 }
                                            Item { Layout.fillWidth: true }
                                            StyledText { text: parent.fmt(MprisController.activePlayer?.length??0); font.pixelSize: Appearance.font.pixelSize.small-1; color: Appearance.colors.colOnLayer0; opacity: 0.4 }
                                        }

                                        RowLayout {
                                            Layout.alignment: Qt.AlignHCenter; spacing: 8
                                            Repeater {
                                                model: ["skip_previous", MprisController.activePlayer?.isPlaying ? "pause" : "play_arrow", "skip_next"]
                                                delegate: Rectangle {
                                                    required property string modelData
                                                    required property int index
                                                    implicitWidth: 40; implicitHeight: 40; radius: 20
                                                    color: index === 1 ? Appearance.colors.colPrimary : Appearance.colors.colLayer2
                                                    border.width: 1; border.color: Appearance.colors.colLayer0Border
                                                    MaterialSymbol { anchors.centerIn: parent; text: parent.modelData; iconSize: Appearance.font.pixelSize.large; color: parent.index === 1 ? Appearance.m3colors.m3onPrimary : Appearance.colors.colOnLayer0 }
                                                    TapHandler {
                                                        onTapped: {
                                                            const p = MprisController.activePlayer
                                                            if (!p) return
                                                            if (parent.index === 0) p.previous()
                                                            else if (parent.index === 2) p.next()
                                                            else p.togglePlaying()
                                                        }
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }
                            }

                            // 2 · Last.fm
                            Rectangle {
                                implicitHeight: lfmFullCol.implicitHeight + 24
                                radius: Appearance.rounding.normal
                                color: Appearance.colors.colLayer1
                                border.width: 1; border.color: Appearance.colors.colLayer0Border

                                ColumnLayout {
                                    id: lfmFullCol
                                    anchors { left: parent.left; right: parent.right; top: parent.top; margins: 14 }
                                    spacing: 12

                                    RowLayout {
                                        StyledText { text: "Last.fm"; font.pixelSize: Appearance.font.pixelSize.normal; font.weight: Font.Bold; color: root.colLastFm; Layout.fillWidth: true }
                                        Rectangle {
                                            visible: root.lfmLoading; implicitWidth: 8; implicitHeight: 8; radius: 4; color: root.colLastFm
                                            SequentialAnimation on opacity {
                                                running: root.lfmLoading; loops: Animation.Infinite
                                                NumberAnimation { to: 0.2; duration: 500 }
                                                NumberAnimation { to: 1.0; duration: 500 }
                                            }
                                        }
                                    }

                                    // Username row. The API key is read-only here — it
                                    // comes from ~/.secure/apikeys and isn't editable from
                                    // the HUD (see the indicator row below).
                                    RowLayout {
                                        Layout.fillWidth: true; spacing: 8
                                        StyledText { text: qsTr("Username"); font.pixelSize: Appearance.font.pixelSize.small; color: Appearance.colors.colOnLayer0; opacity: 0.55; Layout.preferredWidth: 72 }
                                        Rectangle {
                                            Layout.fillWidth: true; implicitHeight: lfmIn.implicitHeight + 10
                                            radius: Appearance.rounding.small; color: Appearance.colors.colLayer2
                                            border.width: 1; border.color: Appearance.colors.colLayer0Border
                                            TextInput {
                                                id: lfmIn
                                                anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter; margins: 8 }
                                                color: Appearance.colors.colOnLayer0; font.pixelSize: Appearance.font.pixelSize.small
                                                text: root.lfmUsername
                                                onEditingFinished: {
                                                    root.lfmUsername = text.trim()
                                                    root.saveLastFmConfig()
                                                    if (root.lfmUsername && root.lfmApiKey) root.fetchLastFm()
                                                }
                                            }
                                        }
                                    }

                                    RowLayout {
                                        Layout.fillWidth: true; spacing: 6
                                        StyledText {
                                            text: root.lfmApiKey ? "🔑" : "⚠"
                                            font.pixelSize: Appearance.font.pixelSize.small
                                        }
                                        StyledText {
                                            Layout.fillWidth: true; wrapMode: Text.WordWrap
                                            text: root.lfmApiKey
                                                ? qsTr("API key loaded from ~/.secure/apikeys")
                                                : qsTr("Set LASTFM_API_KEY in ~/.secure/apikeys")
                                            font.pixelSize: Appearance.font.pixelSize.small
                                            color: Appearance.colors.colOnLayer0
                                            opacity: 0.5
                                        }
                                    }

                                    ColumnLayout {
                                        visible: root.lfmTopArtists.length > 0
                                        Layout.fillWidth: true; spacing: 6
                                        StyledText { text: qsTr("Top artists · 7 days"); font.pixelSize: Appearance.font.pixelSize.small; color: Appearance.colors.colOnLayer0; opacity: 0.4 }
                                        Repeater {
                                            model: root.lfmTopArtists
                                            delegate: RowLayout {
                                                required property var modelData
                                                required property int index
                                                Layout.fillWidth: true; spacing: 6
                                                StyledText { text: String(index+1); font.pixelSize: Appearance.font.pixelSize.small; color: Appearance.colors.colOnLayer0; opacity: 0.3; Layout.preferredWidth: 18 }
                                                StyledText { text: modelData.name; font.pixelSize: Appearance.font.pixelSize.small; color: Appearance.colors.colOnLayer0; Layout.fillWidth: true; elide: Text.ElideRight }
                                                StyledText { text: qsTr("%1 plays").arg(modelData.playcount); font.pixelSize: Appearance.font.pixelSize.small; color: Appearance.colors.colOnLayer0; opacity: 0.38 }
                                            }
                                        }
                                    }

                                    StyledText {
                                        visible: !root.lfmUsername || !root.lfmApiKey
                                        text: !root.lfmApiKey
                                            ? qsTr("Add LASTFM_API_KEY to ~/.secure/apikeys to load Last.fm stats")
                                            : qsTr("Enter your username above to load Last.fm stats")
                                        font.pixelSize: Appearance.font.pixelSize.small; color: Appearance.colors.colOnLayer0; opacity: 0.35
                                        wrapMode: Text.WordWrap; Layout.fillWidth: true
                                    }
                                }
                            }

                            // 3 · Equalizer
                            EqualizerView {}
                        }
                    }
                }

                // ─ 5 · Screen Time ────────────────────────────────────────
                // (page 6 — the new Essentials — is defined after this so
                //  the StackLayout child order matches mainTab indices)
                LazyStackPage {
                    Component { Item {
                    implicitHeight: screenTimeContent.implicitHeight + stPills.height + 22
                    PillTabBar {
                        id: stPills
                        anchors { top: parent.top; horizontalCenter: parent.horizontalCenter; topMargin: 12 }
                        tabs: [
                            { id: "0", icon: "today",      label: "Today" },
                            { id: "1", icon: "date_range", label: "Week"  },
                            { id: "2", icon: "apps",       label: "Apps"  }
                        ]
                        current: String(GlobalStates.hudScreenTab)
                        onTabSelected: id => GlobalStates.hudScreenTab = parseInt(id)
                    }
                    ScreenTimeContent {
                        id: screenTimeContent
                        anchors { left: parent.left; right: parent.right; top: stPills.bottom; topMargin: 8 }
                    }
                    } }
                }

                // ─ 6 · Essentials (NEW) ───────────────────────────────────
                // Quick toggles, battery + ROG power profile, system info.
                // Lives in the Home group alongside Dashboard and Screen Time.
                LazyStackPage {
                    Component { Item {
                        implicitHeight: essentialsContent.implicitHeight
                        EssentialsContent {
                            id: essentialsContent
                            anchors { left: parent.left; right: parent.right; top: parent.top }
                        }
                    } }
                }

                } // StackLayout contentStack
            } // Flickable contentFlick
        } // ColumnLayout mainCol
    } // Rectangle hudBg
}
