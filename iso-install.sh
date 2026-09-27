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

c()    { printf '\033[%sm%s\033[0m\n' "$1" "$2"; }
die()  { c '31' "error: $*" >&2; exit 1; }
info() { c '36' ":: $*"; }
warn() { c '33' "warn: $*" >&2; }
ok()   { c '32' "ok: $*"; }
run()  { if [ "$DRY" = 1 ]; then printf '   would: %s\n' "$*"; else "$@"; fi; }
# Same, but the command is a shell string run inside the new system.
inchroot() { if [ "$DRY" = 1 ]; then printf '   would (chroot): %s\n' "$*"; else arch-chroot /mnt bash -c "$*"; fi; }

# Prompts read the terminal, not stdin: curl | bash makes stdin the script.
ask() {
    local prompt="$1" default="${2:-}" reply=""
    [ "$ASSUME_YES" = 1 ] && { printf '%s\n' "$default"; return; }
    if [ -r /dev/tty ]; then
        printf '\033[36m?\033[0m %s%s: ' "$prompt" "${default:+ [$default]}" > /dev/tty
        read -r reply < /dev/tty || true
    fi
    printf '%s\n' "${reply:-$default}"
}
ask_secret() {
    local prompt="$1" a="" b="" tries=0
    # Never a flag: an argv is readable by every process on the machine.
    [ -n "${QS_PASSWORD:-}" ] && { printf '%s\n' "$QS_PASSWORD"; return; }
    [ -r /dev/tty ] || die "no terminal to ask for a password on.
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

if [ "$USE_EXISTING" = 1 ]; then
    [ -b "$ROOTPART" ] || [ "$DRY" = 1 ] || die "not a block device: $ROOTPART"
    [ "$UEFI" = 0 ] || [ -n "$BOOTPART" ] || die "--root-part on a UEFI machine needs --esp-part too."
elif [ -z "$DISK" ]; then
    echo; info "disks on this machine:"
    lsblk -po NAME,SIZE,FSTYPE,MOUNTPOINTS,LABEL | grep -vE "loop|/dev/sr" | sed 's/^/   /'
    echo; info "to keep another OS on the disk, quit and pass --root-part instead"
    echo
    DISK=$(ask "  Install to which disk" "")
fi
[ "$USE_EXISTING" = 1 ] || [ -b "$DISK" ] || [ "$DRY" = 1 ] || die "not a block device: $DISK"

[ -n "$USERNAME" ] || USERNAME=$(ask "  Username" "$(whoami 2>/dev/null || echo user)")
[ "$HOSTNAME_NEW" = arch ] && HOSTNAME_NEW=$(ask "  Hostname" "arch")
# Geolocated default, and never in dry-run: no reason to call out just to
# print a plan.
if [ -z "$TIMEZONE" ]; then
    guess=UTC
    [ "$DRY" = 1 ] || guess=$(curl -fsS --max-time 4 https://ipapi.co/timezone 2>/dev/null || echo UTC)
    TIMEZONE=$(ask "  Time zone" "$guess")
fi
[ -n "$KEYMAP" ]   || KEYMAP=$(ask "  Console keymap" "us")

if [ "$ASSUME_YES" != 1 ]; then
    echo; info "desktops:"
    printf '   %-10s %s\n' \
        "ii"       "Hyprland + this quickshell desktop" \
        "hyprland" "Hyprland on its own, nothing else" \
        "gnome"    "GNOME" \
        "plasma"   "KDE Plasma" \
        "xfce"     "Xfce" \
        "none"     "no desktop, base system only"
    echo
    DESKTOP=$(ask "  Desktop" "$DESKTOP")
fi

case "$DESKTOP" in
    ii|hyprland|gnome|plasma|xfce|none) ;;
    *) die "unknown desktop: $DESKTOP (ii, hyprland, gnome, plasma, xfce, none)" ;;
esac

if [ "$DRY" = 1 ]; then PASSWORD="(not asked in dry-run)"; else PASSWORD=$(ask_secret "  Password for $USERNAME and root"); fi

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
