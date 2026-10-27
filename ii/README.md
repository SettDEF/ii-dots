# ii — working on the shell

A one-page map for changing this config. Installing it is in `../README.md`.

## Run, reload, check

- The shell runs as `qs -c ii` and **reloads itself on every save**. Don't
  restart or signal it.
- `~/.scripts/apps/quickshell/qs-check <file.qml>` — lint the file, reload, report only
  *new* errors.
- `qs log -c ii` — the live log.
- `~/.scripts/showme dock | notify 'text' | open <panel> | layer <name>` —
  bring something up, capture just the shell's own layer to `/tmp/showme/`,
  put it back. It refuses when a fullscreen window would hide it.
- `qs -c ii ipc show` — every IPC target (`open`, `close`, `toggle` …).

## Where things live

| Path | What |
|---|---|
| `shell.qml` | entry point |
| `modules/ii/<name>/` | one directory per surface: `bar`, `dock`, `sidebarLeft`, `notificationPopup`, `overlay`, `hud` … |
| `modules/common/` | `Appearance` (colours, sizes), `Config`, shared `widgets/`, `functions/` |
| `services/` | singletons (audio, notifications, places, downloads, badges …), auto-discovered — never add a `qmldir` |
| `scripts/` | helpers the shell calls (colours, Discord plugin, fs, hypr …) |
| `GlobalStates.qml` | open/closed state of panels |

## Colours

Everything comes from **tinct** (`~/.config/tinct/config.toml`): the wallpaper
palette is rendered into the shell, terminals, GTK, Discord, websites and more.
Use `Appearance.colors.*` roles in QML, never a hex.

Websites: `~/.config/tinct/templates/firefox/theme.user.css` (Stylus) plus the
`tinct-live` userscript for live colours, served on `http://localhost:8787`.
`~/.scripts/apps/browser/sitevars <site> --check` shows a site's real colour variables and
verifies its section.

## Gotchas

- Edit Hyprland bindings in `~/.config/hypr/custom/*.conf` **and** the
  generated `lua/custom/*.lua`; the Lua is regenerated from the `.conf`.
- Two declarations of `Component.onCompleted` on one object: the second
  silently replaces the first.
- A widget used in a file needs its module imported there (`StyledText` needs
  `qs.modules.common.widgets`), or the whole surface fails to load.
- `pgrep -f pattern` matches its own command line; use `pgrep -x`.
- Scripts started via `#!/usr/bin/env bash` are named "bash" — name them
  (`printf %s name > /proc/$$/comm`) or autostart guards start duplicates.
