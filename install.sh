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
DO_LOWEND=0

# ── Dependencies, by profile ────────────────────────────────────────────────
# Arch package names. Split by what actually stops working without them, not
# by category — "optional" here means the shell starts and the rest still runs.
# Qt modules the QML actually imports. Missing one is not a degraded feature:
# quickshell fails to load the service that imports it, and because the
# services directory is auto-discovered, every other service then reports
# "unavailable" too. One absent module reads as the whole shell being broken.
CORE_PKGS=(quickshell hyprland
           qt6-declarative qt6-5compat qt6-imageformats
           qt6-multimedia qt6-positioning
           ttf-material-symbols-variable)
RECOMMENDED_PKGS=(libnotify wl-clipboard networkmanager pipewire pipewire-pulse
                  wireplumber brightnessctl grim slurp cliphist hyprpicker
                  polkit-gnome xdg-utils jq curl
                  matugen ddcutil
                  syntax-highlighting)      # code blocks in the AI chat
# kirigami only matters if you switch the panel family to "waffle"; it is not
# the default, and it pulls in KF6.
EXTRA_PKGS=(ffmpeg zenity udisks2 translate-shell timew solaar kirigami)
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
                          low-end      recommended tools, effects turned off
                        (default: recommended)
      --low-end         Tune the settings for a weak GPU or 4GB of RAM.
                        Combines with any profile. Merges into your existing
                        config.json; the old one is backed up first.
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
  ./install.sh -p low-end                a 2013 laptop with integrated graphics
EOF
}

while [ $# -gt 0 ]; do
    case "$1" in
        -n|--name)    NAME="${2:?--name needs a value}"; shift 2 ;;
        -d|--dest)    DEST="${2:?--dest needs a value}"; shift 2 ;;
        -p|--profile) PROFILE="${2:?--profile needs a value}"; shift 2 ;;
        --polkit)     DO_POLKIT=1; shift ;;
        --low-end)    DO_LOWEND=1; shift ;;
        --no-deps)    DO_DEPS=0; shift ;;
        -y|--yes)     ASSUME_YES=1; shift ;;
        --dry-run)    DRY=1; shift ;;
        --uninstall)  DO_UNINSTALL=1; shift ;;
        -h|--help)    usage; exit 0 ;;
        *)            die "unknown option: $1 (try --help)" ;;
    esac
done

case "$PROFILE" in
    # low-end installs the same tools as `recommended` — they are all small —
    # and additionally turns off the settings that cost a weak GPU or 4 GB of
    # RAM. See low_end_tuning() for what those are and why.
    low-end) DO_LOWEND=1; PROFILE="recommended" ;;
    minimal|core|recommended|full|rog) ;;
    *) die "unknown profile: $PROFILE (try --help)" ;;
esac

CONF_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
DATA_HOME="${XDG_DATA_HOME:-$HOME/.local/share}"
SOURCE_MARKER="$DATA_HOME/ii-dots/install-source"
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
[ "$DO_LOWEND" = 1 ] && info "tuning: low-end (effects off)"
[ "$DRY" = 1 ] && warn "dry run — nothing will be changed"

[ -d "$SRC/ii" ] || die "$SRC does not look like this repo (no ii/ directory)"

# A clone that already sits at $XDG_CONFIG_HOME/quickshell installs onto its own
# source: install_config would move $SRC/ii aside as the backup and then copy
# from the path it just emptied, destroying the checkout. Refuse, and say which
# way out to take.
case "$DEST/" in
    "$SRC"/*)
        die "install target $DEST is inside the source $SRC.
       This clone already lives where the config is installed, so there is
       nothing to install. Run it from here with: qs -c $(basename "$DEST")
       Or install a separate copy elsewhere:      ./install.sh -n ii-test"
        ;;
esac

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

    # Where this came from, so the shell can update itself later. The install is
    # a copy, not a checkout, so the git repo it was copied FROM is the only
    # thing that knows about upstream.
    if [ "$DRY" != 1 ]; then
        mkdir -p "$(dirname "$SOURCE_MARKER")"
        printf 'source=%s\nname=%s\ndest=%s\nprofile=%s\nlowend=%s\n' \
            "$SRC" "$NAME" "$DEST" "$PROFILE" "$DO_LOWEND" > "$SOURCE_MARKER"
    else
        printf '   would: record the install source in %s\n' "$SOURCE_MARKER"
    fi
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

# ── Low-end tuning ──────────────────────────────────────────────────────────
# Everything switched off here already had a switch; what was missing was a
# preset that knows which ones matter. The target is roughly a 2013 laptop —
# Haswell, Intel HD 4400, 4GB of DDR3, a 1366x768 panel — where the shell
# starts fine and then the effects make it unusable.
#
# Ordered by what actually costs the most there:
#
#   lock.blur            GaussianBlur radius 100 => samples 201, i.e. 201
#                        texture fetches per pixel over the whole screen. On
#                        HD 4400 at 1366x768 that is ~211M fetches a frame.
#                        This one alone is the difference between a lock screen
#                        and a slideshow.
#   background.effect    a full-screen fragment shader, redrawn every frame.
#   parallax             rescales the wallpaper on every workspace switch.
#   transparency         forces blended layers the compositor cannot skip.
#   extraBackgroundTint  another full-screen blend on top of that.
#   keepRightSidebarLoaded
#                        the shell's resident size is roughly one Mesa GL
#                        context per mapped surface, so a surface kept alive
#                        for latency costs real RAM on a 4GB machine.
#   showVisualizer       cava, plus a repainting spectrum, whenever audio plays.
#   fakeScreenRounding   a layer.enabled overlay per screen, every frame.
#   switchFlash          an animation on every workspace change.
#   resources            polling interval and history ring.
#
# The dock stays off: its window previews are ScreencopyView at a 35ms
# interval per window, which is the most expensive thing in the config and has
# no switch of its own short of the dock itself.
low_end_tuning() {
    [ "$DO_LOWEND" = 1 ] || return 0

    # Note this lives OUTSIDE the install dir, in the shared config the shell
    # reads at runtime — so it is not isolated by -n NAME. Say so plainly.
    local cfg_dir="${XDG_CONFIG_HOME:-$HOME/.config}/illogical-impulse"
    local cfg="$cfg_dir/config.json"

    local tuning
    tuning=$(cat <<'JSON'
{
  "appearance": {
    "extraBackgroundTint": false,
    "fakeScreenRounding": 0,
    "transparency": { "enable": false }
  },
  "background": {
    "effect": "",
    "parallax": { "enableWorkspace": false, "enableSidebar": false }
  },
  "bar": {
    "showVisualizer": false,
    "workspaces": { "switchFlash": false }
  },
  "dock": { "enable": false },
  "lock": { "blur": { "enable": false } },
  "overview": { "scale": 0.13 },
  "resources": { "updateInterval": 5000, "historyLength": 30 },
  "search": { "nonAppResultDelay": 120 },
  "sidebar": { "keepRightSidebarLoaded": false }
}
JSON
)

    info "low-end tuning -> $cfg"
    if [ "$DRY" = 1 ]; then
        printf '   would: merge into %s\n' "$cfg"
        printf '%s\n' "$tuning" | sed 's/^/          /'
        return 0
    fi

    mkdir -p "$cfg_dir"

    # No config yet: the keys left out fall back to the defaults in Config.qml,
    # so a partial file is a complete answer.
    if [ ! -f "$cfg" ]; then
        printf '%s\n' "$tuning" > "$cfg"
        info "wrote $cfg"
        return 0
    fi

    # One exists. Merge rather than replace, or this quietly eats every setting
    # the user has. Recursive merge, with the tuning winning each key it names.
    if command -v jq >/dev/null 2>&1; then
        local backup="$cfg.backup-$(date +%Y%m%d-%H%M%S)"
        cp -- "$cfg" "$backup"
        if printf '%s\n' "$tuning" | jq -s '.[0] * .[1]' "$cfg" - > "$cfg.tmp" 2>/dev/null; then
            mv -- "$cfg.tmp" "$cfg"
            info "merged; previous config saved as $(basename "$backup")"
        else
            rm -f "$cfg.tmp"
            warn "could not parse $cfg as JSON; left it alone"
            rm -f "$backup"
        fi
        return 0
    fi

    # No jq and a config already there: merging by hand in sh would be a good
    # way to corrupt it. Print the keys and let the user apply them.
    warn "jq is not installed and $cfg already exists, so it was NOT changed."
    warn "Apply these by hand, or in the settings panel:"
    printf '%s\n' "$tuning" | sed 's/^/       /' >&2
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
low_end_tuning
report_gaps

cat <<EOF

Done.

  Run it:        qs -c $NAME
  Keep it:       add \`exec-once = qs -c $NAME\` to your Hyprland config
  Remove it:     $SRC/install.sh -n $NAME --uninstall

EOF
