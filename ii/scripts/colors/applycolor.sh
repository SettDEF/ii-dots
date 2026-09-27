#!/usr/bin/env bash

QUICKSHELL_CONFIG_NAME="ii"
XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
XDG_CACHE_HOME="${XDG_CACHE_HOME:-$HOME/.cache}"
XDG_STATE_HOME="${XDG_STATE_HOME:-$HOME/.local/state}"
CONFIG_DIR="$XDG_CONFIG_HOME/quickshell/$QUICKSHELL_CONFIG_NAME"
CACHE_DIR="$XDG_CACHE_HOME/quickshell"
STATE_DIR="$XDG_STATE_HOME/quickshell"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

term_alpha=100 #Set this to < 100 make all your terminals transparent
# sleep 0 # idk i wanted some delay or colors dont get applied properly
if [ ! -d "$STATE_DIR"/user/generated ]; then
  mkdir -p "$STATE_DIR"/user/generated
fi
cd "$CONFIG_DIR" || exit

colornames=''
colorstrings=''
colorlist=()
colorvalues=()

scss_path="${1:-$STATE_DIR/user/generated/material_colors.scss}"
colors_json_path="${2:-$STATE_DIR/user/generated/colors.json}"

colornames=$(cat "$scss_path" | cut -d: -f1)
colorstrings=$(cat "$scss_path" | cut -d: -f2 | cut -d ' ' -f2 | cut -d ";" -f1)
IFS=$'\n'
colorlist=($colornames)     # Array of color names
colorvalues=($colorstrings) # Array of color values

apply_term() {
  # Check if terminal escape sequence template exists
  if [ ! -f "$SCRIPT_DIR/terminal/sequences.txt" ]; then
    echo "Template file not found for Terminal. Skipping that."
    return
  fi

  local temp_seq="/tmp/matugen-temp-sequences.txt"
  cp "$SCRIPT_DIR/terminal/sequences.txt" "$temp_seq"

  # Apply colors
  for i in "${!colorlist[@]}"; do
    sed -i "s/${colorlist[$i]} #/${colorvalues[$i]#\#}/g" "$temp_seq"
  done

  sed -i "s/\$alpha/$term_alpha/g" "$temp_seq"

  # Atomically publish to final location
  mkdir -p "$STATE_DIR"/user/generated/terminal
  mv "$temp_seq" "$STATE_DIR"/user/generated/terminal/sequences.txt

  local seq_raw="$STATE_DIR/user/generated/terminal/sequences.txt"
  # Stale artifact from an abandoned DCS-passthrough approach; remove so
  # nothing accidentally replays it.
  rm -f "$STATE_DIR/user/generated/terminal/sequences-tmux.txt"

  # Ask tmux which ptys are what, instead of guessing from /proc environ.
  # environ is a snapshot taken at exec() — a wezterm window spawned from
  # inside a tmux pane keeps a stale TMUX= var forever, which made the
  # OUTER wezterm pty look like a tmux pane and got it the wrong bytes.
  #   - client ttys: the pty between the tmux client and the real terminal
  #     emulator (wezterm). Writing raw OSC here goes straight to the
  #     emulator — this is THE path that re-themes a tmux-wrapped wezterm.
  #   - pane ttys: rendered by their client's emulator, which we already
  #     theme via the client tty. Writing into panes is redundant and raw
  #     OSC there would make tmux pin per-pane colours. Skip them.
  local tmux_client_ttys tmux_pane_ttys
  tmux_client_ttys=$(tmux list-clients -F '#{client_tty}' 2>/dev/null)
  tmux_pane_ttys=$(tmux list-panes -a -F '#{pane_tty}' 2>/dev/null)

  # Push to every open pty. Synchronous per pty (no `&` / disown) so two rapid
  # theme changes can't interleave writes and leave a terminal half-updated.
  #
  # Remaining ptys (neither tmux client nor pane): write raw OSC only if a
  # process on them has a real TERM (not empty/dumb/linux). Anything else
  # (KDE Connect's phone bridge, sandboxed helpers, daemons holding a pty)
  # is SKIPPED — those forward the raw bytes as text and KDE Connect would
  # surface them as a "Local System Message Service" notification on the
  # paired phone.
  for file in /dev/pts/*; do
    if [[ $file =~ ^/dev/pts/([0-9]+)$ ]]; then
      ptsnum="${BASH_REMATCH[1]}"
      if grep -qxF "$file" <<<"$tmux_client_ttys"; then
        cat "$seq_raw" >"$file" 2>/dev/null || true
        continue
      fi
      if grep -qxF "$file" <<<"$tmux_pane_ttys"; then
        continue
      fi
      is_real_term=""
      for pid in $(ps -o pid= --no-headers -t "pts/$ptsnum" 2>/dev/null); do
        [ -r "/proc/$pid/environ" ] || continue
        term_val=$(tr '\0' '\n' < "/proc/$pid/environ" 2>/dev/null \
                   | awk -F= '$1=="TERM"{print $2; exit}')
        case "$term_val" in
          ""|dumb|linux) ;;
          *) is_real_term="yes" ;;
        esac
      done
      [ -n "$is_real_term" ] || continue
      cat "$seq_raw" >"$file" 2>/dev/null || true
    fi
  done
}

# Nudge GTK / Qt apps to reload their colour scheme. Many apps watch this
# gsettings key and re-tint immediately. Cheap, dbus-only, no restart needed.
broadcast_color_scheme() {
  local mode_flag="prefer-dark"
  if [ -f "$STATE_DIR/user/generated/color.txt" ]; then
    case "$(cat "$STATE_DIR/user/generated/color.txt" 2>/dev/null)" in
      *light*|*Light*|*LIGHT*) mode_flag="prefer-light" ;;
    esac
  fi
  command -v gsettings >/dev/null 2>&1 || return 0
  gsettings set org.gnome.desktop.interface color-scheme "$mode_flag" 2>/dev/null || true

  # The colour-scheme key only flips light/dark — it does NOT make GTK re-read
  # the regenerated ~/.config/gtk-{3,4}.0/gtk.css, so running GTK apps kept the
  # previous accent until they were restarted. Bumping gtk-theme to a scratch
  # value and straight back fires a theme-changed signal, which re-parses the
  # user stylesheet. The name ends up exactly as it was, so whatever theme is
  # set in System Settings is preserved.
  local gtk_theme
  gtk_theme=$(gsettings get org.gnome.desktop.interface gtk-theme 2>/dev/null | tr -d "'")
  if [ -n "$gtk_theme" ]; then
    gsettings set org.gnome.desktop.interface gtk-theme "${gtk_theme}-tinct-reload" 2>/dev/null || true
    gsettings set org.gnome.desktop.interface gtk-theme "$gtk_theme" 2>/dev/null || true
  fi
}

apply_qt() {
  sh "$CONFIG_DIR/scripts/kvantum/materialQT.sh"          # generate kvantum theme
  python "$CONFIG_DIR/scripts/kvantum/changeAdwColors.py" # apply config colors
}

# The OSC sequences above retheme every terminal that is ALREADY OPEN. A
# terminal launched afterwards reads its own config instead, and those files
# are rendered from colors.json — which carries the Material roles but not
# term0..15. So kitty's `color2` was `tertiary` and wezterm's ANSI green was
# whatever hue the wallpaper happened to rotate it to: a new window got a
# different, unreadable palette from every window already on screen.
#
# Patched here rather than in the templates because this is the only step that
# has both the rendered files and the term values, and it runs last.
apply_term_configs() {
  local kitty_theme="$STATE_DIR/user/generated/terminal/kitty-theme.conf"
  local wezterm_colors="$XDG_CONFIG_HOME/wezterm/matugen_colors.lua"

  # term0..15 out of the same SCSS the sequences came from. The array is `tc`,
  # not `term`: a literal "$term0" has to survive the shell, and writing it
  # inside double quotes next to an array called `term` expands the array.
  local -a tc=()
  local i
  for i in $(seq 0 15); do
    # awk, not grep+cut: the pattern has to carry a literal "$", which is one
    # quoting mistake away from expanding, and this machine's grep is ugrep.
    tc[$i]=$(awk -v n="$i" 'index($0, "$term" n ":") == 1 { gsub(/[ ;]/, "", $2); print $2; exit }' FS='[:;]' "$scss_path")
    [ -n "${tc[$i]}" ] || { echo "term$i missing from $scss_path; leaving terminal configs alone"; return; }
  done

  if [ -f "$kitty_theme" ]; then
    for i in $(seq 0 15); do
      sed -i "s|^color${i}[[:space:]].*|color${i}  ${tc[$i]}|" "$kitty_theme"
    done
  fi

  if [ -f "$wezterm_colors" ]; then
    # Rewrite the two arrays in place, keeping everything else the template said.
    python3 - "$wezterm_colors" "${tc[@]}" <<'EOPY'
import re, sys
path, cols = sys.argv[1], sys.argv[2:18]
text = open(path).read()
def block(name, values):
    rows = ",\n".join(f'        "{v}"' for v in values)
    return f"{name} = {{\n{rows},\n    }}"
text = re.sub(r'ansi\s*=\s*\{.*?\}', block("ansi", cols[0:8]), text, count=1, flags=re.S)
text = re.sub(r'brights\s*=\s*\{.*?\}', block("brights", cols[8:16]), text, count=1, flags=re.S)
open(path, "w").write(text)
EOPY
  fi
}

# Check if terminal theming is enabled in config
CONFIG_FILE="$XDG_CONFIG_HOME/illogical-impulse/config.json"
if [ -f "$CONFIG_FILE" ]; then
  enable_terminal=$(jq -r '.appearance.wallpaperTheming.enableTerminal' "$CONFIG_FILE")
  if [ "$enable_terminal" = "true" ]; then
    apply_term
  fi
else
  echo "Config file not found at $CONFIG_FILE. Applying terminal theming by default."
  apply_term
fi

# Nudge GTK / Qt apps to flip their color scheme even if their config file
# hasn't changed in a way they detect. Runs after apply_term so all surfaces
# (terminal pty + dbus broadcast) get the new theme in one synchronous pass.
broadcast_color_scheme

# Rebuild all matugen templates (including Bitwig Studio theme.bte)
# using the final transformed, high-contrast, or preset-remapped colors.json.
if [[ "${TINCT:-1}" == "1" ]] && command -v tinct >/dev/null 2>&1; then
    # Rust template renderer — byte-identical to rebuild_templates.py+matugen,
    # ~1ms instead of ~400ms. TINCT=0 falls back to the python path.
    #
    # --image is passed explicitly from the live config. Without it the
    # renderer falls back to reading the path.txt it also WRITES, so a single
    # colour-based (non-image) run put "Null" in there and every later run
    # copied that Null forward — leaving everything that reads the active
    # wallpaper path stuck on a dead value.
    wallpaper_now=$(jq -r '.background.wallpaperPath // empty' \
        "$XDG_CONFIG_HOME/illogical-impulse/config.json" 2>/dev/null)
    if [ -n "$wallpaper_now" ] && [ -e "$wallpaper_now" ]; then
        tinct render --colors "$colors_json_path" --image "$wallpaper_now" >/dev/null 2>&1 || true
    else
        tinct render --colors "$colors_json_path" >/dev/null 2>&1 || true
    fi
else
    echo "applycolor: tinct not available — templates not rendered" >&2
fi

# MUST run after the render above, for the same reason the nvim patch below
# does: the render rewrites kitty's and wezterm's colour files from templates
# that can only see colors.json, and term0..15 are not in it.
apply_term_configs

# Substitute $term0 into nvim's matugen palette and live-reload running nvims.
# Runs here (not as matugen post_hook) because $term0 is only written into
# material_colors.scss by generate_colors_material.py, which fires *after*
# matugen. MUST run AFTER rebuild_templates.py above — that re-renders
# nvim_colors.lua from the template, re-introducing the A0 = "__TERM0__"
# placeholder. Running before it (the old order) left the placeholder in the
# final file, which crashes cocoa.nvim ("arithmetic on nil" in blend()).
if [ -x "$HOME/.config/tinct/templates/neovim/post-hook.sh" ]; then
    "$HOME/.config/tinct/templates/neovim/post-hook.sh" 2>/dev/null || true
fi

# Keep wezterm's config-level background in sync with the OSC palette.
# The wezterm matugen template uses {{colors.surface}}, which is a different
# colour than the terminal-tuned $term0 that the live OSC path applies —
# without this, a freshly-started wezterm window settles on a different
# background than the already-running, OSC-themed ones. Must run AFTER
# rebuild_templates.py above, because that re-renders matugen_colors.lua.
wezterm_colors="$XDG_CONFIG_HOME/wezterm/matugen_colors.lua"
if [ -f "$wezterm_colors" ]; then
    term0=""
    for i in "${!colorlist[@]}"; do
        [ "${colorlist[$i]}" = '$term0' ] && term0="${colorvalues[$i]}"
    done
    # Only the top-level `    background    = "#xxxxxx",` (4-space indent);
    # the deeper-indented tab_bar.background is intentionally left alone.
    [ -n "$term0" ] && \
        sed -i -E "s|^(    background[[:space:]]+= )\"[^\"]*\"|\1\"${term0}\"|" "$wezterm_colors"
fi

# apply_qt & # Qt theming is already handled by kde-material-colors

# GREETER-SYNC : keep /var/cache/greeter/colors.json in sync with the session
if [ -w /var/cache/greeter ]; then
    cp "$colors_json_path" /var/cache/greeter/colors.json 2>/dev/null
fi
