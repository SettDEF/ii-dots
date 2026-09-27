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
#   --disk /dev/nvme0n1   target (no prompt)
#   --user NAME           account to create
#   --host NAME           hostname
#   --fs ext4|btrfs       root filesystem (default ext4)
#   --profile P           passed to install.sh (default recommended)
#   --no-shell            base Arch only, skip this desktop
#   -y, --yes             do not stop for confirmation
#   --dry-run             print every action, change nothing

set -euo pipefail

REPO="${QS_REPO_URL:-https://github.com/SettDEF/ii-dots}"
BRANCH="${QS_BRANCH:-master}"
DISK=""; USERNAME=""; HOSTNAME_NEW="arch"; FS="ext4"; PROFILE="recommended"
DO_SHELL=1; ASSUME_YES=0; DRY=0
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
    local prompt="$1" a="" b=""
    while :; do
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
        --profile)   PROFILE="${2:?--profile needs a value}"; shift 2 ;;
        --repo)      REPO="${2:?--repo needs a value}"; shift 2 ;;
        --no-shell)  DO_SHELL=0; shift ;;
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

if [ -z "$DISK" ]; then
    echo; info "disks on this machine:"
    lsblk -dpno NAME,SIZE,MODEL | grep -vE "loop|/dev/sr" | sed 's/^/   /'
    echo
    DISK=$(ask "  Install to which disk" "")
fi
[ -b "$DISK" ] || [ "$DRY" = 1 ] || die "not a block device: $DISK"

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

if [ "$DRY" = 1 ]; then PASSWORD="(not asked in dry-run)"; else PASSWORD=$(ask_secret "  Password for $USERNAME and root"); fi

echo
c '1;31' "  This ERASES ${DISK} completely."
printf '   %-12s %s\n' "disk"    "$DISK" \
                       "user"    "$USERNAME" \
                       "host"    "$HOSTNAME_NEW" \
                       "fs"      "$FS" \
                       "tz"      "$TIMEZONE" \
                       "keymap"  "$KEYMAP" \
                       "desktop" "$( [ "$DO_SHELL" = 1 ] && echo "$REPO ($PROFILE)" || echo 'no' )"
echo
if [ "$ASSUME_YES" != 1 ] && [ "$DRY" != 1 ]; then
    # Typing the path back, not "y": a stray keystroke should not wipe a disk.
    confirm=$(ask "  Type the disk path to confirm" "")
    [ "$confirm" = "$DISK" ] || die "that did not match. Nothing was changed."
fi

# ── Partition, format, mount ───────────────────────────────────────────────

info "partitioning $DISK"
run sgdisk --zap-all "$DISK"
if [ "$UEFI" = 1 ]; then
    run sgdisk -n1:0:+1G  -t1:ef00 -c1:EFI  "$DISK"
    run sgdisk -n2:0:0    -t2:8304 -c2:root "$DISK"
else
    run sgdisk -n1:0:+1M  -t1:ef02 -c1:BIOS "$DISK"
    run sgdisk -n2:0:0    -t2:8304 -c2:root "$DISK"
fi
run partprobe "$DISK" || true
sleep 2

# nvme0n1 partitions are nvme0n1p1; sda partitions are sda1.
case "$DISK" in *[0-9]) P="${DISK}p" ;; *) P="$DISK" ;; esac
BOOTPART="${P}1"; ROOTPART="${P}2"

info "formatting"
[ "$UEFI" = 1 ] && run mkfs.fat -F32 "$BOOTPART"
if [ "$FS" = btrfs ]; then
    run mkfs.btrfs -f "$ROOTPART"
    run mount "$ROOTPART" /mnt
    for sub in @ @home @log @cache; do run btrfs subvolume create "/mnt/$sub"; done
    run umount /mnt
    OPTS="noatime,compress=zstd,space_cache=v2"
    run mount -o "$OPTS,subvol=@" "$ROOTPART" /mnt
    run mkdir -p /mnt/home /mnt/var/log /mnt/var/cache
    run mount -o "$OPTS,subvol=@home"  "$ROOTPART" /mnt/home
    run mount -o "$OPTS,subvol=@log"   "$ROOTPART" /mnt/var/log
    run mount -o "$OPTS,subvol=@cache" "$ROOTPART" /mnt/var/cache
else
    run mkfs.ext4 -F "$ROOTPART"
    run mount "$ROOTPART" /mnt
fi
if [ "$UEFI" = 1 ]; then run mkdir -p /mnt/boot; run mount "$BOOTPART" /mnt/boot; fi
ok "mounted"

# ── Base system ────────────────────────────────────────────────────────────

BASE=(base base-devel linux linux-firmware sudo networkmanager git nano
      pipewire pipewire-pulse wireplumber polkit)
[ "$FS" = btrfs ] && BASE+=(btrfs-progs)
[ "$UEFI" = 1 ] || BASE+=(grub)
# No swap partition: zram is faster, needs no sizing guess, and survives a
# resize of the root filesystem later.
BASE+=(zram-generator)

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
inchroot "printf '[zram0]\nzram-size = min(ram / 2, 8192)\n' > /etc/systemd/zram-generator.conf"

# Wheel gets sudo; the user goes in wheel. Both halves, or sudo does nothing.
inchroot "echo '%wheel ALL=(ALL:ALL) ALL' > /etc/sudoers.d/10-wheel && chmod 440 /etc/sudoers.d/10-wheel"
inchroot "useradd -m -G wheel -s /bin/bash '$USERNAME'"
if [ "$DRY" != 1 ]; then
    printf 'root:%s\n%s:%s\n' "$PASSWORD" "$USERNAME" "$PASSWORD" | arch-chroot /mnt chpasswd
fi
inchroot "systemctl enable NetworkManager"

info "bootloader"
if [ "$UEFI" = 1 ]; then
    inchroot "bootctl install"
    ROOTUUID=$([ "$DRY" = 1 ] && echo "UUID" || blkid -s UUID -o value "$ROOTPART")
    ROOTOPTS="root=UUID=$ROOTUUID rw"
    [ "$FS" = btrfs ] && ROOTOPTS="$ROOTOPTS rootflags=subvol=@"
    inchroot "printf 'default arch\ntimeout 3\neditor no\n' > /boot/loader/loader.conf"
    inchroot "printf 'title Arch Linux\nlinux /vmlinuz-linux\ninitrd /initramfs-linux.img\noptions %s\n' '$ROOTOPTS' > /boot/loader/entries/arch.conf"
else
    inchroot "grub-install --target=i386-pc '$DISK' && grub-mkconfig -o /boot/grub/grub.cfg"
fi
ok "system configured"

# ── The desktop ────────────────────────────────────────────────────────────

if [ "$DO_SHELL" = 1 ]; then
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
echo "   Log in as $USERNAME. The welcome screen opens on the first start."
