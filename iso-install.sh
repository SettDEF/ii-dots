#!/usr/bin/env bash
# iso-install.sh — from the Arch ISO to this desktop, in one run.
#
# bootstrap.sh starts where archinstall leaves off. This starts earlier: boot
# the Arch ISO, run this, answer four questions, and reboot into the finished
# thing.
#
#   curl -fsSL https://github.com/SettDEF/ii-dots/raw/master/iso-install.sh | bash
#
# Built on pacstrap/genfstab/arch-chroot rather than archinstall, because those
# interfaces have not changed in a decade and archinstall's config schema
# changes between releases.
#
# THIS ERASES A DISK. It names the disk and waits for you to type it back,
# unless you pass both --disk and --yes.
#
#   --disk /dev/nvme0n1   target (no prompt). ERASED.
#   --esp SIZE            EFI partition, default 1G
#   --swap SIZE           swap partition, e.g. 8G. Default: none, zram instead
#   --home SIZE           separate /home, e.g. 200G. Default: none, one root
#
# Or install into partitions that already exist, touching no partition table --
# this is the dual-boot path, and it leaves every other OS on the disk alone:
#
#   --root-part /dev/sda3 format and install here
#   --esp-part  /dev/sda1 reuse this ESP (NOT formatted; shared with Windows)
#   --home-part /dev/sda4 mount as /home (NOT formatted unless --format-home)
#   --user NAME           account to create
#   --host NAME           hostname
#   --fs ext4|btrfs       root filesystem (default ext4)
#   --desktop D           ii | hyprland | gnome | plasma | xfce | none
#   --profile P           passed to bootstrap.sh for the ii desktop
#   --no-shell            same as --desktop none
#   -y, --yes             do not stop for confirmation
#   --dry-run             print every action, change nothing

set -euo pipefail

REPO="${QS_REPO_URL:-https://github.com/SettDEF/ii-dots}"
BRANCH="${QS_BRANCH:-master}"
DISK=""; USERNAME=""; HOSTNAME_NEW="arch"; FS="ext4"; PROFILE="recommended"
ESP_SIZE="1G"; SWAP_SIZE=""; HOME_SIZE=""
ROOTPART=""; BOOTPART=""; HOMEPART=""; FORMAT_HOME=0
DESKTOP="ii"; ASSUME_YES=0; DRY=0
TIMEZONE=""; LOCALE="en_US.UTF-8"; KEYMAP=""

B=$'\033[1m'; DIM=$'\033[2m'; R=$'\033[0m'
CYN=$'\033[36m'; GRN=$'\033[32m'; YEL=$'\033[33m'; RED=$'\033[31m'

c()    { printf '\033[%sm%s\033[0m\n' "$1" "$2"; }

banner() {
    local text="Arch Linux — install" w=52 pad
    pad=$(( w - ${#text} - 3 ))
    printf '\n%s╭%s╮%s\n' "$CYN" "$(printf '─%.0s' $(seq 1 $w))" "$R"
    printf '%s│%s  %s%s%s%*s%s│%s\n' "$CYN" "$R" "$B" "$text" "$R" "$pad" "" "$CYN" "$R"
    printf '%s╰%s╯%s\n' "$CYN" "$(printf '─%.0s' $(seq 1 $w))" "$R"
}
die()  { c '31' "error: $*" >&2; exit 1; }
info() { c '36' ":: $*"; }
warn() { c '33' "warn: $*" >&2; }
ok()   { c '32' "ok: $*"; }
run()  { if [ "$DRY" = 1 ]; then printf '   would: %s\n' "$*"; else "$@"; fi; }
# Same, but the command is a shell string run inside the new system.
inchroot() { if [ "$DRY" = 1 ]; then printf '   would (chroot): %s\n' "$*"; else arch-chroot /mnt bash -c "$*"; fi; }

# A /dev/tty that exists but cannot be opened still passes -r, so open it.
have_tty() { { : >/dev/tty; } 2>/dev/null; }

# Prompts read the terminal, not stdin: curl | bash makes stdin the script.
ask() {
    local prompt="$1" default="${2:-}" reply=""
    [ "$ASSUME_YES" = 1 ] && { printf '%s\n' "$default"; return; }
    if have_tty; then
        printf '\033[36m?\033[0m %s%s: ' "$prompt" "${default:+ [$default]}" > /dev/tty
        read -r reply < /dev/tty || true
    fi
    printf '%s\n' "${reply:-$default}"
}
ask_secret() {
    local prompt="$1" a="" b="" tries=0
    # Never a flag: an argv is readable by every process on the machine.
    [ -n "${QS_PASSWORD:-}" ] && { printf '%s\n' "$QS_PASSWORD"; return; }
    have_tty || die "no terminal to ask for a password on.
       Pipe it in as QS_PASSWORD=... instead."
    while :; do
        tries=$((tries + 1))
        [ "$tries" -gt 5 ] && die "too many attempts."
        printf '\033[36m?\033[0m %s: ' "$prompt" > /dev/tty; read -rs a < /dev/tty; echo > /dev/tty
        printf '\033[36m?\033[0m %s (again): ' "$prompt" > /dev/tty; read -rs b < /dev/tty; echo > /dev/tty
        [ -n "$a" ] && [ "$a" = "$b" ] && { printf '%s\n' "$a"; return; }
        warn "empty or did not match; try again"
    done
}

while [ $# -gt 0 ]; do
    case "$1" in
        --disk)      DISK="${2:?--disk needs a value}"; shift 2 ;;
        --user)      USERNAME="${2:?--user needs a value}"; shift 2 ;;
        --host)      HOSTNAME_NEW="${2:?--host needs a value}"; shift 2 ;;
        --fs)        FS="${2:?--fs needs a value}"; shift 2 ;;
        --esp)       ESP_SIZE="${2:?--esp needs a value}"; shift 2 ;;
        --swap)      SWAP_SIZE="${2:?--swap needs a value}"; shift 2 ;;
        --home)      HOME_SIZE="${2:?--home needs a value}"; shift 2 ;;
        --root-part) ROOTPART="${2:?--root-part needs a value}"; shift 2 ;;
        --esp-part)  BOOTPART="${2:?--esp-part needs a value}"; shift 2 ;;
        --home-part) HOMEPART="${2:?--home-part needs a value}"; shift 2 ;;
        --format-home) FORMAT_HOME=1; shift ;;
        --profile)   PROFILE="${2:?--profile needs a value}"; shift 2 ;;
        --repo)      REPO="${2:?--repo needs a value}"; shift 2 ;;
        --desktop)   DESKTOP="${2:?--desktop needs a value}"; shift 2 ;;
        --no-shell)  DESKTOP="none"; shift ;;
        -y|--yes)    ASSUME_YES=1; shift ;;
        --dry-run)   DRY=1; shift ;;
        -h|--help)   sed -n '2,26p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *)           die "unknown option: $1 (try --help)" ;;
    esac
done

# ── Submenus ───────────────────────────────────────────────────────────────
# Every setting whose answers can be enumerated gets a numbered list rather
# than a blank prompt: a free-text field asks you to already know the answer.

# choose <title> <current> <value> <description> [<value> <description>]...
# Enter keeps the current value; a number picks; typing a value also works, so
# anything not listed is still reachable.
choose() {
    local title="$1" current="$2"; shift 2
    have_tty || { printf '%s' "$current"; return; }
    local -a vals=() descs=()
    while [ $# -gt 0 ]; do vals+=("$1"); descs+=("${2:-}"); shift 2; done

    printf '\n  %s%s%s\n\n' "$B" "$title" "$R" > /dev/tty
    local i mark
    for i in "${!vals[@]}"; do
        mark=' '; [ "${vals[$i]}" = "$current" ] && mark='*'
        printf '   %s%s %-2s %-16s %s%s%s\n' \
            "$( [ "$mark" = '*' ] && printf '%s' "$GRN" )" "$mark" "$((i+1))" \
            "${vals[$i]}" "$DIM" "${descs[$i]}" "$R" > /dev/tty
    done
    echo > /dev/tty
    local answer; answer=$(ask "  Number, value, or Enter to keep ${current:-none}" "")
    [ -n "$answer" ] || { printf '%s' "$current"; return; }
    case "$answer" in
        ''|*[!0-9]*) printf '%s' "$answer" ;;                 # typed a value
        *) if [ "$answer" -ge 1 ] && [ "$answer" -le "${#vals[@]}" ]; then
               printf '%s' "${vals[$((answer-1))]}"
           else printf '%s' "$current"; fi ;;
    esac
}

# choose_long <title> <current> <command producing one value per line>
# For lists in the hundreds. Filter first, then pick from what matched.
choose_long() {
    local title="$1" current="$2" lister="$3"
    have_tty || { printf '%s' "$current"; return; }
    local filter matches answer
    while true; do
        printf '\n  %s%s%s   %scurrently %s%s\n' "$B" "$title" "$R" "$DIM" "${current:-none}" "$R" > /dev/tty
        filter=$(ask "  Type part of it to search, or Enter to keep" "")
        [ -n "$filter" ] || { printf '%s' "$current"; return; }
        mapfile -t matches < <(eval "$lister" 2>/dev/null | grep -i -- "$filter" | head -30)
        if [ "${#matches[@]}" -eq 0 ]; then warn "nothing matched '$filter'"; continue; fi
        if [ "${#matches[@]}" -eq 1 ]; then printf '%s' "${matches[0]}"; return; fi
        echo > /dev/tty
        local i; for i in "${!matches[@]}"; do printf '   %-3s %s\n' "$((i+1))" "${matches[$i]}" > /dev/tty; done
        echo > /dev/tty
        answer=$(ask "  Number, or Enter to search again" "")
        [ -n "$answer" ] || continue
        case "$answer" in
            ''|*[!0-9]*) ;;
            *) if [ "$answer" -ge 1 ] && [ "$answer" -le "${#matches[@]}" ]; then
                   printf '%s' "${matches[$((answer-1))]}"; return; fi ;;
        esac
    done
}

# Size prompts share a shape: a few sensible presets, or type your own.
choose_size() {
    local title="$1" current="$2"; shift 2
    choose "$title" "$current" "$@"
}

# ── Guards ─────────────────────────────────────────────────────────────────

# --dry-run changes nothing, so it is inspectable from anywhere.
[ "$(id -u)" -eq 0 ] || [ "$DRY" = 1 ] || die "run this as root. On the Arch ISO you already are."
[ -d /run/archiso ] || [ "$DRY" = 1 ] || die "this is not the Arch ISO.
       Installing from a running system would erase the disk under you.
       On an installed system you want bootstrap.sh instead."
if [ "$DRY" != 1 ]; then
    for t in pacstrap genfstab arch-chroot sgdisk; do
        command -v "$t" >/dev/null 2>&1 || die "$t is missing (pacman -S arch-install-scripts gptfdisk)"
    done
    ping -c1 -W3 archlinux.org >/dev/null 2>&1 || die "no network. Use iwctl for wifi, then run this again."
fi
[ "$FS" = ext4 ] || [ "$FS" = btrfs ] || die "unknown filesystem: $FS"

UEFI=0; [ -d /sys/firmware/efi/efivars ] && UEFI=1
ok "$( [ "$UEFI" = 1 ] && echo 'UEFI' || echo 'BIOS' ) boot, network up"

# ── What to install onto, and as whom ──────────────────────────────────────

USE_EXISTING=0
[ -n "$ROOTPART" ] && USE_EXISTING=1
PASSWORD=""

pick_disk() {
    local -a args=() line name size type fstype label
    while read -r name size type fstype label; do
        case "$type" in
            disk) args+=("$name" "$size  whole disk — ERASED") ;;
            part) args+=("$name" "$size  ${fstype:-unformatted} ${label:+· $label}  — keeps the table") ;;
        esac
    done < <(lsblk -pnro NAME,SIZE,TYPE,FSTYPE,LABEL 2>/dev/null | grep -vE "loop|/dev/sr|zram")

    [ "${#args[@]}" -gt 0 ] || { warn "no disks found"; return; }
    local answer
    answer=$(choose "Install where" "${ROOTPART:-$DISK}" "${args[@]}")
    [ -n "$answer" ] || return

    # A partition means an install into what is already there; a disk means the
    # table gets rewritten.
    if [ "$(lsblk -dno TYPE "$answer" 2>/dev/null)" = part ]; then
        ROOTPART="$answer"; USE_EXISTING=1; DISK=""
        if [ "$UEFI" = 1 ]; then
            local -a esps=()
            while read -r name size fstype; do
                esps+=("$name" "$size  $fstype")
            done < <(lsblk -pnro NAME,SIZE,FSTYPE 2>/dev/null | awk '$3=="vfat"')
            [ "${#esps[@]}" -gt 0 ] \
                && BOOTPART=$(choose "Which EFI partition (kept, never formatted)" "$BOOTPART" "${esps[@]}") \
                || BOOTPART=$(ask "  EFI partition" "$BOOTPART")
        fi
    else
        DISK="$answer"; USE_EXISTING=0; ROOTPART=""
    fi
}

pick_desktop() {
    DESKTOP=$(choose "Desktop" "$DESKTOP" \
        ii       "Hyprland + this quickshell desktop" \
        hyprland "Hyprland on its own, nothing else" \
        gnome    "GNOME, with gdm" \
        plasma   "KDE Plasma, with sddm" \
        xfce     "Xfce, with lightdm" \
        none     "base system, no desktop")
}

# Everything on one screen with its current value, the way archinstall does it:
# a linear run of prompts cannot be corrected without starting again.
menu() {
    local choice
    while true; do
        banner
        printf '\n   %-3s %-14s %s%s%s\n' \
          "d" "Target"     "$GRN" "$( [ "$USE_EXISTING" = 1 ] && echo "$ROOTPART (keep table)" || echo "${DISK:-not set}" )" "$R"
        printf '   %-3s %-14s %s%s%s\n' \
          "D" "Desktop"    "$DIM" "$DESKTOP$( [ "$DESKTOP" = ii ] && echo " ($PROFILE)" )" "$R" \
          "f" "Filesystem" "$DIM" "$FS" "$R" \
          "e" "EFI size"   "$DIM" "$( [ "$USE_EXISTING" = 1 ] && echo "${BOOTPART:-none} (kept)" || echo "$ESP_SIZE" )" "$R" \
          "s" "Swap"       "$DIM" "${SWAP_SIZE:-zram, half of RAM}" "$R" \
          "H" "Home"       "$DIM" "${HOMEPART:-${HOME_SIZE:-inside root}}" "$R" \
          "u" "User"       "$DIM" "${USERNAME:-not set}" "$R" \
          "n" "Hostname"   "$DIM" "$HOSTNAME_NEW" "$R" \
          "t" "Time zone"  "$DIM" "$TIMEZONE" "$R" \
          "k" "Keymap"     "$DIM" "$KEYMAP" "$R" \
          "p" "Password"   "$DIM" "$( [ -n "$PASSWORD" ] && echo set || echo 'not set' )" "$R"
        printf '\n'
        printf '   %-3s %s\n' \
          "i" "Install" \
          "r" "Dry run — print the plan, change nothing" \
          "q" "Quit"
        echo
        # No terminal and no --yes: show the plan once, then go.
        have_tty || { warn "no terminal for the menu; taking these settings"; return; }
        choice=$(ask "  Choice" "")
        case "$choice" in
            d) pick_disk ;;
            D) pick_desktop
               [ "$DESKTOP" = ii ] && PROFILE=$(choose "Profile" "$PROFILE" \
                    recommended "the shell and the tools most panels need" \
                    minimal     "the shell only, no packages" \
                    full        "everything, media and translation included" \
                    low-end     "recommended, effects off — for old hardware" \
                    rog         "full, plus asusctl and supergfxctl")
               ;;
            f) FS=$(choose "Root filesystem" "$FS" \
                    ext4  "plain and predictable" \
                    btrfs "subvolumes and zstd compression, snapshot-ready")
               ;;
            e) ESP_SIZE=$(choose_size "EFI partition size" "$ESP_SIZE" \
                    512M "enough for one kernel" \
                    1G   "room for a few kernels — the default" \
                    2G   "plenty, if you keep several")
               ;;
            s) SWAP_SIZE=$(choose_size "Swap" "$SWAP_SIZE" \
                    ""    "zram, half of RAM — no partition, no sizing" \
                    4G    "a small partition" \
                    8G    "a partition" \
                    16G   "enough to hibernate with 16G of RAM")
               ;;
            H) HOME_SIZE=$(choose_size "Separate /home" "$HOME_SIZE" \
                    ""     "none — /home lives inside root" \
                    100G   "a partition of its own" \
                    200G   "a partition of its own" \
                    500G   "a partition of its own")
               ;;
            u) USERNAME=$(ask "  Username" "$USERNAME") ;;
            n) HOSTNAME_NEW=$(ask "  Hostname" "$HOSTNAME_NEW") ;;
            t) TIMEZONE=$(choose_long "Time zone" "$TIMEZONE" \
                    "find /usr/share/zoneinfo -mindepth 2 -maxdepth 2 -type f -printf '%P\\n' | sort") ;;
            k) KEYMAP=$(choose_long "Console keymap" "$KEYMAP" \
                    "localectl list-keymaps") ;;
            p) PASSWORD=$(ask_secret "  Password for $USERNAME and root") ;;
            r) DRY=1; return ;;
            i|"") return ;;
            q) warn "nothing done"; exit 0 ;;
            *) warn "no such choice: $choice" ;;
        esac
    done
}

# Defaults the menu opens with, so nothing shows as unset that need not be.
[ -n "$TIMEZONE" ] || TIMEZONE=$( [ "$DRY" = 1 ] && echo UTC \
    || curl -fsS --max-time 4 https://ipapi.co/timezone 2>/dev/null || echo UTC )
[ -n "$KEYMAP" ]   || KEYMAP=$(localectl status 2>/dev/null | sed -n 's/.*VC Keymap: *//p' | head -1)
[ -n "$KEYMAP" ]   || KEYMAP=us

if [ "$ASSUME_YES" != 1 ]; then
    menu
else
    [ -n "$DISK" ] || [ -n "$ROOTPART" ] || die "--yes needs --disk or --root-part."
    [ -n "$USERNAME" ] || die "--yes needs --user."
fi

case "$DESKTOP" in
    ii|hyprland|gnome|plasma|xfce|none) ;;
    *) die "unknown desktop: $DESKTOP (ii, hyprland, gnome, plasma, xfce, none)" ;;
esac
[ "$FS" = ext4 ] || [ "$FS" = btrfs ] || die "unknown filesystem: $FS"
[ -n "$USERNAME" ] || die "no username set."

if [ "$USE_EXISTING" = 1 ]; then
    [ -b "$ROOTPART" ] || [ "$DRY" = 1 ] || die "not a block device: $ROOTPART"
    [ "$UEFI" = 0 ] || [ -n "$BOOTPART" ] || die "a UEFI install into an existing partition needs an EFI partition too."
else
    [ -n "$DISK" ] || die "no disk chosen."
    [ -b "$DISK" ] || [ "$DRY" = 1 ] || die "not a block device: $DISK"
fi

if [ "$DRY" = 1 ]; then
    PASSWORD="(not asked in dry-run)"
elif [ -z "$PASSWORD" ]; then
    PASSWORD=$(ask_secret "  Password for $USERNAME and root")
fi

echo
if [ "$USE_EXISTING" = 1 ]; then
    c '1;33' "  This formats ${ROOTPART}. The partition table is not touched."
else
    c '1;31' "  This ERASES ${DISK} completely."
fi
printf '   %-12s %s\n' "target"  "$( [ "$USE_EXISTING" = 1 ] && echo "$ROOTPART (existing)" || echo "$DISK (whole disk)" )" \
                       "esp"     "$( [ "$USE_EXISTING" = 1 ] && echo "${BOOTPART:-none} (kept)" || echo "$ESP_SIZE" )" \
                       "swap"    "$( [ -n "$SWAP_SIZE" ] && echo "$SWAP_SIZE" || echo 'zram' )" \
                       "home"    "$( [ -n "$HOMEPART" ] && echo "$HOMEPART" || { [ -n "$HOME_SIZE" ] && echo "$HOME_SIZE" || echo 'in root'; } )" \
                       "user"    "$USERNAME" \
                       "host"    "$HOSTNAME_NEW" \
                       "fs"      "$FS" \
                       "tz"      "$TIMEZONE" \
                       "keymap"  "$KEYMAP" \
                       "desktop" "$( [ "$DESKTOP" = ii ] && echo "ii ($PROFILE)" || echo "$DESKTOP" )"
echo
if [ "$ASSUME_YES" != 1 ] && [ "$DRY" != 1 ]; then
    # Typing the path back, not "y": a stray keystroke should not wipe a disk.
    want=$( [ "$USE_EXISTING" = 1 ] && echo "$ROOTPART" || echo "$DISK" )
    confirm=$(ask "  Type the path to confirm" "")
    [ "$confirm" = "$want" ] || die "that did not match. Nothing was changed."
fi

# ── Partition, format, mount ───────────────────────────────────────────────

if [ "$USE_EXISTING" = 1 ]; then
    info "using partitions that already exist; the partition table is untouched"
else
    info "partitioning $DISK"
    run sgdisk --zap-all "$DISK"

    # Built in order, so the numbers follow whatever was asked for.
    n=1
    if [ "$UEFI" = 1 ]; then
        run sgdisk "-n${n}:0:+${ESP_SIZE}" "-t${n}:ef00" "-c${n}:EFI" "$DISK"; ESP_N=$n; n=$((n+1))
    else
        run sgdisk "-n${n}:0:+1M" "-t${n}:ef02" "-c${n}:BIOS" "$DISK"; ESP_N=$n; n=$((n+1))
    fi
    if [ -n "$SWAP_SIZE" ]; then
        run sgdisk "-n${n}:0:+${SWAP_SIZE}" "-t${n}:8200" "-c${n}:swap" "$DISK"; SWAP_N=$n; n=$((n+1))
    fi
    # Root takes the rest, unless /home is carved out after it.
    if [ -n "$HOME_SIZE" ]; then
        run sgdisk "-n${n}:0:-${HOME_SIZE}" "-t${n}:8304" "-c${n}:root" "$DISK"; ROOT_N=$n; n=$((n+1))
        run sgdisk "-n${n}:0:0" "-t${n}:8302" "-c${n}:home" "$DISK"; HOME_N=$n
    else
        run sgdisk "-n${n}:0:0" "-t${n}:8304" "-c${n}:root" "$DISK"; ROOT_N=$n
    fi
    run partprobe "$DISK" || true
    sleep 2

    # nvme0n1 partitions are nvme0n1p1; sda partitions are sda1.
    case "$DISK" in *[0-9]) P="${DISK}p" ;; *) P="$DISK" ;; esac
    BOOTPART="${P}${ESP_N}"
    ROOTPART="${P}${ROOT_N}"
    [ -n "${SWAP_N:-}" ] && SWAPPART="${P}${SWAP_N}"
    [ -n "${HOME_N:-}" ] && HOMEPART="${P}${HOME_N}"
fi

info "formatting"
# An existing ESP is never formatted: it is probably shared with another OS,
# and reformatting it is how a dual boot loses its other bootloader.
if [ "$UEFI" = 1 ] && [ "$USE_EXISTING" != 1 ]; then run mkfs.fat -F32 "$BOOTPART"; fi
if [ -n "${SWAPPART:-}" ]; then run mkswap "$SWAPPART"; run swapon "$SWAPPART"; fi

if [ "$FS" = btrfs ]; then
    run mkfs.btrfs -f "$ROOTPART"
    run mount "$ROOTPART" /mnt
    SUBVOLS="@ @log @cache"
    [ -n "$HOMEPART" ] || SUBVOLS="$SUBVOLS @home"
    for sub in $SUBVOLS; do run btrfs subvolume create "/mnt/$sub"; done
    run umount /mnt
    OPTS="noatime,compress=zstd,space_cache=v2"
    run mount -o "$OPTS,subvol=@" "$ROOTPART" /mnt
    run mkdir -p /mnt/home /mnt/var/log /mnt/var/cache
    [ -n "$HOMEPART" ] || run mount -o "$OPTS,subvol=@home" "$ROOTPART" /mnt/home
    run mount -o "$OPTS,subvol=@log"   "$ROOTPART" /mnt/var/log
    run mount -o "$OPTS,subvol=@cache" "$ROOTPART" /mnt/var/cache
else
    run mkfs.ext4 -F "$ROOTPART"
    run mount "$ROOTPART" /mnt
    run mkdir -p /mnt/home
fi

if [ -n "$HOMEPART" ]; then
    # A home partition passed in by hand keeps its data unless asked otherwise.
    if [ "$USE_EXISTING" != 1 ] || [ "$FORMAT_HOME" = 1 ]; then run mkfs.ext4 -F "$HOMEPART"; fi
    run mount "$HOMEPART" /mnt/home
fi

if [ "$UEFI" = 1 ]; then run mkdir -p /mnt/boot; run mount "$BOOTPART" /mnt/boot; fi
ok "mounted"

# ── Base system ────────────────────────────────────────────────────────────

BASE=(base base-devel linux linux-firmware sudo networkmanager git nano
      pipewire pipewire-pulse wireplumber polkit)
[ "$FS" = btrfs ] && BASE+=(btrfs-progs)
BASE+=(grub os-prober)
[ "$UEFI" = 1 ] && BASE+=(efibootmgr)
# No swap partition: zram is faster, needs no sizing guess, and survives a
# resize of the root filesystem later.
[ -n "${SWAPPART:-}" ] || BASE+=(zram-generator)

# Everything but `none` gets a greeter: a machine that boots to a bare tty
# after a graphical install reads as a failed one.
case "$DESKTOP" in
    gnome)    BASE+=(gnome gnome-tweaks gdm);            GREETER=gdm ;;
    plasma)   BASE+=(plasma kde-applications sddm);      GREETER=sddm ;;
    xfce)     BASE+=(xfce4 xfce4-goodies lightdm lightdm-gtk-greeter); GREETER=lightdm ;;
    hyprland) BASE+=(hyprland foot sddm);                GREETER=sddm ;;
    # ii installs its own packages through bootstrap.sh; it only needs the
    # greeter up front.
    ii)       BASE+=(sddm);                              GREETER=sddm ;;
    none)     GREETER="" ;;
esac

info "installing the base system (this is the slow part)"
run pacstrap -K /mnt "${BASE[@]}"
run bash -c "genfstab -U /mnt >> /mnt/etc/fstab"
ok "base installed"

# ── Configure it ───────────────────────────────────────────────────────────

info "configuring"
inchroot "ln -sf /usr/share/zoneinfo/$TIMEZONE /etc/localtime && hwclock --systohc"
inchroot "sed -i 's/^#\\($(echo "$LOCALE" | sed 's/\./\\./') \\)/\\1/' /etc/locale.gen && locale-gen"
inchroot "echo 'LANG=$LOCALE' > /etc/locale.conf"
inchroot "echo 'KEYMAP=$KEYMAP' > /etc/vconsole.conf"
inchroot "echo '$HOSTNAME_NEW' > /etc/hostname"
inchroot "printf '127.0.0.1 localhost\n::1 localhost\n127.0.1.1 %s\n' '$HOSTNAME_NEW' > /etc/hosts"
[ -n "${SWAPPART:-}" ] || inchroot "printf '[zram0]\nzram-size = min(ram / 2, 8192)\n' > /etc/systemd/zram-generator.conf"

# Wheel gets sudo; the user goes in wheel. Both halves, or sudo does nothing.
inchroot "echo '%wheel ALL=(ALL:ALL) ALL' > /etc/sudoers.d/10-wheel && chmod 440 /etc/sudoers.d/10-wheel"
inchroot "useradd -m -G wheel -s /bin/bash '$USERNAME'"
if [ "$DRY" != 1 ]; then
    printf 'root:%s\n%s:%s\n' "$PASSWORD" "$USERNAME" "$PASSWORD" | arch-chroot /mnt chpasswd
fi
inchroot "systemctl enable NetworkManager"
[ -n "${GREETER:-}" ] && inchroot "systemctl enable $GREETER"

info "bootloader"
if [ "$UEFI" = 1 ]; then
    inchroot "grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id=GRUB"
else
    inchroot "grub-install --target=i386-pc '$DISK'"
fi
# os-prober is off by default and silently finds nothing until it is on, which
# is why a dual boot so often ends up with no menu entry for the other system.
inchroot "grep -q GRUB_DISABLE_OS_PROBER /etc/default/grub \
    && sed -i 's/^#\?GRUB_DISABLE_OS_PROBER=.*/GRUB_DISABLE_OS_PROBER=false/' /etc/default/grub \
    || echo 'GRUB_DISABLE_OS_PROBER=false' >> /etc/default/grub"
inchroot "grub-mkconfig -o /boot/grub/grub.cfg"
ok "system configured"

# ── The desktop ────────────────────────────────────────────────────────────

if [ "$DESKTOP" = "ii" ]; then
    info "installing the desktop"

    # bootstrap.sh, not install.sh: quickshell is in the AUR and a fresh chroot
    # has no helper to build it with. bootstrap sets paru up first.
    #
    # It runs as the user and calls sudo, which cannot prompt in here. So sudo
    # goes passwordless for the length of this step only, and the trap takes it
    # away again even if the step dies.
    NOPASSWD=/mnt/etc/sudoers.d/00-installer
    cleanup_nopasswd() {
        [ "$DRY" = 1 ] && { printf '   would: rm -f %s\n' "$NOPASSWD"; return; }
        rm -f "$NOPASSWD"
        arch-chroot /mnt visudo -c >/dev/null 2>&1 \
            || warn "sudoers did not validate; check /etc/sudoers.d in the new system."
    }
    trap cleanup_nopasswd EXIT

    if [ "$DRY" = 1 ]; then
        printf '   would: write %%wheel NOPASSWD to %s (removed after)\n' "$NOPASSWD"
    else
        printf '%%wheel ALL=(ALL:ALL) NOPASSWD: ALL\n' > "$NOPASSWD"
        chmod 440 "$NOPASSWD"
    fi

    inchroot "su - '$USERNAME' -c 'git clone --depth 1 -b $BRANCH $REPO ~/.local/share/ii-dots-src'" \
        || warn "clone failed; skipping the desktop."
    inchroot "su - '$USERNAME' -c 'cd ~/.local/share/ii-dots-src && ./bootstrap.sh --yes --profile $PROFILE'" \
        || warn "the desktop install did not finish. Log in and run bootstrap.sh by hand."

    cleanup_nopasswd
    trap - EXIT
fi

echo
ok "done"
echo "   umount -R /mnt && reboot"
case "$DESKTOP" in
    ii)   echo "   Log in as $USERNAME. The welcome screen opens on the first start." ;;
    none) echo "   Log in as $USERNAME at the console." ;;
    *)    echo "   Log in as $USERNAME at the $GREETER greeter." ;;
esac
