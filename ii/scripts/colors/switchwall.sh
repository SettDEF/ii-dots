#!/usr/bin/env bash

export PATH="$HOME/.local/bin:$PATH"

QUICKSHELL_CONFIG_NAME="ii"
XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
XDG_CACHE_HOME="${XDG_CACHE_HOME:-$HOME/.cache}"
XDG_STATE_HOME="${XDG_STATE_HOME:-$HOME/.local/state}"
CONFIG_DIR="$XDG_CONFIG_HOME/quickshell/$QUICKSHELL_CONFIG_NAME"
CACHE_DIR="$XDG_CACHE_HOME/quickshell"
STATE_DIR="$XDG_STATE_HOME/quickshell"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SHELL_CONFIG_FILE="$XDG_CONFIG_HOME/illogical-impulse/config.json"
WALL_DB="$STATE_DIR/wallpaper_history.jsonl"
MATUGEN_DIR="$XDG_CONFIG_HOME/matugen"
terminalscheme="$SCRIPT_DIR/terminal/scheme-base.json"

mkdir -p "$(dirname "$WALL_DB")"
touch "$WALL_DB"

mark_seen() { # $1=source $2=id $3=url
  jq -n --arg s "$1" --arg i "$2" --arg u "$3" --argjson t "$(date +%s)" \
    '{type:"seen",source:$s,id:$i,url:$u,ts:$t}' >> "$WALL_DB"
}

is_seen() { # $1=id
  grep -q "\"id\":\"$1\"" "$WALL_DB" 2>/dev/null
}

get_reddit_after() { # $1=sub $2=sort -> returns token
  tac "$WALL_DB" | grep -m1 "\"type\":\"reddit_cursor\".*\"sub\":\"$1\".*\"sort\":\"$2\"" | jq -r '.after // empty'
}

set_reddit_after() { # $1=sub $2=sort $3=after
  jq -n --arg sub "$1" --arg sort "$2" --arg after "$3" --argjson ts "$(date +%s)" \
    '{type:"reddit_cursor",ts:$ts,sub:$sub,sort:$sort,after:$after}' >> "$WALL_DB"
}

log_fetch() { # $1=source $2=sub $3=sort $4=page $5=urls_json
  jq -n --arg src "$1" --arg sub "$2" --arg sort "$3" --arg page "$4" \
        --argjson urls "$5" --argjson ts "$(date +%s)" \
        '{type:"fetch",ts:$ts,source:$src,subreddit:$sub,sort:$sort,page:$page,urls:$urls}' >> "$WALL_DB"
}

# ── prune history and cache ─────────────────────────────────────────────
cleanup_history() {
    local keep_days="${1:-90}"
    local cache_dir="$XDG_CACHE_HOME/quickshell/select-thumbs"
    local cutoff
    cutoff=$(date -d "$keep_days days ago" +%s)

    echo "[cleanup] Pruning history older than $keep_days days..."

    if [[ -s "$WALL_DB" ]] && command -v jq &>/dev/null; then
        local tmp; tmp=$(mktemp)
        jq -c "select(.ts >= $cutoff)" "$WALL_DB" > "$tmp" && mv "$tmp" "$WALL_DB"
    fi

    find "$cache_dir" -type f -mtime +"$keep_days" -delete 2>/dev/null

    local size_mb
    size_mb=$(du -sm "$cache_dir" 2>/dev/null | cut -f1)
    if [[ "$size_mb" -gt 2048 ]]; then
        echo "[cleanup] Cache >2GB, trimming oldest..."
        find "$cache_dir" -type f -printf '%T@ %p\n' | sort -n | head -n 500 | cut -d' ' -f2- | xargs -r rm -f
    fi

    notify-send -a "Wallpaper switcher" "Cleanup done" "History: $keep_days days kept"
}

handle_kde_material_you_colors() {
    if [ -f "$SHELL_CONFIG_FILE" ]; then
        enable_qt_apps=$(jq -r '.appearance.wallpaperTheming.enableQtApps' "$SHELL_CONFIG_FILE")
        if [ "$enable_qt_apps" == "false" ]; then
            return
        fi
    fi

    local kde_scheme_variant=""
    case "$type_flag" in
        scheme-content|scheme-expressive|scheme-fidelity|scheme-fruit-salad|scheme-monochrome|scheme-neutral|scheme-rainbow|scheme-tonal-spot)
            kde_scheme_variant="$type_flag"
            ;;
        *)
            kde_scheme_variant="scheme-tonal-spot"
            ;;
    esac
    "$XDG_CONFIG_HOME"/matugen/templates/kde/kde-material-you-colors-wrapper.sh --scheme-variant "$kde_scheme_variant" \
        >/dev/null 2>&1 || true
}

pre_process() {
    local mode_flag="$1"
    # Light/dark preference auto-follows wallpaper brightness so apps
    # respecting freedesktop's color-scheme hint flip correctly.
    # Theme NAMES (icon, gtk, cursor) are intentionally NOT set here —
    # KDE System Settings stays the source of truth for those. Was
    # previously also setting gtk-theme=adw-gtk3-dark/adw-gtk3 here,
    # which overrode whatever theme the user picked every wallpaper
    # change.
    if [[ "$mode_flag" == "dark" ]]; then
        gsettings set org.gnome.desktop.interface color-scheme 'prefer-dark'
    elif [[ "$mode_flag" == "light" ]]; then
        gsettings set org.gnome.desktop.interface color-scheme 'prefer-light'
    fi

    if [ ! -d "$CACHE_DIR"/user/generated ]; then
        mkdir -p "$CACHE_DIR"/user/generated
    fi
}

post_process() {
    local screen_width="$1"
    local screen_height="$2"
    local wallpaper_path="$3"

    handle_kde_material_you_colors
    "$SCRIPT_DIR/code/material-code-set-color.sh" > /tmp/vscode-theme-apply.log 2>&1
}

check_and_prompt_upscale() {
    local img="$1"
    min_width_desired="$(hyprctl monitors -j | jq '([.[].width] | max)' | xargs)"
    min_height_desired="$(hyprctl monitors -j | jq '([.[].height] | max)' | xargs)"

    if command -v identify &>/dev/null && [ -f "$img" ]; then
        local img_width img_height
        if is_video "$img"; then
            img_width=$min_width_desired
            img_height=$min_height_desired
        else
            img_width=$(identify -ping -format "%w" "$img" 2>/dev/null)
            img_height=$(identify -ping -format "%h" "$img" 2>/dev/null)
        fi
        if [[ "$img_width" -lt "$min_width_desired" || "$img_height" -lt "$min_height_desired" ]]; then
            # Quickshell collapses the notification body to one elided line
            # when not expanded — keep the punchline (numbers + arrow) at the
            # FRONT so it survives the squeeze. Use the proper multiplication
            # sign (×) and an em arrow for typographic polish.
            action=$(notify-send "Upscale wallpaper?" \
                "${img_width}×${img_height} → ${min_width_desired}×${min_height_desired} recommended" \
                -A "open_upscayl=Upscale now" \
                -i "view-fullscreen-symbolic" \
                -a "Wallpaper switcher" \
                -h "string:image-path:view-fullscreen-symbolic" \
                -h "string:category:transfer")
            if [[ "$action" == "open_upscayl" ]]; then
                if command -v upscayl &>/dev/null; then
                    nohup upscayl > /dev/null 2>&1 &
                else
                    action2=$(notify-send \
                        -a "Wallpaper switcher" \
                        -c "im.error" \
                        -A "install_upscayl=Install Upscayl (Arch)" \
                        "Install Upscayl?" \
                        "yay -S upscayl-bin")
                    if [[ "$action2" == "install_upscayl" ]]; then
                        kitty -1 yay -S upscayl-bin
                        if command -v upscayl &>/dev/null; then
                            nohup upscayl > /dev/null 2>&1 &
                        fi
                    fi
                fi
            fi
        fi
    fi
}

CUSTOM_DIR="$XDG_CONFIG_HOME/hypr/custom"
RESTORE_SCRIPT_DIR="$CUSTOM_DIR/scripts"
RESTORE_SCRIPT="$RESTORE_SCRIPT_DIR/__restore_video_wallpaper.sh"
THUMBNAIL_DIR="$RESTORE_SCRIPT_DIR/mpvpaper_thumbnails"
VIDEO_OPTS="no-audio loop hwdec=auto scale=bilinear interpolation=no video-sync=display-resample panscan=1.0 video-scale-x=1.0 video-scale-y=1.0 video-align-x=0.5 video-align-y=0.5 load-scripts=no"

is_video() {
    local extension="${1##*.}"
    extension="${extension,,}"
    # gif is included: mpvpaper decodes & loops animated GIFs as wallpapers.
    [[ "$extension" == "mp4" || "$extension" == "webm" || "$extension" == "mkv" || "$extension" == "avi" || "$extension" == "mov" || "$extension" == "m4v" || "$extension" == "gif" ]] && return 0 || return 1
}

kill_existing_mpvpaper() {
    pkill -f -9 mpvpaper || true
}

create_restore_script() {
    local video_path=$1
    cat > "$RESTORE_SCRIPT.tmp" << EOF
#!/bin/bash
# Generated by switchwall.sh - Don't modify it by yourself.
# Time: $(date)

pkill -f -9 mpvpaper

for monitor in \$(hyprctl monitors -j | jq -r '.[] | .name'); do
    setsid mpvpaper -o "$VIDEO_OPTS" "\$monitor" "$video_path" >/dev/null 2>&1 &
    sleep 0.1
done
EOF
    mv "$RESTORE_SCRIPT.tmp" "$RESTORE_SCRIPT"
    chmod +x "$RESTORE_SCRIPT"
}

remove_restore() {
    cat > "$RESTORE_SCRIPT.tmp" << EOF
#!/bin/bash
# The content of this script will be generated by switchwall.sh - Don't modify it by yourself.
EOF
    mv "$RESTORE_SCRIPT.tmp" "$RESTORE_SCRIPT"
}

set_wallpaper_path() {
    local path="$1"
    if [ -f "$SHELL_CONFIG_FILE" ]; then
        jq --arg path "$path" '.background.wallpaperPath = $path | .background.wallpaperSourcePath = $path' "$SHELL_CONFIG_FILE" > "$SHELL_CONFIG_FILE.tmp" && mv "$SHELL_CONFIG_FILE.tmp" "$SHELL_CONFIG_FILE"
    fi
    log_wallpaper_recent "$path"
}

# Append wallpaper to recents log, capped at 40 entries.
log_wallpaper_recent() {
    local path="$1"
    [[ -z "$path" || ! -f "$path" ]] && return
    # Skip the WallTune processed file — we want the SOURCE wallpapers.
    [[ "$path" == *"/walltune/processed.png" ]] && return
    [[ "$path" == /tmp/walltune-* ]] && return
    local recents="$STATE_DIR/wallpaper-recents.jsonl"
    mkdir -p "$(dirname "$recents")"
    local ts; ts=$(date +%s)
    # Drop any existing entry with the same path, append the new one, keep last 40.
    if [[ -f "$recents" ]]; then
        local tmp; tmp=$(mktemp)
        jq -c --arg p "$path" 'select(.path != $p)' "$recents" > "$tmp" 2>/dev/null || true
        mv "$tmp" "$recents"
    fi
    jq -cn --arg p "$path" --argjson t "$ts" '{type:"recent",path:$p,ts:$t}' >> "$recents"
    # Cap at 40
    if [[ -f "$recents" ]] && [[ $(wc -l < "$recents") -gt 40 ]]; then
        local tmp; tmp=$(mktemp)
        tail -n 40 "$recents" > "$tmp" && mv "$tmp" "$recents"
    fi
}

set_thumbnail_path() {
    local path="$1"
    if [ -f "$SHELL_CONFIG_FILE" ]; then
        jq --arg path "$path" '.background.thumbnailPath = $path' "$SHELL_CONFIG_FILE" > "$SHELL_CONFIG_FILE.tmp" && mv "$SHELL_CONFIG_FILE.tmp" "$SHELL_CONFIG_FILE"
    fi
}

# ─────────────────────────────────────────────────────────────────────────────
# _select_fetch_reddit  — populate $1 (list file) from a subreddit
#   - Paginates automatically: each run advances one Reddit page via after= cursor
#   - Already-seen images are listed as "path [seen]" so fzf shows them tagged
#   - Downloads cached per day in reddit-SUB-SORT-YYYYMMDD/
# _select_fetch_wallhaven — populate $1 (list file) from Wallhaven API
# ─────────────────────────────────────────────────────────────────────────────
_select_fetch_reddit() {
    local list_file="$1"
    local sub="$2"
    local sort="${3:-hot}"
    local thumb_cache="$4"
    local day="$(date +%Y%m%d)"
    local reddit_tmp="$thumb_cache/reddit-${sub}-${sort}-${day}"
    mkdir -p "$reddit_tmp"

    local after
    after=$(get_reddit_after "$sub" "$sort")
    echo "[select] Fetching r/${sub}/${sort} after=${after:-START}…" >&2

    local api_url="https://old.reddit.com/r/${sub}/${sort}.json?limit=100&raw_json=1"
    [[ -n "$after" ]] && api_url+="&after=${after}"

    local json
    json=$(curl -sL --max-time 15 \
        -H "User-Agent: Mozilla/5.0 (X11; Linux x86_64) quickshell-ii/1.0" \
        -H "Accept: application/json" \
        "$api_url")

    local _urls=()

    if ! echo "$json" | jq -e. >/dev/null 2>&1; then
        echo "[select] Reddit blocked JSON, falling back to gallery-dl…" >&2
        mapfile -t _urls < <(gallery-dl --get-urls \
            -o "extractor.reddit.comments=0" \
            -o "extractor.reddit.videos=true" \
            "https://old.reddit.com/r/${sub}/${sort}/" 2>/dev/null \
            | grep -iE "\.(jpg|png|jpeg|webp|mp4|webm)$")
    else
        local new_after
        new_after=$(echo "$json" | jq -r '.data.after // empty')

        # Pull direct URL + Reddit CDN preview (fixes posts where url is a gallery page)
        mapfile -t _urls < <(echo "$json" | jq -r '
            .data.children[].data | (
                (.url_overridden_by_dest // ""),
                (.preview.images[0].source.url // "" | gsub("&amp;";"&"))
            )
            | select(. != "" and test("\\.(jpg|jpeg|png|webp|mp4|webm)([?#]|$)"; "i"))
        ' | sort -u)

        if [[ ${#_urls[@]} -eq 0 ]]; then
            echo "[select] No direct URLs, falling back to gallery-dl…" >&2

            # Download + live count on one updating line (no archive, no extra text)
            count=0
            mapfile -t _urls < <(
                gallery-dl \
                    -o "output.mode=terminal" \
                    -o "extractor.reddit.comments=0" \
                    -o "extractor.reddit.videos=true" \
                    "https://old.reddit.com/r/${sub}/${sort}/" 2>&1 | \
                awk '
                    /\.(jpg|jpeg|png|webp|gif|mp4|webm|mkv|avi|mov)$/ {
                        count++
                        printf "\rDownloaded: %-5d" , count > "/dev/stderr"
                        print $0   # pass the filename/url through so mapfile still works
                    }
                    END {
                        printf "\nDownloaded: %d files total\n", count > "/dev/stderr"
                    }
                '
            )
        fi

        local urls_json
        urls_json=$(printf '%s\n' "${_urls[@]}" | jq -R '.' | jq -s '.')
        log_fetch "reddit" "$sub" "$sort" "${after:-start}" "$urls_json"
        [[ -n "$new_after" ]] && set_reddit_after "$sub" "$sort" "$new_after"
    fi

    if [[ ${#_urls[@]} -eq 0 ]]; then
        notify-send -a "Wallpaper switcher" "Reddit" "No images found in r/${sub}"
        return 1
    fi

    # Build seen-ID set in one jq pass (fast — avoids per-URL grep)
    local -A seen_ids=()
    while IFS= read -r sid; do
        [[ -n "$sid" ]] && seen_ids["$sid"]=1
    done < <(jq -r 'select(.type=="seen") | .id' "$WALL_DB" 2>/dev/null)

    mapfile -t _urls < <(printf '%s\n' "${_urls[@]}" | shuf)

    > "$list_file"
    local count=0 seen_count=0
    for url in "${_urls[@]}"; do
        local id
        id=$(printf '%s' "$url" | md5sum | cut -d' ' -f1)
        local ext="${url##*.}"; ext="${ext,,}"; ext="${ext%%\?*}"
        local dest="$reddit_tmp/${id}.${ext}"

        if [[ -n "${seen_ids[$id]:-}" ]]; then
            # Already seen: download if missing, list as tagged
            [[ -f "$dest" ]] || curl -sL --max-time 10 -A "Mozilla/5.0" -o "$dest" "$url" &
            echo "${dest} [seen]" >> "$list_file"
            (( ++seen_count ))
            continue
        fi

        [[ -f "$dest" ]] || { curl -sL --max-time 10 -A "Mozilla/5.0" -o "${dest}.tmp" "$url" && mv "${dest}.tmp" "$dest" || rm -f "${dest}.tmp"; } &
        echo "$dest" >> "$list_file"
        mark_seen "reddit" "$id" "$url"
        (( ++count >= 30 )) && break
    done
    wait
    echo "[select] Got $count new, $seen_count already seen (page: ${after:-start} → ${new_after:-end})" >&2
}

_select_fetch_wallhaven() {
    local list_file="$1"
    local query="$2"
    local purity="${3:-100}"
    local ratio="${4:-}"
    local sorting="${5:-relevance}"
    local thumb_cache="$6"
    local WALLHAVEN_API_KEY="dZDXFoYhJwerYC6iJtjo1fJQuzihoIqI"

    local wh_tmp="$thumb_cache/wallhaven-$(printf '%s' "${query}${purity}${ratio}${sorting}" | md5sum | cut -d' ' -f1)"
    mkdir -p "$wh_tmp"

    echo "[select] Fetching Wallhaven: query='${query}' purity=${purity} sorting=${sorting}…" >&2

    local wh_url="https://wallhaven.cc/api/v1/search?sorting=${sorting}&purity=${purity}&categories=111&apikey=${WALLHAVEN_API_KEY}"
    [[ -n "$query" ]] && wh_url+="&q=$(echo "$query" | sed 's/ /+/g')"
    [[ -n "$ratio" ]] && wh_url+="&ratios=${ratio}"

    local wh_response
    wh_response=$(curl -s --fail --max-time 15 "$wh_url") || {
        notify-send -a "Wallpaper switcher" "Wallhaven Error" "API call failed"
        return 1
    }

    local _wh_urls=()
    mapfile -t _wh_urls < <(echo "$wh_response" | jq -r '.data[].path' 2>/dev/null | head -24)
    if [[ ${#_wh_urls[@]} -eq 0 ]]; then
        notify-send -a "Wallpaper switcher" "Wallhaven" "No results for: $query"
        return 1
    fi

    echo "[select] Downloading ${#_wh_urls[@]} previews in parallel…" >&2
    > "$list_file"
    local idx=0 pids=()
    for url in "${_wh_urls[@]}"; do
        local ext="${url##*.}"; ext="${ext,,}"
        local dest="$wh_tmp/$(printf '%03d' $idx).${ext}"
        echo "$dest" >> "$list_file"
        if [[ ! -f "$dest" ]]; then
            { curl -s -L -o "${dest}.tmp" "$url" && mv "${dest}.tmp" "$dest" || rm -f "${dest}.tmp"; } &
            pids+=($!)
        fi
        (( idx++ )) || true
    done
    local total=${#pids[@]} done_count=0
    for pid in "${pids[@]}"; do
        wait "$pid" 2>/dev/null && (( done_count++ )) || true
        printf "\r[select] Downloaded %d/%d…" "$done_count" "$total" >&2
    done
    echo >&2
}

# ─────────────────────────────────────────────────────────────────────────────
# select_wallpaper — interactive fzf + kitty icat picker
# ─────────────────────────────────────────────────────────────────────────────
select_wallpaper() {
    local select_source="${1:-local}"
    local select_dir="${2:-}"
    local select_reddit_sub="${3:-wallpapers}"
    local select_reddit_sort="${4:-hot}"
    local select_wallhaven_query="${5:-}"
    local select_wallhaven_purity="${6:-100}"
    local select_wallhaven_ratio="${7:-}"
    local select_wallhaven_sorting="${8:-relevance}"

    # ── Re-launch inside kitty if needed ─────────────────────────────────────
    if [[ "$TERM" != "xterm-kitty" && -z "$KITTY_WINDOW_ID" ]]; then
        exec kitty \
            --title "Wallpaper Picker" \
            --override "initial_window_width=1400" \
            --override "initial_window_height=900" \
            -- bash "$0" --select-internal \
                "$select_source" \
                "$select_dir" \
                "$select_reddit_sub" \
                "$select_reddit_sort" \
                "$select_wallhaven_query" \
                "$select_wallhaven_purity" \
                "$select_wallhaven_ratio" \
                "$select_wallhaven_sorting"
        return
    fi

    # ── Dependency check ─────────────────────────────────────────────────────
    if ! command -v fzf &>/dev/null; then
        notify-send -a "Wallpaper switcher" -c "im.error" "Missing dependency" "fzf is required for --select (pacman -S fzf)"
        exit 1
    fi

    local thumb_cache="$XDG_CACHE_HOME/quickshell/select-thumbs"
    local favs_file="$XDG_CACHE_HOME/quickshell/select-favs"
    mkdir -p "$thumb_cache"
    touch "$favs_file"

    local tmp_list preview_script reload_script save_script fav_script open_script
    tmp_list="$(mktemp /tmp/switchwall-select-XXXXXX.txt)"
    preview_script="$(mktemp /tmp/switchwall-preview-XXXXXX.sh)"
    reload_script="$(mktemp /tmp/switchwall-reload-XXXXXX.sh)"
    save_script="$(mktemp /tmp/switchwall-save-XXXXXX.sh)"
    fav_script="$(mktemp /tmp/switchwall-fav-XXXXXX.sh)"
    open_script="$(mktemp /tmp/switchwall-open-XXXXXX.sh)"

    # ── Populate list ─────────────────────────────────────────────────────────
    _populate_list() {
        case "$select_source" in
            reddit)
                _select_fetch_reddit "$tmp_list" "$select_reddit_sub" "$select_reddit_sort" "$thumb_cache" || exit 1
                ;;
            wallhaven)
                _select_fetch_wallhaven "$tmp_list" "$select_wallhaven_query" \
                    "$select_wallhaven_purity" "$select_wallhaven_ratio" \
                    "$select_wallhaven_sorting" "$thumb_cache" || exit 1
                ;;
            local|*)
                local search_dir="${select_dir:-}"
                if [[ -z "$search_dir" ]]; then
                    search_dir="$(xdg-user-dir PICTURES)/Wallpapers"
                    [[ ! -d "$search_dir" ]] && search_dir="$(xdg-user-dir PICTURES)"
                fi
                if [[ ! -d "$search_dir" ]]; then
                    notify-send -a "Wallpaper switcher" "Error" "Directory not found: $search_dir"
                    exit 1
                fi
                find "$search_dir" -maxdepth 3 -type f \
                    \( -iname "*.jpg" -o -iname "*.jpeg" -o -iname "*.png" \
                       -o -iname "*.webp" -o -iname "*.gif" \
                       -o -iname "*.mp4"  -o -iname "*.webm" -o -iname "*.mkv" \) \
                    | sort > "$tmp_list"
                ;;
        esac
    }
    _populate_list

    trap 'rm -f "$tmp_list" "$preview_script" "$reload_script" "$save_script" "$fav_script" "$open_script"' RETURN

    if [[ ! -s "$tmp_list" ]]; then
        notify-send -a "Wallpaper switcher" "No images found" "Nothing to select from."
        exit 1
    fi

    # ── Preview script ────────────────────────────────────────────────────────
    cat > "$preview_script" << 'PREVIEW_EOF'
#!/usr/bin/env bash
src="$1"
src="${src% \[seen\]}"
thumb_cache="${SWITCHWALL_THUMB_CACHE}"
favs_file="${SWITCHWALL_FAVS_FILE}"

ext="${src##*.}"; ext="${ext,,}"
thumb="${thumb_cache}/$(printf '%s' "$src" | md5sum | cut -d' ' -f1).${ext}"

if [[ ! -f "$thumb" ]]; then
    case "$ext" in
        mp4|webm|mkv|avi|mov)
            thumb="${thumb_cache}/$(printf '%s' "$src" | md5sum | cut -d' ' -f1).jpg"
            ffmpeg -y -ss 0 -i "$src" -vframes 1 -vf "scale=800:-1" "$thumb" 2>/dev/null || true
            ;;
        *)
            cp "$src" "$thumb" 2>/dev/null || true
            ;;
    esac
fi

[[ -f "$thumb" ]] || { echo "No preview available"; exit 0; }

kitty icat \
    --clear \
    --transfer-mode=memory \
    --stdin=no \
    --silent 2>/dev/null || true

kitty icat \
    --transfer-mode=memory \
    --stdin=no \
    --scale-up \
    --place="${FZF_PREVIEW_COLUMNS}x$((FZF_PREVIEW_LINES - 4))@0x0" \
    "$thumb" 2>/dev/null

printf '\n'
name="$(basename "$src")"
size="" dims="" is_fav=""

if [[ -f "$src" ]]; then
    bytes=$(stat -c%s "$src" 2>/dev/null || stat -f%z "$src" 2>/dev/null || echo 0)
    if   (( bytes >= 1048576 )); then size="$(echo "scale=1; $bytes/1048576" | bc) MB"
    elif (( bytes >= 1024 ));    then size="$(echo "scale=0; $bytes/1024"    | bc) KB"
    else size="${bytes} B"; fi
fi

case "$ext" in
    mp4|webm|mkv|avi|mov) dims="[video]" ;;
    *)
        if command -v identify &>/dev/null; then
            dims="$(identify -ping -format '%wx%h' "$src" 2>/dev/null || true)"
        fi
        ;;
esac

grep -qxF "$src" "$favs_file" 2>/dev/null && is_fav=" ★"
printf '%-38s  %-12s  %s%s\n' "$name" "${dims}" "${size}" "$is_fav"
PREVIEW_EOF
    chmod +x "$preview_script"

    # ── Reload script ─────────────────────────────────────────────────────────
    cat > "$reload_script" << RELOAD_EOF
#!/usr/bin/env bash
source "${BASH_SOURCE[0]}"
export XDG_CACHE_HOME="$XDG_CACHE_HOME"
select_source="$select_source"
select_dir="$select_dir"
select_reddit_sub="$select_reddit_sub"
select_reddit_sort="$select_reddit_sort"
select_wallhaven_query="$select_wallhaven_query"
select_wallhaven_purity="$select_wallhaven_purity"
select_wallhaven_ratio="$select_wallhaven_ratio"
select_wallhaven_sorting="$select_wallhaven_sorting"
thumb_cache="$thumb_cache"
tmp_list="$tmp_list"

case "\$select_source" in
    reddit)
        _select_fetch_reddit "\$tmp_list" "\$select_reddit_sub" "\$select_reddit_sort" "\$thumb_cache"
        ;;
    wallhaven)
        _select_fetch_wallhaven "\$tmp_list" "\$select_wallhaven_query" \
            "\$select_wallhaven_purity" "\$select_wallhaven_ratio" \
            "\$select_wallhaven_sorting" "\$thumb_cache"
        ;;
    *)
        find "\${select_dir:-\$(xdg-user-dir PICTURES)/Wallpapers}" -maxdepth 3 -type f \
            \( -iname "*.jpg" -o -iname "*.jpeg" -o -iname "*.png" \
               -o -iname "*.webp" -o -iname "*.gif" \
               -o -iname "*.mp4"  -o -iname "*.webm" -o -iname "*.mkv" \) \
            | sort > "\$tmp_list"
        ;;
esac
cat "\$tmp_list"
RELOAD_EOF
    chmod +x "$reload_script"

    # ── Save script ───────────────────────────────────────────────────────────
    cat > "$save_script" << 'SAVE_EOF'
#!/usr/bin/env bash
src="$1"; src="${src% \[seen\]}"
[[ -f "$src" ]] || exit 1
dest="$HOME/Pictures/$(basename "$src")"
cp "$src" "$dest" && \
    notify-send -a "Wallpaper switcher" "Saved" "$(basename "$src") → ~/Pictures"
SAVE_EOF
    chmod +x "$save_script"

    # ── Favourite toggle ──────────────────────────────────────────────────────
    cat > "$fav_script" << FAV_EOF
#!/usr/bin/env bash
src="\$1"; src="\${src% \[seen\]}"
favs="$favs_file"
touch "\$favs"
if grep -qxF "\$src" "\$favs" 2>/dev/null; then
    grep -vxF "\$src" "\$favs" > "\${favs}.tmp" && mv "\${favs}.tmp" "\$favs"
    notify-send -a "Wallpaper switcher" "Removed from favourites" "\$(basename "\$src")"
else
    echo "\$src" >> "\$favs"
    notify-send -a "Wallpaper switcher" "Added to favourites ★" "\$(basename "\$src")"
fi
FAV_EOF
    chmod +x "$fav_script"

    # ── Open in viewer ────────────────────────────────────────────────────────
    cat > "$open_script" << 'OPEN_EOF'
#!/usr/bin/env bash
src="$1"; src="${src% \[seen\]}"
[[ -f "$src" ]] || exit 1
for viewer in imv eog feh gwenview; do
    if command -v "$viewer" &>/dev/null; then
        nohup "$viewer" "$src" > /dev/null 2>&1 &
        exit 0
    fi
done
xdg-open "$src" > /dev/null 2>&1 &
OPEN_EOF
    chmod +x "$open_script"

    export SWITCHWALL_THUMB_CACHE="$thumb_cache"
    export SWITCHWALL_FAVS_FILE="$favs_file"

    # ── Header ────────────────────────────────────────────────────────────────
    local hdr
    case "$select_source" in
        reddit)    hdr="Reddit › r/${select_reddit_sub}/${select_reddit_sort}" ;;
        wallhaven) hdr="Wallhaven › ${select_wallhaven_query:-random} (purity=${select_wallhaven_purity}, sort=${select_wallhaven_sorting})" ;;
        *)         hdr="Local › ${select_dir:-$(xdg-user-dir PICTURES)/Wallpapers}" ;;
    esac

    # ── Launch fzf ────────────────────────────────────────────────────────────
    local selected
    selected=$(fzf \
        --prompt="  Wallpaper  " \
        --header="${hdr}
ENTER apply · ESC cancel · C-d dark · C-l light · C-s save · C-r reload · C-f fav · C-o open" \
        --layout=reverse \
        --preview="$preview_script {}" \
        --preview-window="right:60%:wrap:noinfo" \
        --bind="ctrl-d:execute-silent(echo dark > /tmp/switchwall-mode-$$)+accept" \
        --bind="ctrl-l:execute-silent(echo light > /tmp/switchwall-mode-$$)+accept" \
        --bind="ctrl-s:execute-silent($save_script {})" \
        --bind="ctrl-r:reload($reload_script)" \
        --bind="ctrl-f:execute-silent($fav_script {})+refresh-preview" \
        --bind="ctrl-o:execute-silent($open_script {})" \
        --expect="ctrl-d,ctrl-l" \
        --height=100% \
        --border=none \
        --color="bg+:-1,fg+:bright-white,hl:yellow,hl+:yellow,prompt:cyan,pointer:cyan,header:bright-black,info:bright-black" \
        < "$tmp_list") || true

    local forced_mode=""
    if [[ -f "/tmp/switchwall-mode-$$" ]]; then
        forced_mode="$(cat /tmp/switchwall-mode-$$)"
        rm -f "/tmp/switchwall-mode-$$"
    fi

    if [[ -z "$selected" ]]; then
        echo "[select] Cancelled." >&2
        exit 0
    fi

    if [[ "$selected" == *$'\n'* ]]; then
        selected="$(echo "$selected" | tail -n1)"
    fi

    # Strip [seen] before returning path
    selected="${selected% \[seen\]}"

    echo "[select] Chosen: $selected" >&2
    echo "__SELECTED__${selected}__MODE__${forced_mode}"
}

switch() {
    imgpath="$1"
    mode_flag="$2"
    type_flag="$3"
    color_flag="$4"
    color="$5"
    _reddit_sub="$6"
    _reddit_sort="$7"
    _reddit_ratio="$8"
    _reddit_media="$9"
    _wallhaven_purity="${10:-111}"
    _wallhaven_ratio="${11:-}"

    # Start Gemini auto-categorization if enabled
    aiStylingEnabled=$(jq -r '.background.clock.cookie.aiStyling' "$SHELL_CONFIG_FILE")
    if [[ "$aiStylingEnabled" == "true" ]]; then
        "$SCRIPT_DIR/../ai/gemini-categorize-wallpaper.sh" "$imgpath" > "$STATE_DIR/user/generated/wallpaper/category.txt" &
    fi

    # === Wallhaven random mode ================================================
    if [[ "$imgpath" == "--wallhaven" ]]; then
        local purity_level="$_wallhaven_purity"
        local ratios="$_wallhaven_ratio"
        local sorting="random"
        local order="desc"
        local min_res="1920x1080"
        local categories="111"
        WALLHAVEN_API_KEY="dZDXFoYhJwerYC6iJtjo1fJQuzihoIqI"

        local api_url="https://wallhaven.cc/api/v1/search?sorting=${sorting}&order=${order}&categories=${categories}&purity=${purity_level}&atleast=${min_res}"
        [[ -n "$ratios" ]] && api_url="${api_url}&ratios=${ratios}"
        if [[ "$purity_level" != "100" || "$categories" != "111" ]]; then
            api_url="${api_url}&apikey=${WALLHAVEN_API_KEY}"
        fi

        local response
        response=$(curl -s --fail --max-time 10 "$api_url") || {
            notify-send "Wallhaven Error" "API call failed (network/key/rate limit?)"
            exit 1
        }

        imgpath=$(echo "$response" | jq -r '.data[0].path // empty' 2>/dev/null)

        if [[ -z "$imgpath" ]]; then
            notify-send "Wallhaven" "No results – retrying broader"
            local broad_url="https://wallhaven.cc/api/v1/search?sorting=random&purity=100&categories=111"
            response=$(curl -s --fail --max-time 10 "$broad_url") || {
                notify-send "Wallhaven Critical" "API dead – check connection"
                exit 1
            }
            imgpath=$(echo "$response" | jq -r '.data[0].path // empty')
            if [[ -z "$imgpath" ]]; then
                notify-send "Wallhaven" "Even broadest search empty – API issue?"
                exit 1
            fi
        fi

        local tmp_img="/tmp/wallhaven-$(date +%s).jpg"
        curl -s -L -o "$tmp_img" "$imgpath" || {
            notify-send "Download failed" "$imgpath"
            exit 1
        }
        imgpath="$tmp_img"
        cp "$tmp_img" "$HOME/Pictures/Wallhaven_$(basename "$imgpath")" 2>/dev/null || true
    fi

    # === Reddit Wallpapers / NSFW from subreddit ==============================
    if [[ "$imgpath" == "--reddit-wallpapers" || "$imgpath" == "--reddit-nsfw" ]]; then
        [[ "$imgpath" == "--reddit-wallpapers" ]] && _reddit_sub="${_reddit_sub:-wallpapers}" || _reddit_sub="${_reddit_sub:-RealGirls}"
        _reddit_sort="${_reddit_sort:-hot}"
        _reddit_ratio="${_reddit_ratio:-}"
        _reddit_media="${_reddit_media:-any}"
        local fetch_limit=25
        local max_tries=10

        if [[ ! "$_reddit_sort" =~ ^(hot|new|top|rising)$ ]]; then
            _reddit_sort="hot"
        fi

        local reddit_url="https://www.reddit.com/r/${_reddit_sub}/${_reddit_sort}/"
        echo "[Reddit] Fetching from: $reddit_url (media: ${_reddit_media}, ratio: ${_reddit_ratio:-any})" >&2

        local image_urls=()
        mapfile -t image_urls < <(gallery-dl --get-urls \
            -o "extractor.reddit.comments=0" \
            -o "extractor.reddit.videos=true" \
            "${reddit_url}" 2>/dev/null | grep -iE "\.(jpg|png|jpeg|mp4|webm|mkv|avi|mov)$" | head -${fetch_limit})

        echo "[Reddit] Found ${#image_urls[@]} results" >&2

        if [[ ${#image_urls[@]} -eq 0 ]]; then
            notify-send "Reddit" "No media found in r/${_reddit_sub}/${_reddit_sort}"
            exit 1
        fi

        local selected_url="" tmp_img="" tried=0
        local shuffled=()
        mapfile -t shuffled < <(printf '%s\n' "${image_urls[@]}" | shuf)

        for url in "${shuffled[@]}"; do
            [[ $tried -ge $max_tries ]] && break
            tried=$(( tried + 1 ))

            local ext="${url##*.}"
            local candidate="/tmp/reddit-$(date +%s%N).${ext}"
            curl -s -L -o "$candidate" "$url" || continue

            if [[ "$_reddit_media" == "video" || "$_reddit_media" == "mp4" ]] && ! is_video "$candidate"; then
                echo "[Reddit] Skipping non-video: $url" >&2
                rm -f "$candidate"
                continue
            fi

            if [[ -n "$_reddit_ratio" ]] && command -v identify &>/dev/null && ! is_video "$candidate"; then
                local img_w img_h ratio_w ratio_h expected actual ok
                img_w=$(identify -ping -format "%w" "$candidate" 2>/dev/null)
                img_h=$(identify -ping -format "%h" "$candidate" 2>/dev/null)
                ratio_w="${_reddit_ratio%%:*}"
                ratio_h="${_reddit_ratio##*:}"
                expected=$(echo "scale=4; $ratio_w / $ratio_h" | bc)
                actual=$(echo "scale=4; $img_w / $img_h" | bc)
                ok=$(echo "$actual >= ($expected - 0.05)" | bc -l)
                if [[ "$ok" != "1" ]]; then
                    echo "[Reddit] Skipping ${url} (${img_w}x${img_h} != ${_reddit_ratio})" >&2
                    rm -f "$candidate"
                    continue
                fi
            fi

            selected_url="$url"
            tmp_img="$candidate"
            break
        done

        if [[ -z "$selected_url" ]]; then
            notify-send "Reddit" "No matching media found (mode: ${_reddit_media}, ratio: ${_reddit_ratio:-any})"
            exit 1
        fi

        echo "[Reddit] Selected: $selected_url" >&2
        imgpath="$tmp_img"
        cp "$tmp_img" "$HOME/Pictures/Reddit_${_reddit_sub}_$(basename "$tmp_img")" 2>/dev/null || true

        if is_video "$tmp_img"; then
            notify-send "Reddit Wallpaper" "Video loaded from r/${_reddit_sub}: $(basename "$tmp_img")"
        else
            notify-send "Reddit Wallpaper" "Image loaded from r/${_reddit_sub}: $(basename "$tmp_img")"
        fi
    fi

    read -r scale screenx screeny screensizey < <(hyprctl monitors -j | jq '.[] | select(.focused) | .scale, .x, .y, .height' | xargs)
    local cursorposx cursorposy cursorposy_inverted
    cursorposx=$(hyprctl cursorpos -j | jq '.x' 2>/dev/null) || cursorposx=960
    cursorposx=$(bc <<< "scale=0; ($cursorposx - $screenx) * $scale / 1")
    cursorposy=$(hyprctl cursorpos -j | jq '.y' 2>/dev/null) || cursorposy=540
    cursorposy=$(bc <<< "scale=0; ($cursorposy - $screeny) * $scale / 1")
    cursorposy_inverted=$((screensizey - cursorposy))

    local matugen_args=() generate_colors_material_args=()

    if [[ "$color_flag" == "1" ]]; then
        matugen_args=(color hex "$color")
        generate_colors_material_args=(--color "$color")
    else
        if [[ -z "$imgpath" ]]; then
            echo 'Aborted'
            exit 0
        fi

        check_and_prompt_upscale "$imgpath" &
        kill_existing_mpvpaper

        if is_video "$imgpath"; then
            mkdir -p "$THUMBNAIL_DIR"

            local missing_deps=()
            command -v mpvpaper &>/dev/null || missing_deps+=("mpvpaper")
            command -v ffmpeg   &>/dev/null || missing_deps+=("ffmpeg")

            if [ ${#missing_deps[@]} -gt 0 ]; then
                echo "Missing deps: ${missing_deps[*]}"
                local action
                action=$(notify-send \
                    -a "Wallpaper switcher" \
                    -c "im.error" \
                    -A "install_arch=Install (Arch)" \
                    "Can't switch to video wallpaper" \
                    "Missing dependencies: ${missing_deps[*]}")
                if [[ "$action" == "install_arch" ]]; then
                    kitty -1 sudo pacman -S "${missing_deps[@]}"
                    if command -v mpvpaper &>/dev/null && command -v ffmpeg &>/dev/null; then
                        notify-send 'Wallpaper switcher' 'Alright, try again!' -a "Wallpaper switcher"
                    fi
                fi
                exit 0
            fi

            [[ -z "$no_wallpaper_update" ]] && set_wallpaper_path "$imgpath"

            local video_path="$imgpath" monitor
            # Per-video user crop. Translate the QML adjuster's
            # (scale, offsetX, offsetY) to mpv options:
            #   * video-zoom = log2(scale)            (mpv zoom is log-scale)
            #   * video-align-x = -offsetX            (range -1..1, picks where
            #   * video-align-y = -offsetY             in the panscan/zoom
            #                                          overflow to show)
            # video-align is the right knob here (not video-pan-*) because
            # at scale=1 the panscan=1.0 default already creates overflow on
            # the long axis — align positions within that overflow without
            # needing to know the aspect mismatch. Sign flip: our offset
            # convention is "+1 → user dragged image right → see LEFT half",
            # which is mpv's align-x = -1 (left-aligned).
            local crop_zoom=0 crop_align_x=0 crop_align_y=0
            local cfg="$XDG_CONFIG_HOME/illogical-impulse/config.json"
            [ -z "$XDG_CONFIG_HOME" ] && cfg="$HOME/.config/illogical-impulse/config.json"
            if [ -f "$cfg" ] && command -v jq >/dev/null; then
                local entry
                entry=$(jq -r --arg p "$video_path" '.background.crop.perFile // "{}" | fromjson | .[$p] // empty' "$cfg" 2>/dev/null)
                if [ -n "$entry" ]; then
                    local _s _ox _oy
                    _s=$(echo "$entry"  | jq -r '.scale   // 1')
                    _ox=$(echo "$entry" | jq -r '.offsetX // 0')
                    _oy=$(echo "$entry" | jq -r '.offsetY // 0')
                    crop_zoom=$(awk -v s="$_s"  'BEGIN { if (s <= 0) s = 1; printf "%.4f", log(s)/log(2) }')
                    crop_align_x=$(awk -v o="$_ox" 'BEGIN { v = -o; if (v < -1) v = -1; if (v > 1) v = 1; printf "%.4f", v }')
                    crop_align_y=$(awk -v o="$_oy" 'BEGIN { v = -o; if (v < -1) v = -1; if (v > 1) v = 1; printf "%.4f", v }')
                fi
            fi
            # Default VIDEO_OPTS has video-align-x/y=0.5 baked in — override
            # by appending so the user's crop wins.
            local VIDEO_OPTS_CROP="$VIDEO_OPTS video-zoom=$crop_zoom video-align-x=$crop_align_x video-align-y=$crop_align_y"
            while IFS= read -r monitor; do
                # setsid: detach mpvpaper into its own session so it outlives
                # switchwall.sh. Without it, Quickshell reaps switchwall and
                # kills the whole process group — mpvpaper dies and the video
                # wallpaper vanishes the moment the apply finishes.
                setsid mpvpaper -o "$VIDEO_OPTS_CROP" "$monitor" "$video_path" >/dev/null 2>&1 &
                sleep 0.1
            done < <(hyprctl monitors -j | jq -r '.[] | .name')

            local thumbnail="$THUMBNAIL_DIR/$(basename "$imgpath").jpg"
            ffmpeg -y -i "$imgpath" -vframes 1 "$thumbnail" 2>/dev/null

            set_thumbnail_path "$thumbnail"

            if [ -f "$thumbnail" ]; then
                matugen_args=(image "$thumbnail")
                generate_colors_material_args=(--path "$thumbnail")
                create_restore_script "$video_path"
            else
                echo "Cannot create image to colorgen"
                remove_restore
                exit 1
            fi
        else
            matugen_args=(image "$imgpath")
            generate_colors_material_args=(--path "$imgpath")
            [[ -z "$no_wallpaper_update" ]] && set_wallpaper_path "$imgpath"
            remove_restore
        fi
    fi

    if [[ -z "$mode_flag" ]]; then
        local current_mode
        current_mode=$(gsettings get org.gnome.desktop.interface color-scheme 2>/dev/null | tr -d "'")
        if [[ "$current_mode" == "prefer-dark" ]]; then
            mode_flag="dark"
        else
            mode_flag="light"
        fi
    fi

    if [[ -n "$mode_flag" ]]; then
        matugen_args+=(--mode "$mode_flag")
        if [[ $(jq -r '.appearance.wallpaperTheming.terminalGenerationProps.forceDarkMode' "$SHELL_CONFIG_FILE") == "true" ]]; then
            generate_colors_material_args+=(--mode "dark")
        else
            generate_colors_material_args+=(--mode "$mode_flag")
        fi
    fi
    [[ -n "$type_flag" ]] && matugen_args+=(--type "$type_flag") && generate_colors_material_args+=(--scheme "$type_flag")
    # Non-interactive: pick most vibrant color when matugen finds multiple candidates
    matugen_args+=(--prefer saturation)
    generate_colors_material_args+=(--termscheme "$terminalscheme" --blend_bg_fg)
    generate_colors_material_args+=(--cache "$STATE_DIR/user/generated/color.txt")

    pre_process "$mode_flag"

    if [ -f "$SHELL_CONFIG_FILE" ]; then
        local enable_apps_shell
        enable_apps_shell=$(jq -r '.appearance.wallpaperTheming.enableAppsAndShell' "$SHELL_CONFIG_FILE")
        if [ "$enable_apps_shell" == "false" ]; then
            echo "App and shell theming disabled, skipping matugen and color generation"
            return
        fi
    fi

    if [ -f "$SHELL_CONFIG_FILE" ]; then
        local harmony harmonize_threshold term_fg_boost
        harmony=$(jq -r '.appearance.wallpaperTheming.terminalGenerationProps.harmony' "$SHELL_CONFIG_FILE")
        harmonize_threshold=$(jq -r '.appearance.wallpaperTheming.terminalGenerationProps.harmonizeThreshold' "$SHELL_CONFIG_FILE")
        term_fg_boost=$(jq -r '.appearance.wallpaperTheming.terminalGenerationProps.termFgBoost' "$SHELL_CONFIG_FILE")
        [[ "$harmony" != "null" && -n "$harmony" ]] && generate_colors_material_args+=(--harmony "$harmony")
        [[ "$harmonize_threshold" != "null" && -n "$harmonize_threshold" ]] && generate_colors_material_args+=(--harmonize_threshold "$harmonize_threshold")
        [[ "$term_fg_boost" != "null" && -n "$term_fg_boost" ]] && generate_colors_material_args+=(--term_fg_boost "$term_fg_boost")
    fi

    # ALWAYS use temporary outputs to avoid default/raw colors flashing
    local temp_config="/tmp/matugen-temp-config.toml"
    cat > "$temp_config" <<EOF
[config]
version_check = false

[templates.m3colors]
input_path = '$HOME/.config/matugen/templates/colors.json'
output_path = '/tmp/matugen-temp-colors.json'
EOF

    # Clean up any stale temp files
    rm -f /tmp/matugen-temp-colors.json /tmp/matugen-temp-material_colors.scss

    matugen -c "$temp_config" "${matugen_args[@]}"
    rm -f "$temp_config"

    source "$(eval echo "$ILLOGICAL_IMPULSE_VIRTUAL_ENV")/bin/activate"
    python3 "$SCRIPT_DIR/generate_colors_material.py" "${generate_colors_material_args[@]}" \
        > /tmp/matugen-temp-material_colors.scss

    if [[ -n "$theory_flag$style_flag$practical_flag$remap_flag" ]]; then
        python3 "$SCRIPT_DIR/palette_transform.py" \
            --theory    "$theory_flag" \
            --style     "$style_flag" \
            --practical "$practical_flag" \
            --remap     "$remap_flag" \
            --mix-order "$mix_order_flag" \
            --json /tmp/matugen-temp-colors.json \
            --scss /tmp/matugen-temp-material_colors.scss \
            2>/dev/null || true
    fi

    # Run applycolor.sh using the temporary files.
    # This will generate terminal sequences, broadcast gsettings theme mode,
    # and run rebuild_templates.py to rewrite all other config files (GTK, Hyprland, etc.)
    # BEFORE colors.json is placed in its final location.
    "$SCRIPT_DIR"/applycolor.sh /tmp/matugen-temp-material_colors.scss /tmp/matugen-temp-colors.json

    # Atomically move the files to their final positions to trigger the Quickshell UI reload
    [[ -f /tmp/matugen-temp-colors.json ]] && mv /tmp/matugen-temp-colors.json "$STATE_DIR/user/generated/colors.json"
    [[ -f /tmp/matugen-temp-material_colors.scss ]] && mv /tmp/matugen-temp-material_colors.scss "$STATE_DIR/user/generated/material_colors.scss"

    deactivate

    # Tell Quickshell to re-read colors.json (handles atomic-write inotify miss)
    qs -c ii msg materialTheme reload 2>/dev/null || true

    local max_width_desired max_height_desired
    max_width_desired="$(hyprctl monitors -j | jq '([.[].width] | min)' | xargs)"
    max_height_desired="$(hyprctl monitors -j | jq '([.[].height] | min)' | xargs)"
    post_process "$max_width_desired" "$max_height_desired" "$imgpath"
}

main() {
    local imgpath="" mode_flag="" type_flag="" color_flag="" color=""
    local noswitch_flag=""
    local theory_flag="" style_flag="" practical_flag="" remap_flag="" mix_order_flag=""
    local no_wallpaper_update=""
    local _reddit_sub="" _reddit_sort="" _reddit_ratio="" _reddit_media=""
    local _wallhaven_purity="" _wallhaven_ratio=""

    # --select state
    local select_flag="" select_source="local" select_dir=""
    local select_reddit_sub="wallpapers" select_reddit_sort="hot"
    local select_wallhaven_query="" select_wallhaven_purity="100"
    local select_wallhaven_ratio="" select_wallhaven_sorting="relevance"

    get_type_from_config() {
        jq -r '.appearance.palette.type' "$SHELL_CONFIG_FILE" 2>/dev/null || echo "auto"
    }
    get_accent_color_from_config() {
        jq -r '.appearance.palette.accentColor' "$SHELL_CONFIG_FILE" 2>/dev/null || echo ""
    }
    set_accent_color() {
        local c="$1"
        jq --arg color "$c" '.appearance.palette.accentColor = $color' "$SHELL_CONFIG_FILE" > "$SHELL_CONFIG_FILE.tmp" && mv "$SHELL_CONFIG_FILE.tmp" "$SHELL_CONFIG_FILE"
    }
    detect_scheme_type_from_image() {
        local img="$1"
        source "$(eval echo "$ILLOGICAL_IMPULSE_VIRTUAL_ENV")/bin/activate"
        "$SCRIPT_DIR"/scheme_for_image.py "$img" 2>/dev/null | tr -d '\n'
        deactivate
    }

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --mode)   mode_flag="$2"; shift 2 ;;
            --type)   type_flag="$2"; shift 2 ;;
            --no-wallpaper-update)
                no_wallpaper_update="1"; shift ;;
            --theory)    theory_flag="$2";    shift 2 ;;
            --style)     style_flag="$2";     shift 2 ;;
            --practical) practical_flag="$2"; shift 2 ;;
            --remap)     remap_flag="$2";     shift 2 ;;
            --mix-order) mix_order_flag="$2"; shift 2 ;;
            --color)
                if [[ "$2" =~ ^#?[A-Fa-f0-9]{6}$ ]]; then
                    set_accent_color "$2"; shift 2
                elif [[ "$2" == "clear" ]]; then
                    set_accent_color ""; shift 2
                else
                    set_accent_color "$(hyprpicker --no-fancy)"; shift
                fi
                ;;
            --image)
                imgpath="$2"; shift 2
                ;;
            --noswitch)
                noswitch_flag="1"
                imgpath=$(jq -r '.background.wallpaperPath' "$SHELL_CONFIG_FILE" 2>/dev/null || echo "")
                shift
                ;;
            --select)
                select_flag="1"; shift
                while [[ $# -gt 0 ]]; do
                    case "$1" in
                        --dir)
                            select_source="local"
                            select_dir="$2"; shift 2
                            ;;
                        --reddit)
                            select_source="reddit"; shift
                            [[ -n "${1:-}" && "${1:-}" != --* ]] && { select_reddit_sub="$1"; shift; }
                            [[ -n "${1:-}" && "${1:-}" != --* ]] && { select_reddit_sort="$1"; shift; }
                            ;;
                        --wallhaven)
                            select_source="wallhaven"; shift
                            [[ -n "${1:-}" && "${1:-}" != --* ]] && { select_wallhaven_query="$1"; shift; }
                            ;;
                        --wallhaven-purity)
                            select_wallhaven_purity="$2"; shift 2 ;;
                        --wallhaven-ratio)
                            select_wallhaven_ratio="$2"; shift 2 ;;
                        --wallhaven-sorting)
                            select_wallhaven_sorting="$2"; shift 2 ;;
                        *) break ;;
                    esac
                done
                ;;
            --select-internal)
                select_flag="1"
                select_source="${2:-local}"
                select_dir="${3:-}"
                select_reddit_sub="${4:-wallpapers}"
                select_reddit_sort="${5:-hot}"
                select_wallhaven_query="${6:-}"
                select_wallhaven_purity="${7:-100}"
                select_wallhaven_ratio="${8:-}"
                select_wallhaven_sorting="${9:-relevance}"
                shift 9 || shift $#
                ;;
            --reddit-wallpapers|--reddit-nsfw)
                imgpath="$1"; shift
                [[ -n "${1:-}" && "${1:-}" != --* ]] && { _reddit_sub="$1"; shift; }
                [[ -n "${1:-}" && "${1:-}" != --* ]] && { _reddit_sort="$1"; shift; }
                _reddit_ratio="${1:-}"
                [[ "$_reddit_ratio" == "-" || -z "$_reddit_ratio" || "$_reddit_ratio" == --* ]] && _reddit_ratio="" || shift
                [[ -n "${1:-}" && "${1:-}" != --* ]] && { _reddit_media="$1"; shift; }
                ;;
            --wallhaven)
                imgpath="$1"; shift
                [[ -n "${1:-}" && "${1:-}" != --* ]] && { _wallhaven_purity="$1"; shift; }
                [[ -n "${1:-}" && "${1:-}" != --* ]] && { _wallhaven_ratio="$1"; shift; }
                ;;
            --cleanup|--prune-history)
                cleanup_history "${2:-90}"
                shift; [[ "${1:-}" =~ ^[0-9]+$ ]] && shift
                exit 0
                ;;
            *)
                [[ -z "$imgpath" ]] && imgpath="$1"
                shift
                ;;
        esac
    done

    # ── Handle --select ───────────────────────────────────────────────────────
    if [[ -n "$select_flag" ]]; then
        local picker_result
        picker_result="$(select_wallpaper \
            "$select_source" \
            "$select_dir" \
            "$select_reddit_sub" \
            "$select_reddit_sort" \
            "$select_wallhaven_query" \
            "$select_wallhaven_purity" \
            "$select_wallhaven_ratio" \
            "$select_wallhaven_sorting")"

        if [[ "$picker_result" != __SELECTED__* ]]; then
            echo "[select] No selection made, exiting." >&2
            exit 0
        fi

        local _inner="${picker_result#__SELECTED__}"
        imgpath="${_inner%%__MODE__*}"
        local _picked_mode="${_inner##*__MODE__}"
        [[ -n "$_picked_mode" && -z "$mode_flag" ]] && mode_flag="$_picked_mode"

        if [[ -z "$imgpath" || ! -f "$imgpath" ]]; then
            echo "[select] Invalid path: $imgpath" >&2
            exit 1
        fi

        case "$select_source" in
            reddit)    cp "$imgpath" "$HOME/Pictures/Reddit_${select_reddit_sub}_$(basename "$imgpath")" 2>/dev/null || true ;;
            wallhaven) cp "$imgpath" "$HOME/Pictures/Wallhaven_$(basename "$imgpath")"                   2>/dev/null || true ;;
        esac
    fi

    # ── Accent colour from config ─────────────────────────────────────────────
    # Only fall back to the accent color if NO image was passed. An explicit
    # --image (or --noswitch / --select / --reddit / etc. that resolved an
    # imgpath) must take priority — otherwise every apply call would skip the
    # image branch (and skip set_wallpaper_path), leaving the displayed
    # wallpaper stuck on whatever was there before.
    if [[ -z "$imgpath" ]]; then
        local config_color
        config_color="$(get_accent_color_from_config)"
        if [[ "$config_color" =~ ^#?[A-Fa-f0-9]{6}$ ]]; then
            color_flag="1"
            color="$config_color"
        fi
    fi

    # ── Palette type ──────────────────────────────────────────────────────────
    [[ -z "$type_flag" ]] && type_flag="$(get_type_from_config)"

    local allowed_types=(scheme-content scheme-expressive scheme-fidelity scheme-fruit-salad scheme-monochrome scheme-neutral scheme-rainbow scheme-tonal-spot auto)
    local valid_type=0
    for t in "${allowed_types[@]}"; do
        [[ "$type_flag" == "$t" ]] && { valid_type=1; break; }
    done
    if [[ $valid_type -eq 0 ]]; then
        echo "[switchwall.sh] Warning: Invalid type '$type_flag', defaulting to 'auto'" >&2
        type_flag="auto"
    fi

    # ── Fallback to kdialog if nothing specified ──────────────────────────────
    if [[ -z "$imgpath" && -z "$color_flag" && -z "$noswitch_flag" ]]; then
        cd "$(xdg-user-dir PICTURES)/Wallpapers/showcase" 2>/dev/null \
            || cd "$(xdg-user-dir PICTURES)/Wallpapers" 2>/dev/null \
            || cd "$(xdg-user-dir PICTURES)" || return 1
        imgpath="$(kdialog --getopenfilename . --title 'Choose wallpaper')"
    fi

    # ── Auto-detect scheme type ───────────────────────────────────────────────
    if [[ "$type_flag" == "auto" ]]; then
        if [[ -n "$imgpath" && -f "$imgpath" ]]; then
            local detected_type valid_detected=0
            detected_type="$(detect_scheme_type_from_image "$imgpath")"
            for t in "${allowed_types[@]}"; do
                [[ "$detected_type" == "$t" && "$detected_type" != "auto" ]] && { valid_detected=1; break; }
            done
            if [[ $valid_detected -eq 1 ]]; then
                type_flag="$detected_type"
            else
                echo "[switchwall] Warning: Could not auto-detect a valid scheme, defaulting to 'scheme-tonal-spot'" >&2
                type_flag="scheme-tonal-spot"
            fi
        else
            echo "[switchwall] Warning: No image to auto-detect scheme from, defaulting to 'scheme-tonal-spot'" >&2
            type_flag="scheme-tonal-spot"
        fi
    fi

    switch "$imgpath" "$mode_flag" "$type_flag" "$color_flag" "$color" \
        "$_reddit_sub" "$_reddit_sort" "$_reddit_ratio" "$_reddit_media" \
        "$_wallhaven_purity" "$_wallhaven_ratio"
}

main "$@"

# GREETER-SYNC : keep /var/cache/greeter/wallpaper.* in sync with the session
if [ -w /var/cache/greeter ]; then
    _gs_cfg="$XDG_CONFIG_HOME/illogical-impulse/config.json"
    [ -z "$XDG_CONFIG_HOME" ] && _gs_cfg="$HOME/.config/illogical-impulse/config.json"
    if [ -f "$_gs_cfg" ] && command -v jq >/dev/null; then
        _gs_wp=$(jq -r '.background.wallpaperSourcePath // .background.wallpaperPath // empty' "$_gs_cfg" 2>/dev/null)
        if [ -n "$_gs_wp" ] && [ -f "$_gs_wp" ]; then
            rm -f /var/cache/greeter/wallpaper.jpg /var/cache/greeter/wallpaper.png 2>/dev/null
            case "${_gs_wp,,}" in
                *.jpg|*.jpeg) cp "$_gs_wp" /var/cache/greeter/wallpaper.jpg 2>/dev/null ;;
                *.png)        cp "$_gs_wp" /var/cache/greeter/wallpaper.png 2>/dev/null ;;
            esac
        fi
    fi
fi
