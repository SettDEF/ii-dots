#!/usr/bin/env bash
# bootstrap.sh — from a fresh Arch install to this desktop, in one run.
#
# The audience is the terminal you are looking at immediately after
# archinstall: a base system, a user with sudo, networking, and nothing else.
# No desktop, no AUR helper, possibly no git. install.sh assumes all of that
# already exists; this is the step before it.
#
#   curl -fsSL <raw url>/bootstrap.sh -o bootstrap.sh
#   bash bootstrap.sh --dry-run        # read what it will do first
#   bash bootstrap.sh
#
# It is safe to re-run: every step checks whether it has already been done.
# Nothing is removed, and an existing ~/.config/hypr is never overwritten.
set -euo pipefail

REPO_URL="${QS_REPO_URL:-}"       # set by --repo, or detected from a clone
BRANCH="${QS_BRANCH:-main}"
CLONE_DIR="${QS_CLONE_DIR:-$HOME/.local/share/quickshell-ii-src}"
PROFILE="recommended"
NAME="ii"
DRY=0
ASSUME_YES=0
DO_HYPR=1
LOWEND=0

die()  { printf '\033[31merror\033[0m: %s\n' "$*" >&2; exit 1; }
info() { printf '\033[36m::\033[0m %s\n' "$*"; }
warn() { printf '\033[33mwarn\033[0m: %s\n' "$*" >&2; }
ok()   { printf '\033[32m ok\033[0m %s\n' "$*"; }
step() { printf '\n\033[1m── %s\033[0m\n' "$*"; }
run()  { if [ "$DRY" = 1 ]; then printf '   would: %s\n' "$*"; else "$@"; fi; }

usage() {
    cat <<EOF
bootstrap.sh — fresh Arch install to this desktop

  bash bootstrap.sh [options]

Options
      --repo URL     Where to clone this config from. Detected automatically
                     when you run this script from inside a clone.
      --branch NAME  Branch to clone.                        (default: main)
  -n, --name NAME    Config name; the shell runs as \`qs -c NAME\`. (default: ii)
  -p, --profile P    minimal | core | recommended | full | rog | low-end
                     Passed through to install.sh.     (default: recommended)
      --low-end      Tune for weak hardware. Passed through to install.sh.
      --no-hypr      Do not write a Hyprland config. Use this if you already
                     have one you want to keep using.
  -y, --yes          Do not stop for confirmation.
      --dry-run      Print every action, change nothing.
  -h, --help         This.

What it does, in order
  1. checks this is Arch, you are not root, and the network is up
  2. installs base-devel and git
  3. builds paru, if no AUR helper is present
  4. installs Hyprland, a terminal, fonts and the portals
  5. clones this config and hands over to its own install.sh
  6. writes a starter ~/.config/hypr, unless one is already there
  7. tells you how to start it

Re-running is safe: each step is skipped if it is already done.
EOF
}

while [ $# -gt 0 ]; do
    case "$1" in
        --repo)       REPO_URL="${2:?--repo needs a value}"; shift 2 ;;
        --branch)     BRANCH="${2:?--branch needs a value}"; shift 2 ;;
        -n|--name)    NAME="${2:?--name needs a value}"; shift 2 ;;
        -p|--profile) PROFILE="${2:?--profile needs a value}"; shift 2 ;;
        --low-end)    LOWEND=1; shift ;;
        --no-hypr)    DO_HYPR=0; shift ;;
        -y|--yes)     ASSUME_YES=1; shift ;;
        --dry-run)    DRY=1; shift ;;
        -h|--help)    usage; exit 0 ;;
        *)            die "unknown option: $1 (try --help)" ;;
    esac
done

# ── 1. Is this the machine we think it is? ──────────────────────────────────
step "Checks"

[ -f /etc/arch-release ] || die "this is not an Arch system.
       The package steps are pacman-specific. On another distro, install
       Hyprland and quickshell yourself and then run ./install.sh."

[ "$(id -u)" -ne 0 ] || die "do not run this as root.
       It installs into your home directory, and a root-owned ~/.config is a
       long afternoon. Run it as your normal user; it will ask for sudo when
       it needs it."

command -v sudo >/dev/null 2>&1 || die "sudo is not installed.
       As root: pacman -S sudo, then add your user to the wheel group and
       uncomment the wheel line in visudo."

# Not in a dry run: --dry-run must be answerable without typing a password,
# or nobody reads it before running the real thing.
if [ "$DRY" != 1 ]; then
    sudo -v || die "sudo failed. Your user needs to be able to run sudo."
fi

# A fresh archinstall can leave a keyring that predates the mirrors, and the
# first -S then fails with an unhelpful signature error.
if ! timeout 10 ping -c1 -W2 archlinux.org >/dev/null 2>&1; then
    warn "cannot reach archlinux.org. If your network is up and only ICMP is"
    warn "blocked, this is fine; otherwise fix networking first."
fi
ok "Arch, non-root, sudo available"

if [ "$DRY" = 1 ]; then warn "dry run — nothing will be changed"; fi

if [ "$ASSUME_YES" != 1 ] && [ "$DRY" != 1 ]; then
    echo
    info "About to install a desktop onto this machine, as profile '$PROFILE'."
    read -rp "   continue? [y/N] " a
    [[ "$a" =~ ^[Yy]$ ]] || { warn "nothing done"; exit 0; }
fi

# ── 2. The toolchain everything else needs ──────────────────────────────────
step "Base tools"
run sudo pacman -Sy --needed --noconfirm base-devel git
ok "base-devel, git"

# ── 3. An AUR helper ────────────────────────────────────────────────────────
# quickshell is not in the official repos, so this is not optional. Built by
# hand exactly once, because there is no helper yet to install the helper.
step "AUR helper"
HELPER=""
for h in paru yay; do command -v "$h" >/dev/null 2>&1 && { HELPER="$h"; break; }; done
if [ -n "$HELPER" ]; then
    ok "$HELPER is already installed"
else
    info "no AUR helper found; building paru from source"
    if [ "$DRY" = 1 ]; then
        printf '   would: makepkg -si paru-bin in a temporary directory\n'
        HELPER="paru"
    else
        tmp="$(mktemp -d)"
        git clone --depth 1 https://aur.archlinux.org/paru-bin.git "$tmp/paru-bin"
        ( cd "$tmp/paru-bin" && makepkg -si --noconfirm )
        rm -rf "$tmp"
        command -v paru >/dev/null 2>&1 || die "paru did not install; build it by hand and re-run"
        HELPER="paru"
        ok "paru built and installed"
    fi
fi

# ── 4. The desktop itself ───────────────────────────────────────────────────
# Deliberately short. This is what it takes to get a session that starts, log
# in and see a shell; install.sh adds the per-feature tools for its profile.
step "Desktop packages"
SESSION_PKGS=(
    hyprland quickshell                      # the compositor and the shell
    qt6-declarative qt6-5compat qt6-imageformats
    ttf-material-symbols-variable ttf-jetbrains-mono-nerd
    xdg-desktop-portal-hyprland xdg-desktop-portal-gtk
    polkit-gnome                             # so anything needing root can ask
    pipewire pipewire-pulse wireplumber      # audio, before first login
    networkmanager
    foot                                     # a terminal that always works
)
missing=()
for p in "${SESSION_PKGS[@]}"; do pacman -Qq "$p" >/dev/null 2>&1 || missing+=("$p"); done
if [ ${#missing[@]} -eq 0 ]; then
    ok "all desktop packages already present"
else
    info "installing: ${missing[*]}"
    run "$HELPER" -S --needed --noconfirm "${missing[@]}"
fi

# NetworkManager is the one that has to be running before you log out of the
# TTY, or the new session has no network and nothing explains why.
if ! systemctl is-enabled NetworkManager >/dev/null 2>&1; then
    info "enabling NetworkManager"
    run sudo systemctl enable --now NetworkManager
else
    ok "NetworkManager already enabled"
fi

# ── 5. This config ──────────────────────────────────────────────────────────
step "The config"
SRC=""
# Running from inside a clone is the common case: use it, and learn the URL
# from it so --repo is not needed.
if [ -d "$(dirname "${BASH_SOURCE[0]}")/ii" ]; then
    SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    ok "using the clone this script is in: $SRC"
    [ -n "$REPO_URL" ] || REPO_URL="$(git -C "$SRC" remote get-url origin 2>/dev/null || true)"
elif [ -n "$REPO_URL" ]; then
    if [ -d "$CLONE_DIR/.git" ]; then
        info "updating $CLONE_DIR"
        run git -C "$CLONE_DIR" pull --ff-only
    else
        info "cloning $REPO_URL -> $CLONE_DIR"
        run git clone --depth 1 -b "$BRANCH" "$REPO_URL" "$CLONE_DIR"
    fi
    SRC="$CLONE_DIR"
else
    die "nothing to install from.
       Either run this script from inside a clone of the config, or pass
       --repo <url> so it can fetch one."
fi

INSTALL_ARGS=(-n "$NAME" -p "$PROFILE" -y)
[ "$LOWEND" = 1 ] && INSTALL_ARGS+=(--low-end)
[ "$DRY" = 1 ] && INSTALL_ARGS+=(--dry-run)
info "handing over to install.sh ${INSTALL_ARGS[*]}"
if [ "$DRY" = 1 ]; then
    bash "$SRC/install.sh" "${INSTALL_ARGS[@]}" || true
else
    bash "$SRC/install.sh" "${INSTALL_ARGS[@]}"
fi

# ── 6. A Hyprland config to start it from ───────────────────────────────────
# The shell is a layer-shell client: without a compositor config that launches
# it, a fresh install logs into an empty grey screen and looks broken. This
# writes the smallest config that starts the shell and gives you the keys to
# reach it — and never touches one that is already there.
step "Hyprland config"
HYPR_DIR="$HOME/.config/hypr"
if [ "$DO_HYPR" != 1 ]; then
    info "skipping (--no-hypr). Add this to your own config:"
    info "  exec-once = qs -c $NAME"
elif [ -e "$HYPR_DIR/hyprland.conf" ]; then
    warn "$HYPR_DIR/hyprland.conf already exists — left untouched."
    warn "To use this shell from it, add:  exec-once = qs -c $NAME"
elif [ -d "$SRC/hypr" ]; then
    info "installing the starter config to $HYPR_DIR"
    run mkdir -p "$HYPR_DIR"
    run cp -r "$SRC/hypr/." "$HYPR_DIR/"
    [ "$DRY" = 1 ] || sed -i "s/@SHELL_NAME@/$NAME/g" "$HYPR_DIR/hyprland.conf"
    ok "written"
else
    warn "no hypr/ directory in $SRC, so no compositor config was written."
    warn "Hyprland will start with its own defaults; add to ~/.config/hypr/hyprland.conf:"
    warn "  exec-once = qs -c $NAME"
fi

# ── 7. What to do now ───────────────────────────────────────────────────────
step "Done"
cat <<EOF

  Start it:      Hyprland
  From a TTY, after logging in. There is no display manager in this setup;
  if you want one, install greetd or sddm separately.

  First launch walks you through language, keyboard layout and the look.
  All of it is in the settings afterwards — Super+I, or: qs -c $NAME ipc ...

  Weak machine?  Settings -> Performance, or re-run with --low-end.
  Remove it:     $SRC/install.sh -n $NAME --uninstall

EOF
