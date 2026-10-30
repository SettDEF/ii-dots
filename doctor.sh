#!/usr/bin/env bash
# doctor.sh: checks that the desktop is in order (Hyprland config, shell, zsh, apps) and says what to do where not
#   bash doctor.sh        (bootstrap.sh runs it at the end)
set -u
G=$'\e[32m' Rd=$'\e[31m' Y=$'\e[33m' D=$'\e[2m' N=$'\e[0m'
bad=0 warned=0
ok()   { printf ' %s✓%s %s\n' "$G" "$N" "$1"; }
fail() { printf ' %s✗%s %s\n   %s→ %s%s\n' "$Rd" "$N" "$1" "$D" "$2" "$N"; bad=$((bad + 1)); }
note() { printf ' %s!%s %s\n   %s→ %s%s\n' "$Y" "$N" "$1" "$D" "$2" "$N"; warned=$((warned + 1)); }
have() { command -v "$1" >/dev/null 2>&1 || [ -x "$HOME/.local/bin/$1" ]; }
H="$HOME/.config/hypr"

echo "── Hyprland"
if ! have Hyprland; then fail "Hyprland is not installed" "sudo pacman -S hyprland"
elif [ ! -f "$H/hyprland.lua" ]; then fail "no $H/hyprland.lua (your config)" "cd ~/.local/src/dotfiles && git pull && bash install.sh"
else
    ok "Hyprland $(Hyprland --version 2>/dev/null | head -1 | awk '{print $2}'), config in $H"
    if grep -rqs '@SHELL_NAME@' "$H"; then fail "the config still holds @SHELL_NAME@" "bash ~/.local/share/quickshell-ii-src/hypr/apply.sh ii"; fi
    out=$(timeout 30 Hyprland --verify-config 2>&1)
    if grep -q 'config ok' <<<"$out"; then ok "the config has no errors (Hyprland --verify-config)"
    else fail "the config has errors:" "$(grep -vE '^\s*$|====' <<<"$out" | tail -8 | sed 's/^/     /')"; fi
    # programs the config starts or binds: the first word of each exec_cmd
    missing=$(grep -rhoE 'exec_cmd\("[^"]+' "$H"/hyprland.lua "$H"/lua 2>/dev/null | sed -E 's/exec_cmd\("//; s/^(env [^ ]+ |sh -c |bash -c |uwsm app -- )//; s/^["'\'']//' \
        | awk '{print $1}' | sed "s#^~#$HOME#; s#^\\\$HOME#$HOME#" | grep -vE '^\$|^\[|^-|=' | sort -u \
        | while read -r c; do have "$c" || [ -x "$c" ] || echo "$c"; done | tr '\n' ' ')
    if [ -n "$missing" ]; then note "the config calls programs that are not here: $missing" "install them, or ignore the ones for the other laptop"
    else ok "every program the config calls is installed"; fi
fi
if [ -n "${HYPRLAND_INSTANCE_SIGNATURE:-}" ] && have hyprctl; then
    errs=$(hyprctl configerrors 2>/dev/null | grep -v '^\s*$' | grep -v 'unknown request')   # loom has no configerrors
    [ -z "$errs" ] && ok "the running Hyprland reports no errors" || fail "the running Hyprland reports errors" "$(head -5 <<<"$errs")"
fi

echo "── Shell (quickshell)"
have qs && ok "quickshell installed" || fail "quickshell is not installed" "sudo pacman -S quickshell"
[ -f "$HOME/.config/quickshell/ii/shell.qml" ] && ok "the ii config is in ~/.config/quickshell/ii" || fail "no ~/.config/quickshell/ii" "bash bootstrap.sh"
grep -rqs 'qs -c\|quickshell' "$H" && ok "Hyprland starts the shell" || fail "the Hyprland config does not start the shell" "add exec-once: qs -c ii"
[ -d "$HOME/.config/illogical-impulse" ] && ok "shell settings (illogical-impulse)" || note "no shell settings yet" "they come with the dotfiles"
if pgrep -x qs >/dev/null; then ok "the shell is running"; elif [ -n "${WAYLAND_DISPLAY:-}" ]; then fail "the shell is not running" "qs -c ii   (its errors show in the terminal)"; fi

echo "── zsh"
sh=$(getent passwd "$USER" | cut -d: -f7)
[ "$sh" = /usr/bin/zsh ] && ok "zsh is your login shell" || fail "your login shell is $sh" "sudo chsh -s /usr/bin/zsh $USER   (then log in again)"
grep -qs 'config/zsh/.zshrc' "$HOME/.zshrc" && ok "~/.zshrc loads your config" || fail "~/.zshrc does not load ~/.config/zsh" "cd ~/.local/src/dotfiles && bash install.sh"
[ -f "$HOME/.zplug/init.zsh" ] && ok "zplug" || fail "zplug is missing" "git clone --depth 1 https://github.com/zplug/zplug ~/.zplug"
if have zsh; then
    t0=$(date +%s%N); errs=$(timeout 20 zsh -ic exit 2>&1 </dev/null | grep -iE 'not found|error|no such' | head -5); ms=$(( ($(date +%s%N) - t0) / 1000000 ))
    [ -z "$errs" ] && ok "zsh starts without errors (${ms} ms)" || fail "zsh shows errors when it starts:" "$(sed 's/^/     /' <<<"$errs")"
    [ "$ms" -gt 1500 ] && note "zsh takes ${ms} ms to start" "zsh -ic 'zprof' after zmodload zsh/zprof in .zshrc shows what is slow"
fi
case ":$PATH:" in *":$HOME/.local/bin:"*) ok "~/.local/bin is on PATH" ;; *) fail "~/.local/bin is not on PATH" "your apps (zash, zeit …) are not found; open a new zsh" ;; esac

echo "── Your apps"
miss=""; for a in zash zeit zett reel dotos sinew kalends arcade prog loom tinct; do have "$a" || miss+="$a "; done
[ -z "$miss" ] && ok "all installed" || note "not installed: $miss" "bash bootstrap.sh again; build logs in ~/.local/src/.logs"

echo "── System"
systemctl is-enabled NetworkManager >/dev/null 2>&1 && ok "NetworkManager on" || fail "NetworkManager is off" "sudo systemctl enable --now NetworkManager"
systemctl --user is-active pipewire.socket >/dev/null 2>&1 || systemctl --user is-active pipewire >/dev/null 2>&1 && ok "PipeWire (sound)" || note "PipeWire is not running" "systemctl --user enable --now pipewire pipewire-pulse wireplumber"
free_gb=$(df -BG --output=avail "$HOME" | tail -1 | tr -dc 0-9); [ "${free_gb:-0}" -ge 5 ] && ok "${free_gb} GB free" || note "only ${free_gb} GB free" "sudo pacman -Scc; rm -rf ~/.local/src/*/target"
fc-list | grep -qi 'Material Symbols' && ok "icon font" || fail "the icon font is missing (empty squares in the bar)" "sudo pacman -S ttf-material-symbols-variable"

echo
if [ $bad -eq 0 ]; then printf '%sAll in order%s%s\n' "$G" "$N" "$([ $warned -gt 0 ] && echo " ($warned to look at)")"
else printf '%s%d problem(s)%s, %d to look at — the → lines say what to do\n' "$Rd" "$bad" "$N" "$warned"; fi
exit $(( bad > 0 ))
