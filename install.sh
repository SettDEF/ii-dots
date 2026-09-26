#!/usr/bin/env bash
# install.sh — install this quickshell configuration without eating whatever
# you already have.
#
# The default is deliberately non-destructive: it installs under a config NAME
# (`qs -c <name>`), so an existing quickshell setup keeps working and you can
# run this one alongside it and delete it again cleanly. Nothing outside the
# paths printed by --dry-run is touched.
#
# Profiles exist because most of this config is optional. The bar, dock and
# panels need very little; the ROG power controls need asusctl; the finance
# and net tools need a Rust toolchain. Installing all of it on a machine that
# wants a bar is how a config gets a reputation for being heavy.
set -euo pipefail

SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NAME="ii"
PROFILE="recommended"
DEST=""
DRY=0
DO_DEPS=1
DO_POLKIT=0
DO_UNINSTALL=0
ASSUME_YES=0

# ── Dependencies, by profile ────────────────────────────────────────────────
# Arch package names. Split by what actually stops working without them, not
# by category — "optional" here means the shell starts and the rest still runs.
CORE_PKGS=(quickshell hyprland qt6-declarative qt6-5compat ttf-material-symbols-variable)
RECOMMENDED_PKGS=(libnotify wl-clipboard networkmanager pipewire pipewire-pulse
                  wireplumber brightnessctl grim slurp cliphist hyprpicker
                  polkit-gnome xdg-utils jq curl)
EXTRA_PKGS=(ffmpeg zenity udisks2 translate-shell timew solaar)
ROG_PKGS=(asusctl supergfxctl)

die()  { printf '\033[31merror\033[0m: %s\n' "$*" >&2; exit 1; }
info() { printf '\033[36m::\033[0m %s\n' "$*"; }
warn() { printf '\033[33mwarn\033[0m: %s\n' "$*" >&2; }
run()  { if [ "$DRY" = 1 ]; then printf '   would: %s\n' "$*"; else "$@"; fi; }

usage() {
    cat <<EOF
install.sh — install this quickshell configuration

  ./install.sh [options]

Options
  -n, --name NAME       Config name; run it with \`qs -c NAME\`.   (default: ii)
                        A name you do not already use means this install
                        cannot disturb an existing one.
  -d, --dest DIR        Install to an exact directory instead of
                        \$XDG_CONFIG_HOME/quickshell/NAME.
  -p, --profile P       What to pull in:
                          minimal      the shell only, no package installs
                          core         + what the shell needs to start
                          recommended  + clipboard, network, audio, screenshots
                          full         + media tools, translate, time tracking
                          rog          full + asusctl/supergfxctl (ASUS laptops)
                        (default: recommended)
      --polkit          Install the polkit rules for the net and ROG tools.
                        Needs root and grants the installing user passwordless
                        access to those specific actions. Off by default.
      --no-deps         Skip package installation entirely.
  -y, --yes             Do not ask before installing packages.
      --dry-run         Print every action, change nothing.
      --uninstall       Remove an install made by this script.
  -h, --help            This.

Examples
  ./install.sh --dry-run                 see exactly what would happen
  ./install.sh -n ii-test -p minimal     a throwaway copy beside your own
  ./install.sh -p rog --polkit           the lot, on an ASUS laptop
  ./install.sh -n ii-test --uninstall    remove that copy
EOF
}

while [ $# -gt 0 ]; do
    case "$1" in
        -n|--name)    NAME="${2:?--name needs a value}"; shift 2 ;;
        -d|--dest)    DEST="${2:?--dest needs a value}"; shift 2 ;;
        -p|--profile) PROFILE="${2:?--profile needs a value}"; shift 2 ;;
        --polkit)     DO_POLKIT=1; shift ;;
        --no-deps)    DO_DEPS=0; shift ;;
        -y|--yes)     ASSUME_YES=1; shift ;;
        --dry-run)    DRY=1; shift ;;
        --uninstall)  DO_UNINSTALL=1; shift ;;
        -h|--help)    usage; exit 0 ;;
        *)            die "unknown option: $1 (try --help)" ;;
    esac
done

case "$PROFILE" in
    minimal|core|recommended|full|rog) ;;
    *) die "unknown profile: $PROFILE (try --help)" ;;
esac

CONF_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
[ -n "$DEST" ] || DEST="$CONF_HOME/quickshell/$NAME"

# ── Uninstall ───────────────────────────────────────────────────────────────
if [ "$DO_UNINSTALL" = 1 ]; then
    [ -d "$DEST" ] || die "nothing installed at $DEST"
    # Only ever remove a directory this script created: the marker is written
    # at install time precisely so an --uninstall cannot delete a hand-made
    # config that happens to sit at the same path.
    [ -f "$DEST/.installed-by-quickshell-config" ] \
        || die "$DEST was not installed by this script; refusing to remove it"
    info "removing $DEST"
    run rm -rf "$DEST"
    # Systemd units are NOT touched. An earlier version disabled the units this
    # config ships with, which meant uninstalling a throwaway test copy stopped
    # the services belonging to the real install — services this script never
    # started. Uninstall removes what it created and nothing else.
    info "done. Packages, polkit rules and systemd units were left alone."
    info "If this was your only install, you may also want:"
    info "  systemctl --user disable --now noisewatch.service hdb630-guard.service"
    exit 0
fi

# ── Preflight ───────────────────────────────────────────────────────────────
info "source:  $SRC"
info "install: $DEST   (run it with: qs -c $NAME)"
info "profile: $PROFILE"
[ "$DRY" = 1 ] && warn "dry run — nothing will be changed"

[ -d "$SRC/ii" ] || die "$SRC does not look like this repo (no ii/ directory)"

if [ -e "$DEST" ] && [ ! -f "$DEST/.installed-by-quickshell-config" ]; then
    warn "$DEST already exists and was not created by this script."
    warn "It will be backed up, not overwritten."
fi

# ── Packages ────────────────────────────────────────────────────────────────
install_packages() {
    [ "$DO_DEPS" = 1 ] || { info "skipping packages (--no-deps)"; return; }
    [ "$PROFILE" = minimal ] && { info "profile 'minimal': no packages"; return; }

    local pkgs=("${CORE_PKGS[@]}")
    case "$PROFILE" in
        recommended) pkgs+=("${RECOMMENDED_PKGS[@]}") ;;
        full)        pkgs+=("${RECOMMENDED_PKGS[@]}" "${EXTRA_PKGS[@]}") ;;
        rog)         pkgs+=("${RECOMMENDED_PKGS[@]}" "${EXTRA_PKGS[@]}" "${ROG_PKGS[@]}") ;;
    esac

    # Only ask for what is actually absent, so re-running is quiet.
    local missing=()
    for p in "${pkgs[@]}"; do
        pacman -Qq "$p" >/dev/null 2>&1 || missing+=("$p")
    done
    if [ ${#missing[@]} -eq 0 ]; then info "all packages already present"; return; fi

    if ! command -v pacman >/dev/null 2>&1; then
        warn "not an Arch-based system; install these yourself:"
        printf '       %s\n' "${missing[*]}"
        return
    fi

    info "missing packages: ${missing[*]}"
    local helper=""
    for h in paru yay; do command -v "$h" >/dev/null 2>&1 && { helper="$h"; break; }; done
    if [ -z "$helper" ]; then
        warn "no AUR helper found; some of these (quickshell, asusctl) are not in the"
        warn "official repos. Installing what pacman can, and listing the rest."
    fi

    if [ "$ASSUME_YES" != 1 ] && [ "$DRY" != 1 ]; then
        read -rp "   install them now? [y/N] " a
        [[ "$a" =~ ^[Yy]$ ]] || { warn "skipping package install"; return; }
    fi
    if [ -n "$helper" ]; then
        run "$helper" -S --needed "${missing[@]}"
    else
        run sudo pacman -S --needed "${missing[@]}" || warn "some packages were not found in the repos"
    fi
}

# ── The config itself ───────────────────────────────────────────────────────
install_config() {
    if [ -e "$DEST" ]; then
        local backup="$DEST.backup-$(date +%Y%m%d-%H%M%S)"
        info "existing install moved to $backup"
        run mv "$DEST" "$backup"
    fi
    run mkdir -p "$(dirname "$DEST")"
    # The whole ii/ tree becomes the config root, so `qs -c NAME` finds
    # shell.qml at the top of it.
    run cp -r "$SRC/ii" "$DEST"
    run touch "$DEST/.installed-by-quickshell-config"
    info "installed"
}

# ── polkit ──────────────────────────────────────────────────────────────────
# Rendered from .in templates: polkit does not expand $HOME or know who is
# installing, so the paths and the username have to be written in.
install_polkit() {
    [ "$DO_POLKIT" = 1 ] || { info "skipping polkit rules (use --polkit)"; return; }
    local user; user="$(id -un)"
    local found=0
    while IFS= read -r tpl; do
        found=1
        local out; out="$(basename "${tpl%.in}")"
        local target
        case "$out" in
            *.rules)  target="/etc/polkit-1/rules.d/$out" ;;
            *.policy) target="/usr/share/polkit-1/actions/$out" ;;
            *)        continue ;;
        esac
        info "polkit: $out -> $target"
        if [ "$DRY" = 1 ]; then
            printf '   would: render %s with HOME=%s USER=%s\n' "$tpl" "$DEST" "$user"
        else
            sed -e "s|@HOME@|$DEST|g" -e "s|@USER@|$user|g" "$tpl" \
              | sudo tee "$target" >/dev/null
        fi
    done < <(find "$SRC/ii/scripts" -name '*.in' 2>/dev/null)
    [ "$found" = 1 ] || warn "no polkit templates found"
}

# ── What is still missing afterwards ────────────────────────────────────────
report_gaps() {
    local optional=(warp-cli nordvpn virt-viewer minimeters matugen)
    local gaps=()
    for b in "${optional[@]}"; do command -v "$b" >/dev/null 2>&1 || gaps+=("$b"); done
    if [ ${#gaps[@]} -gt 0 ]; then
        echo
        warn "not installed, and not installed by any profile: ${gaps[*]}"
        warn "The features that use them stay hidden; nothing else is affected."
    fi
}

install_packages
install_config
install_polkit
report_gaps

cat <<EOF

Done.

  Run it:        qs -c $NAME
  Keep it:       add \`exec-once = qs -c $NAME\` to your Hyprland config
  Remove it:     $SRC/install.sh -n $NAME --uninstall

EOF
