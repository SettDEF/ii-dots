# Beating Garuda

Garuda feels professional because of what sits *behind* its welcome screen: a
set of tools that do real system work, with one visual language and one place to
find them. The welcome window is only a launcher.

This is the gap analysis and the order to close it in.

## What Garuda actually ships

| Tool | What it does |
|---|---|
| **Welcome** | A hub. Launches the others, links to wiki/forum/chat/donate, autostart toggle. |
| **Assistant** | Update system · refresh mirrorlist · clear package cache · remove orphans · clear the pacman db lock · reinstall all packages · refresh keyring · edit repos · enable/disable systemd services · Btrfs/Timeshift snapshots · diagnostics and log upload |
| **Settings Manager** | Kernels, drivers, locale, keyboard, time, users |
| **Gamer** | Bulk-installs launchers, Wine/Proton, emulators, controller tools, Vulkan drivers |
| **Network Assistant** | Reset NetworkManager, change DNS, install network drivers |
| **Boot Options** | Kernel parameters, GRUB |

## Where we stand

| Capability | State |
|---|---|
| Settings, with a nav rail and 11 pages | **done** |
| Welcome, 11 sections, section rail, finish action | **done** |
| Shell self-update, notify + auto-apply, honours a copy-install | **done** |
| Optional-tool detection (`SystemRequirements`, 21 tools, ASUS-aware) | **done** |
| Installer: ISO → partitions → base → desktop, menu-driven | **done** |
| `SystemSettings` — pkexec-backed writes to /etc (timezone, locale, keymap) | **done**, and it is the pattern every privileged action should reuse |
| `Updates` — counts pacman updates | **partial**: counts only, cannot act |
| Wi-Fi panel | **partial**: connects, cannot diagnose or repair |
| Package bundles (the "Gamer" idea, generalised) | **missing** |
| Maintenance actions (cache, orphans, keyring, mirrors) | **missing** |
| Service management UI | **partial**: `ServicesConfig` toggles the shell's own services, not systemd |
| Snapshots | **missing** |
| Kernel / driver management | **missing** |
| Community links | **missing**, and blocked: there is nowhere to link to |

## The plan, in order

### 1. Assistant — the one that matters

A new app beside Settings and Welcome, same `SectionRail`, sections:

- **Maintenance** — update system · refresh mirrors · clear package cache
  (`paccache -r`) · remove orphans · clear db lock · refresh keyring
- **Packages** — bundles: gaming, media, development, office. This is Gamer,
  generalised and less silly.
- **Services** — real systemd units, enable/disable/start/stop
- **Snapshots** — only if snapper or timeshift is present; hidden otherwise
- **Diagnostics** — version, hardware, what is missing, copy a report

Every destructive action shows the exact command first and runs it in a terminal
the user can watch. A shell that silently runs `pacman -Rns` on someone's
machine is not professional, it is alarming.

### 2. Network Assistant

Fold into Assistant rather than a separate app: restart NetworkManager, flush
and set DNS, forget and re-add a network, show the live link detail `Network`
already collects.

### 3. Make `Updates` act, not just count

It knows the count. It should be able to run the update through the same
terminal-visible path as Assistant.

### 4. Community

Blocked, not missing: enable GitHub Discussions, then the welcome screen's links
have somewhere to point.

## Where we can beat it

Garuda's tools are separate GTK/Qt apps bolted to a distro. Ours live inside the
shell, which buys things Garuda structurally cannot do:

- **One visual language.** Assistant, Settings and Welcome share `SectionRail`,
  `ContentSection` and the theme that follows the wallpaper. Garuda's tools do
  not even agree with each other.
- **It already knows the machine.** `SystemRequirements` knows what is missing,
  `Network` knows the real dBm and retry count, `Battery`, `AudioProfiles` and
  the ROG services know the hardware. Garuda's assistant has to ask the system
  from scratch every time.
- **Updates that are honest about a dirty tree.** Ours refuses to stomp local
  edits. Garuda's update button does not know you edit your config.
- **It installs itself.** `iso-install.sh` goes from the Arch ISO to a running
  desktop; Garuda needs a whole ISO to do that.
- **Not a distro.** It runs on any Arch. Nobody has to leave their install.

## Not worth copying

- **Boot Options.** GRUB parameters from a desktop shell is a way to make a
  machine unbootable.
- **Kernel switching.** Same.
- **Log upload to a paste service.** Copy to clipboard instead; do not ship
  someone's journal to a third party by default.
