#!/usr/bin/env bash
# bootstrap.sh — from a fresh Arch install to this desktop, in one run.
#
# The audience is the terminal you are looking at immediately after
# archinstall: a base system, a user with sudo, networking, and nothing else.
# No desktop, no AUR helper, possibly no git. install.sh assumes all of that
# already exists; this is the step before it.
#
#   curl -fsSL <raw url>/bootstrap.sh | bash
#
# Piped like that, stdin is the script itself, so every prompt is read from
# /dev/tty instead — a plain `read` there swallows the rest of the program and
# the installer dies halfway through. Downloading first works too, and is the
# honest way to read it before running it:
#
#   curl -fsSL <raw url>/bootstrap.sh -o bootstrap.sh
#   bash bootstrap.sh --dry-run        # see everything it would do
#   bash bootstrap.sh
#
# Do NOT run it with sudo. It installs into your home directory; it asks for
# sudo only where a package or a systemd unit genuinely needs root.
#
# It is safe to re-run: every step checks whether it has already been done.
# Nothing is removed, and an existing ~/.config/hypr is never overwritten.
set -euo pipefail

REPO_URL="${QS_REPO_URL:-}"       # set by --repo, or detected from a clone
BRANCH="${QS_BRANCH:-master}"
DEFAULT_REPO="${QS_DEFAULT_REPO:-https://github.com/SettDEF/ii-dots}"
CLONE_DIR="${QS_CLONE_DIR:-$HOME/.local/share/quickshell-ii-src}"
PROFILE="recommended"
CHOSE_PROFILE=0
NAME="ii"
DRY=0
ASSUME_YES=0
DO_HYPR=1
LOWEND=0

# ── Presentation ────────────────────────────────────────────────────────────
# Plain ANSI, no dialog/whiptail: neither is in the Arch base install, and a
# first-run installer that must install its own UI first is not a first-run
# installer. Degrades to unstyled text when stdout is not a terminal.
if [ -t 1 ]; then
    B=$'\033[1m'; DIM=$'\033[2m'; R=$'\033[0m'
    RED=$'\033[31m'; GRN=$'\033[32m'; YEL=$'\033[33m'; CYN=$'\033[36m'
else
    B=""; DIM=""; R=""; RED=""; GRN=""; YEL=""; CYN=""
fi

banner() {
    # One width, one padding calculation: hand-counted box drawing drifts the
    # moment the text changes, and the escape codes are not printable width.
    local text="ii — a quickshell desktop for Hyprland"
    local w=52 pad
    pad=$(( w - ${#text} - 3 ))
    printf '\n%s╭%s╮%s\n' "$CYN" "$(printf '─%.0s' $(seq 1 $w))" "$R"
    printf '%s│%s  %s%s%s%*s%s│%s\n' "$CYN" "$R" "$B" "$text" "$R" "$pad" "" "$CYN" "$R"
    printf '%s╰%s╯%s\n' "$CYN" "$(printf '─%.0s' $(seq 1 $w))" "$R"
}

die()  { printf '%serror%s: %s\n' "$RED" "$R" "$*" >&2; exit 1; }
info() { printf '%s::%s %s\n' "$CYN" "$R" "$*"; }
warn() { printf '%swarn%s: %s\n' "$YEL" "$R" "$*" >&2; }
ok()   { printf '%s  ok%s %s\n' "$GRN" "$R" "$*"; }
step() { printf '\n%s── %s%s\n' "$B" "$*" "$R"; }
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
        -p|--profile) PROFILE="${2:?--profile needs a value}"; CHOSE_PROFILE=1; shift 2 ;;
        --low-end)    LOWEND=1; shift ;;
        --no-hypr)    DO_HYPR=0; shift ;;
        -y|--yes)     ASSUME_YES=1; shift ;;
        --dry-run)    DRY=1; shift ;;
        -h|--help)    usage; exit 0 ;;
        *)            die "unknown option: $1 (try --help)" ;;
    esac
done

banner

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

# ── The menu ────────────────────────────────────────────────────────────────
# Shown when nothing was chosen on the command line and there is a terminal to
# read from. Piped from curl, stdin is the SCRIPT, so the prompts are read from
# /dev/tty instead — otherwise the first read swallows the rest of the program.
ask() {                 # ask <prompt> <default>
    local p="$1" d="$2" a=""
    [ -r /dev/tty ] || { printf '%s' "$d"; return; }
    printf '%s%s%s [%s] ' "$B" "$p" "$R" "$d" > /dev/tty
    read -r a < /dev/tty || a=""
    printf '%s' "${a:-$d}"
}

menu() {
    local choice
    while true; do
        printf '\n  %sWhat to install%s\n\n' "$B" "$R"
        printf '   1  %sRecommended%s   the shell, and the tools most panels need\n' "$GRN" "$R"
        printf '   2  Minimal       the shell only, no extra packages\n'
        printf '   3  Full          everything, including media and translation tools\n'
        printf '   4  Low-end       recommended, with the effects turned off\n'
        printf '   5  ROG laptop    full, plus asusctl and supergfxctl\n\n'
        printf '   n  Config name   %s%s%s\n' "$DIM" "$NAME" "$R"
        printf '   h  Hyprland      %s%s%s\n' "$DIM" "$([ "$DO_HYPR" = 1 ] && echo "write a starter config" || echo "leave mine alone")" "$R"
        printf '   d  Dry run       %sshow what would happen, change nothing%s\n' "$DIM" "$R"
        printf '   q  Quit\n\n'
        choice=$(ask "  Choice, or Enter to install" "")
        case "$choice" in
            1) PROFILE=recommended; LOWEND=0; return ;;
            2) PROFILE=minimal;     LOWEND=0; return ;;
            3) PROFILE=full;        LOWEND=0; return ;;
            4) PROFILE=recommended; LOWEND=1; return ;;
            5) PROFILE=rog;         LOWEND=0; return ;;
            n) NAME=$(ask "  Config name" "$NAME") ;;
            h) DO_HYPR=$([ "$DO_HYPR" = 1 ] && echo 0 || echo 1) ;;
            d) DRY=1; return ;;
            q) warn "nothing done"; exit 0 ;;
            "") return ;;
            *) warn "not an option: $choice" ;;
        esac
    done
}

if [ "$ASSUME_YES" != 1 ] && [ "$DRY" != 1 ] && [ "$CHOSE_PROFILE" != 1 ] && [ -r /dev/tty ]; then
    menu
fi

printf '\n'
info "profile: ${B}$PROFILE${R}$([ "$LOWEND" = 1 ] && printf ' (low-end)')   name: ${B}$NAME${R}"
if [ "$ASSUME_YES" != 1 ] && [ "$DRY" != 1 ]; then
    a=$(ask "  Install now?" "y")
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
# --version, not command -v. An installed helper that cannot start still
# satisfies "exists", and then every package after this point fails quietly.
for h in paru yay; do "$h" --version >/dev/null 2>&1 && { HELPER="$h"; break; }; done
if [ -n "$HELPER" ]; then
    ok "$HELPER is already installed"
else
    # Present but broken is the paru-bin/libalpm case. Clear it out first, or
    # rebuilding paru-bin just reinstalls the same unusable binary.
    PARU_BIN_BROKEN=0
    if command -v paru >/dev/null 2>&1; then
        warn "paru is installed but will not start; replacing it"
        [ "$DRY" = 1 ] || sudo pacman -Rdd --noconfirm paru-bin paru-bin-debug >/dev/null 2>&1 || true
        PARU_BIN_BROKEN=1
    fi
    info "no working AUR helper; installing paru"
    if [ "$DRY" = 1 ]; then
        printf '   would: makepkg -si paru-bin, then paru from source if it will not run\n'
        HELPER="paru"
    else
        build_aur() {   # build_aur <aur package name>
            local pkg="$1" tmp
            tmp="$(mktemp -d)"
            git clone --depth 1 "https://aur.archlinux.org/$pkg.git" "$tmp/$pkg" \
                && ( cd "$tmp/$pkg" && makepkg -si --noconfirm )
            local rc=$?
            rm -rf "$tmp"
            return $rc
        }

        # paru-bin first: it is a download rather than a Rust build, so it is
        # minutes faster when it works. Skipped if we just removed a broken one.
        [ "$PARU_BIN_BROKEN" = 1 ] || build_aur paru-bin || true

        # Existing is not the same as working. paru-bin is linked against the
        # libalpm that was current when it was PACKAGED, so on a system whose
        # pacman differs it installs cleanly and then cannot start:
        #   paru: error while loading shared libraries: libalpm.so.15
        # Checking only for the file let that through, and every package after
        # this point silently did not install.
        if ! paru --version >/dev/null 2>&1; then
            warn "paru-bin will not run here (libalpm mismatch); building from source"
            sudo pacman -R --noconfirm paru-bin paru-bin-debug >/dev/null 2>&1 || true
            run sudo pacman -S --needed --noconfirm rust
            build_aur paru || die "could not build paru; build an AUR helper by hand and re-run"
        fi

        paru --version >/dev/null 2>&1 || die "paru installed but will not run; build one by hand and re-run"
        HELPER="paru"
        ok "paru installed and working"
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
elif [ -n "$(command -v git)" ] && [ -r /dev/tty ]; then
    # Piped from the web with no clone to work from: ask, rather than dying
    # with an instruction the user cannot act on mid-pipe.
    warn "no clone here and no --repo given."
    REPO_URL=$(ask "  Repository to install from" "$DEFAULT_REPO")
    [ -n "$REPO_URL" ] || die "no repository; nothing to install"
    info "cloning $REPO_URL -> $CLONE_DIR"
    run git clone --depth 1 -b "$BRANCH" "$REPO_URL" "$CLONE_DIR"
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
elif [ -e "$HYPR_DIR/hyprland.conf" ] || [ -e "$HYPR_DIR/hyprland.lua" ]; then
    warn "$HYPR_DIR already has a Hyprland config — left untouched."
    warn "To use this shell from it, add:  exec-once = qs -c $NAME"
    warn "and see $SRC/hypr/ for what else the shell expects."
elif [ -d "$SRC/hypr" ]; then
    info "installing the starter config to $HYPR_DIR"
    run mkdir -p "$HYPR_DIR"
    run cp -r "$SRC/hypr/." "$HYPR_DIR/"
    # @SHELL_NAME@ appears in the Lua binds and in the cheatsheet's conf, so
    # substitute across the tree rather than in one named file.
    if [ "$DRY" != 1 ]; then
        grep -rl '@SHELL_NAME@' "$HYPR_DIR" 2>/dev/null \
            | while IFS= read -r f; do sed -i "s/@SHELL_NAME@/$NAME/g" "$f"; done
    fi
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
