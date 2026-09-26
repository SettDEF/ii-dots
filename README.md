# ii — a quickshell desktop shell for Hyprland

A bar, dock, sidebars, overlays and a set of panels, written in QML for
[quickshell](https://quickshell.outfoxxed.me) on Hyprland.

```sh
git clone <this repo> quickshell-ii && cd quickshell-ii
./install.sh --dry-run          # see exactly what it would do
./install.sh                    # install as `ii`
qs -c ii
```

## Installing

The installer is deliberately non-destructive. It installs under a **config
name**, so an existing quickshell setup keeps working and you can run this one
beside it:

```sh
./install.sh -n ii-test -p minimal    # a throwaway copy, no packages touched
./install.sh -n ii-test --uninstall   # and gone again
```

It refuses to remove any directory it did not create, backs up anything it
would overwrite, and leaves packages, polkit rules and systemd units alone on
uninstall.

### Profiles

Most of this config is optional. Installing all of it on a machine that wants
a bar is how a config gets a reputation for being heavy.

| Profile | What it pulls in |
|---|---|
| `minimal` | the shell only — no packages installed at all |
| `core` | quickshell, Hyprland, Qt 6, the icon font |
| `recommended` *(default)* | + clipboard, network, audio, brightness, screenshots |
| `full` | + media tools, translation, time tracking |
| `rog` | + `asusctl` / `supergfxctl` for ASUS laptops |

```sh
./install.sh -p rog --polkit    # the lot, on an ASUS laptop
./install.sh --no-deps          # config only, manage packages yourself
```

`--polkit` is off by default and asks for root. It renders the rules in
`ii/scripts/*/polkit/*.in` with your username and install path — polkit expands
neither `$HOME` nor "whoever is installing", so those have to be written in.

`--dry-run` prints every action and changes nothing. It is worth running first.

## What needs what

The shell starts with very little. Features whose tools are missing stay
hidden rather than erroring:

- **Always** — quickshell, Hyprland, Qt 6 Declarative + 5Compat, Material
  Symbols
- **Most panels** — `libnotify`, `wl-clipboard`, NetworkManager, PipeWire +
  WirePlumber, `brightnessctl`, `grim`/`slurp`, `cliphist`, `hyprpicker`
- **ROG power and fan controls** — `asusctl`, `supergfxctl`
- **Never installed for you** — `warp-cli`, `nordvpn`, `virt-viewer`,
  `minimeters`. Personal tools; the toggles that drive them simply do not
  appear.

Wallpaper theming expects [`matugen`](https://github.com/InioX/matugen) if you
want colours to follow the wallpaper.

## Layout

```
ii/
  shell.qml          the entry point
  modules/ii/        bar, dock, sidebars, overlays, HUD — one directory each
  modules/common/    shared widgets, Appearance, Config
  services/          singletons: audio, network, players, calendar, …
  scripts/           helper scripts, polkit templates, systemd units
  docs/              notes, including a running backlog of known weaknesses
```

Singletons in `services/` are auto-discovered — **do not add a `services/qmldir`**.
Creating one overrides discovery and hides every other service.

## Portability

Paths come from `$HOME` at runtime rather than being baked in, so the config
works for any user. The two polkit files are the exception and are rendered at
install time.

## Known weaknesses

`ii/docs/not-finished-backlog.md` is kept honest: what has been measured, what
was ruled out and why, and what is still unexplained — including a ~1.4 GB
resident figure that is **not** a QML leak (the JS heap is 21 MB; it is roughly
one Mesa GL context per mapped surface).

## Licence

MIT. See `LICENSE`.
