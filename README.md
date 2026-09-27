# ii — a quickshell desktop shell for Hyprland

A bar, dock, sidebars, overlays and a set of panels, written in QML for
[quickshell](https://quickshell.outfoxxed.me) on Hyprland.

## Install

**From the Arch ISO**, with nothing installed yet. Four questions, then it
partitions, installs Arch and this desktop, and you reboot into it:

```sh
curl -fsSL https://github.com/SettDEF/ii-dots/raw/master/iso-install.sh | bash
```

It **erases the disk you point it at**, and makes you type the path back before
it does. `--dry-run` prints the whole plan and changes nothing — worth running
first, and it works from any machine, not just the ISO. `--disk` and `--yes`
together skip every prompt. UEFI and BIOS, ext4 or `--fs btrfs` (with @/@home/
@log/@cache subvolumes), zram instead of a swap partition.

> Built on `pacstrap`/`genfstab`/`arch-chroot`, not archinstall, whose config
> schema changes between releases. **Not yet tested on real hardware or in a
> VM** — read the dry-run before trusting it with a disk.

**From a fresh Arch install**, once you have a network — this fetches packages,
clones the repo and walks you through locale, keyboard layout and profile:

```sh
curl -fsSL https://github.com/SettDEF/ii-dots/raw/master/bootstrap.sh | bash
```

It reads its prompts from the terminal rather than from the pipe, so
`curl | bash` behaves the same as running it from a file. `--yes` takes the
defaults and asks nothing; `--dry-run` prints every action and changes nothing.

**If you already have a desktop**, clone it and look before you leap:

```sh
git clone https://github.com/SettDEF/ii-dots.git quickshell-ii && cd quickshell-ii
./install.sh --dry-run          # see exactly what it would do
./install.sh                    # install as `ii`
qs -c ii
```

## Install options

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
| `low-end` | the same tools as `recommended`, with the effects turned off |

```sh
./install.sh -p rog --polkit    # the lot, on an ASUS laptop
./install.sh --no-deps          # config only, manage packages yourself
```

`--polkit` is off by default and asks for root. It renders the rules in
`ii/scripts/*/polkit/*.in` with your username and install path — polkit expands
neither `$HOME` nor "whoever is installing", so those have to be written in.

`--dry-run` prints every action and changes nothing. It is worth running first.

### Old and slow machines

Everything expensive in this config already had a switch; what was missing was
a preset that knows which switches matter. `--low-end` is that preset, and it
combines with any profile:

```sh
./install.sh -p low-end          # recommended tools, effects off
./install.sh -p full --low-end   # all the tools, effects still off
```

The target is roughly a 2013 laptop — Haswell, Intel HD 4400, 4GB of DDR3, a
1366x768 panel. The shell starts fine on one; it is the effects that make it
unusable, and they are not evenly expensive. In rough order of what it buys:

- **the lock screen blur** — `radius: 100` means `samples: 201`, i.e. 201
  texture fetches per pixel of the whole screen, about 211 million a frame at
  1366x768. This one is the difference between a lock screen and a slideshow.
- **the wallpaper effect** — a full-screen fragment shader, redrawn every frame
- **wallpaper parallax** — rescales the wallpaper on every workspace switch
- **transparency and the background tint** — full-screen blends the compositor
  cannot skip
- **keeping the right sidebar loaded** — resident size here is roughly one Mesa
  GL context per mapped surface, so a surface kept alive for latency costs real
  RAM on a 4GB machine
- **the bar visualizer** — runs cava plus a repainting spectrum whenever audio
  plays
- **fake screen rounding, workspace switch flash, polling intervals** — small
  individually, and free to give up on a machine this size

The dock stays off, because its window previews are a `ScreencopyView` per
window at a 35ms interval, which is the most expensive thing in the config and
has no switch short of the dock itself.

These are ordinary settings, so none of it is a one-way door: change any of
them back in the settings panel. They are written to
`~/.config/illogical-impulse/config.json`, which is shared between installs and
so is **not** isolated by `-n NAME`. An existing config is merged into, not
replaced, and backed up first.

Untested on a machine that old — the reasoning is from what the code does, not
from a benchmark on 2013 hardware.

## Updating

The shell knows about the checkout it runs out of. **Settings -> System ->
Shell updates** checks a remote branch on a timer, says how far behind you are
and can pull.

Pulls are `--ff-only` and are skipped while the tree is dirty. This config is
meant to be edited by the person running it, so an update that stashes your
work would be worse than no update at all — commit or stash first, and the
button un-greys. Automatic installs are off by default; notifications are on.

```sh
qs -c ii ipc call shellUpdate check     # same check, from a script
qs -c ii ipc call shellUpdate status    # JSON: behind, dirty, latest, error
```

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

## Credits

Built on [quickshell](https://quickshell.outfoxxed.me) and Hyprland.

The config directory and the settings file path are still named
`illogical-impulse`, after [end-4/dots-hyprland](https://github.com/end-4/dots-hyprland),
which is where this started out. [caelestia-dots/shell](https://github.com/caelestia-dots/shell)
was a reference for parts of the service layer.

## Licence

MIT. See `LICENSE`.
