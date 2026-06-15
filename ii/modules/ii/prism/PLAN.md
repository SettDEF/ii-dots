# Prism — Plan

A wallpaper + theme command center for the Quickshell config.
Mashes the wallpaper-browsing of **skwd-wall** with the color-theming UX of **Aether**, all inside the existing matugen pipeline.

Alternate names if Prism is taken: Tincture, Halcyon, Iris, Chroma, Lumen.

---

## 1. Goals

1. One place to **browse** wallpapers from local + wallhaven + reddit.
2. One place to **theme** the desktop: extraction modes, presets, live filter sliders.
3. Apply via the existing scripts (`switchwall.sh`, `applycolor.sh`, matugen).
4. No new daemon, no Go backend — pure QML + bash, fits the rest of `modules/ii/*`.

Non-goals (for v1):
- Animated/video wallpapers (mp4/webm/gif).
- Steam Workshop / Wallpaper Engine.
- Multi-monitor per-wallpaper assignment.
- Ollama auto-tagging.

---

## 2. Surface

- New module dir: `modules/ii/prism/`
- Trigger: own `GlobalShortcut name: "prismToggle"` (suggested keybind: `$mod+P`)
- Also reachable as a **section in Nexus** (`Nexus.qml`'s `sections` list gets a `prism` entry alongside launcher / themes / cheatsheet). Internal `NexusThemes.qml` stays as a thin embed of `PrismHome.qml`.
- Window: `PanelWindow` like Nexus (≈900×600), focus-grabbed, dismissable on outside click.

---

## 3. Module layout

```
modules/ii/prism/
├── PLAN.md                   ← this file
├── qmldir
├── Prism.qml                 ← PanelWindow shell + GlobalShortcut
├── PrismHome.qml             ← top-level layout (sidebar + content)
├── browse/
│   ├── BrowseTab.qml         ← source switcher + grid
│   ├── WallpaperGrid.qml     ← reusable thumbnail grid
│   ├── WallpaperCard.qml     ← single tile (preview + actions)
│   └── SearchBar.qml         ← query + sort + nsfw toggle
├── sources/
│   ├── LocalSource.qml       ← scans Config.options.background.wallpaperDirs
│   ├── WallhavenSource.qml   ← https://wallhaven.cc/api/v1/search
│   └── RedditSource.qml      ← https://www.reddit.com/r/{sub}/hot.json
├── theme/
│   ├── ThemeTab.qml          ← extraction modes + presets + sliders
│   ├── ExtractionModes.qml   ← Aether-style: Normal/Mono/Analogous/Pastel/Material/Colorful/Muted/Bright
│   ├── PresetGrid.qml        ← Dracula / Nord / Gruvbox / Catppuccin / Sakura / etc.
│   └── FilterPanel.qml       ← live sliders (delegates to walltune script)
└── services/
    └── PrismState.qml        ← Singleton: last query, cached results, in-flight processes
```

---

## 4. Sources (data layer)

All three implement the same interface so `WallpaperGrid` is source-agnostic:

```qml
QtObject {
    property var items        // [{ id, thumbUrl, fullUrl, title, source, meta }]
    property bool loading
    property string error
    function search(query, page) { ... }
    function next() { ... }
}
```

| Source | Endpoint / cmd | Auth |
|---|---|---|
| Local | `find ~/Pictures/Wallpapers -type f -iregex '.*\.(jpe?g\|png\|webp)'` | none |
| Wallhaven | `https://wallhaven.cc/api/v1/search?q=&page=&sorting=&purity=` | optional API key for NSFW |
| Reddit | `https://www.reddit.com/r/{sub}/hot.json?limit=50&after=` | none (public JSON) |

Reddit subs are a list in config: `Config.options.prism.redditSubs = ["wallpapers", "ImaginaryLandscapes", ...]`.

Thumbnails cached in `~/.cache/quickshell/prism/thumbs/`.

---

## 5. Apply pipeline

1. User clicks `WallpaperCard` → "Apply".
2. If remote: `curl -L -o ~/Pictures/Wallpapers/prism/<id>.<ext>` (via `Process`).
3. Run `${Directories.wallpaperSwitchScriptPath} --image <path>` (already wired to matugen + applycolor.sh — reused, untouched).
4. If user picked an extraction mode other than Auto: pass `--type scheme-<mode>` (the same flag the settings menu now uses; this is the field that crashed earlier on `scheme-content` — now fixed).
5. If filter sliders are non-default: pipe through the magick command from `WallTuneContent.qml::reprocess()` first, then matugen on the processed file.

---

## 6. Theme tab

Three rows:

1. **Extraction modes** — 8 chips. Maps to:
   - Auto → no `--type`
   - Mono → `scheme-monochrome`
   - Analogous / Pastel / Material / Colorful / Muted / Bright → custom matugen extra args (or pre-tinted version of the wall via magick before matugen).
2. **Presets** — Aether-style fixed palettes. Bypass matugen entirely; write color JSON directly to `~/.local/state/quickshell/user/generated/colors.json` and call `applycolor.sh`. ~10 hand-picked presets (Dracula, Nord, Gruvbox, Catppuccin, Tokyo Night, Sakura, Rose Pine, Everforest, Solarized, Mono).
3. **Filters** — sliders (brightness/saturation/hue/contrast/sharpness/grain/temperature). Delegates to the existing WallTune logic — share the function, don't duplicate.

---

## 7. Config additions (`modules/common/Config.qml`)

```qml
property JsonObject prism: JsonObject {
    property string wallhavenApiKey: ""
    property bool allowNsfw: false
    property var redditSubs: ["wallpapers", "ImaginaryLandscapes", "EarthPorn"]
    property string downloadDir: "~/Pictures/Wallpapers/prism"
    property int gridColumns: 4
    property string defaultSource: "local"   // local | wallhaven | reddit
}
```

⚠ Do **not** add `property var` inside the nested JsonObject — the `playerColors` crash showed Quickshell's deserializer trips on QVariant fields under nested JsonObjects on Qt 6.11. Use `property string` with JSON-encoded text if a map is needed.

---

## 8. Implementation order

1. `Prism.qml` shell + GlobalShortcut + visibility plumbing (mirror of `Nexus.qml`).
2. `LocalSource` + `WallpaperGrid` + `WallpaperCard` — get a working browse-and-apply with local files.
3. `WallhavenSource` (curl + JSON parse via `Process` SplitParser).
4. `RedditSource`.
5. Theme tab: extraction modes (matugen flags only).
6. Theme tab: presets (direct color injection).
7. Theme tab: filter sliders (reuse WallTune).
8. Nexus integration (add as a section).
9. `Config.qml` additions + a `QuickConfig`-style settings panel for Prism (api key, subs, dirs).

Each step is a deliverable on its own — Prism is usable after step 2.

---

## 9. Risks / unknowns

- **Wallhaven rate limit**: 45 req/min. Debounce search input (~300ms).
- **Reddit anti-bot**: requests need a non-empty UA. Use the same UA as `Config.options.networking.userAgent`.
- **Quickshell JSON adapter bug**: see §7 — already bit us once.
- **Image cache size**: prune `~/.cache/quickshell/prism/thumbs/` when over N MB (cron via `services/PrismState.qml` Component.onCompleted).

---

## 10. Open questions for you

1. Keybind for the toggle (`$mod+P`? `$mod+Shift+W`?).
2. Should presets fully override matugen or just seed it (Aether does both)?
3. Filter sliders: live preview on the card, or only after Apply?
4. Want a "favorites" feature (star a wallpaper → goes to a separate Local subfolder)?
