#!/usr/bin/env bash
# Print the basenames of symlinks in DIR whose targets are directories.
#
# WHY THIS EXISTS
# The obvious one-liner is
#     find DIR -maxdepth 1 -type l -xtype d -printf '%f\n'
# but -xtype dereferences, and dereferencing a link into an autofs mount whose
# backing device is gone parks the process in uninterruptible D state
# (wchan: autofs_wait) until the mount's own timeout — 600s on /mnt/nuke9100.
#
# `timeout 2` does NOT save you: SIGTERM is not delivered to a task in D state,
# so the finds accumulate and every one fires another failing automount
# request. Measured 764 of them in 30 minutes from a 4s refresh timer, which
# was enough autofs churn to make Dolphin crawl.
#
# So: never dereference blindly. Read the targets WITHOUT following them
# (-type l alone does not stat the target), drop anything under an autofs
# mount that has no real filesystem on it right now, and stat only the rest.
# A link into a healthy automount still resolves and still triggers the mount,
# which is what you want; only the dead ones are skipped.
#
# WHY THE ANSWER IS REMEMBERED
# A target that is merely UNPLUGGED is not a target that stopped being a folder.
# ~/Desktop links into /mnt/nuke9100, whose fstab entry is currently disabled
# (the drive's PCIe link faults), so every one of those links fails `test -d`
# and silently demotes to a plain-link icon. Cache each verdict while the device
# is present and reuse it while it is away, so the desktop keeps looking like
# itself across an unplug.
set -uo pipefail
dir=${1:?usage: dir-symlinks.sh DIR}

cache_dir=${XDG_CACHE_HOME:-$HOME/.cache}/quickshell
cache=$cache_dir/dir-symlinks.cache
mkdir -p "$cache_dir" 2>/dev/null

# Previously observed verdict for a target path, or empty if never seen live.
cached_verdict() {
    [ -r "$cache" ] || return 0
    awk -F'\t' -v k="$1" '$1 == k { print $2; exit }' "$cache" 2>/dev/null
}

# Last resort for a target we have never seen resolve: directories essentially
# never carry a file extension. Stated as a guess because it is one -- it only
# ever applies to a link whose destination this machine has not had mounted.
guess_from_name() {
    case "${1##*/}" in *.*) echo 0 ;; *) echo 1 ;; esac
}

# autofs mountpoints with nothing really mounted on them. An active automount
# shows a second, non-autofs entry at the same mountpoint; a dormant or broken
# one shows only the autofs entry.
mapfile -t dead < <(awk '
    {
        mp = $5; fstype = ""
        for (i = 6; i <= NF; i++) if ($i == "-") { fstype = $(i + 1); break }
        if (fstype == "autofs") auto[mp] = 1; else real[mp] = 1
    }
    END { for (m in auto) if (!(m in real)) print m }
' /proc/self/mountinfo)

declare -a learned=()
while IFS=$'\t' read -r name target; do
    [ -n "$name" ] || continue
    case "$target" in
        /*) abs="$target" ;;
        *)  abs="$dir/$target" ;;
    esac
    skip=
    for d in "${dead[@]}"; do
        [ -n "$d" ] || continue
        case "$abs" in "$d"/*|"$d") skip=1; break ;; esac
    done
    if [ -n "$skip" ]; then
        # Under a dead automount: must not stat it. Answer from memory.
        verdict=$(cached_verdict "$abs")
        [ -n "$verdict" ] || verdict=$(guess_from_name "$abs")
    elif [ -d "$abs" ]; then
        verdict=1
        learned+=("$abs"$'\t'1)
    elif [ -e "$abs" ]; then
        verdict=0
        learned+=("$abs"$'\t'0)
    else
        # Target absent entirely -- an unplugged drive, not a file that changed
        # type. Keep the last known answer rather than relearning it as "no".
        verdict=$(cached_verdict "$abs")
        [ -n "$verdict" ] || verdict=$(guess_from_name "$abs")
    fi
    [ "$verdict" = 1 ] && printf '%s\n' "$name"
done < <(find "$dir" -maxdepth 1 -mindepth 1 -type l -printf '%f\t%l\n' 2>/dev/null)

# Only rewrite when something was actually observed live, so a run with the
# drive absent cannot erase what an earlier run learned.
if [ ${#learned[@]} -gt 0 ]; then
    {
        printf '%s\n' "${learned[@]}"
        # Carry over entries for targets this run did not look at. Guarded with
        # an `if`, not `&&`: on the very first run there is no cache to read, the
        # test fails, and as the group's last command that made the whole
        # redirection non-zero -- so an `&& mv` never fired and the cache could
        # never come into existence at all.
        if [ -r "$cache" ]; then
            awk -F'\t' 'NR==FNR { k[$1]; next } !($1 in k)' \
                <(printf '%s\n' "${learned[@]}") "$cache" 2>/dev/null || true
        fi
    } > "$cache.tmp" 2>/dev/null
    mv -f "$cache.tmp" "$cache" 2>/dev/null || true
fi
exit 0
