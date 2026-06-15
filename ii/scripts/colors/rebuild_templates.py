#!/usr/bin/env python3
import json
import sys
import subprocess
from pathlib import Path

def hex_to_rgb_str(h):
    h = h.lstrip("#")
    if len(h) == 8: h = h[:6]
    r = int(h[0:2], 16)
    g = int(h[2:4], 16)
    b = int(h[4:6], 16)
    return f"{r}, {g}, {b}"

def hex_to_rgba_str(h):
    h = h.lstrip("#")
    if len(h) == 8: h = h[:6]
    r = int(h[0:2], 16)
    g = int(h[2:4], 16)
    b = int(h[4:6], 16)
    return f"{r}, {g}, {b}, 255"

def main():
    state_dir = Path.home() / ".local/state/quickshell"
    if len(sys.argv) > 1:
        colors_json_path = Path(sys.argv[1])
    else:
        colors_json_path = state_dir / "user/generated/colors.json"
    
    if not colors_json_path.exists():
        print(f"Error: {colors_json_path} does not exist.")
        return 1
        
    try:
        with open(colors_json_path) as f:
            colors = json.load(f)
    except Exception as e:
        print(f"Error loading colors.json: {e}")
        return 1
        
    # Construct the nested structure that matugen template variables expect
    nested = {
        "colors": {}
    }
    
    # Read active wallpaper path if it exists to satisfy templates using {{image}}
    wallpaper_path = ""
    wallpaper_txt_path = state_dir / "user/generated/wallpaper/path.txt"
    if wallpaper_txt_path.exists():
        try:
            wallpaper_path = wallpaper_txt_path.read_text().strip()
        except Exception as e:
            print(f"Warning: could not read wallpaper path: {e}")
            
    if wallpaper_path:
        nested["image"] = wallpaper_path
    else:
        nested["image"] = ""
    
    # Synthesize source_color if missing to prevent template resolution failures
    if "source_color" not in colors:
        if "primary" in colors:
            colors["source_color"] = colors["primary"]
        else:
            for k, v in colors.items():
                if isinstance(v, str) and v.startswith("#"):
                    colors["source_color"] = v
                    break
                    
    if "source_color" in colors:
        nested["source_color"] = colors["source_color"]
    
    # Detect the current color scheme mode (prefer-light or prefer-dark)
    is_dark = True
    try:
        mode_out = subprocess.check_output(
            ["gsettings", "get", "org.gnome.desktop.interface", "color-scheme"],
            text=True
        ).strip().strip("'")
        is_dark = "light" not in mode_out.lower()
    except Exception:
        pass

    # Run matugen color to generate light/dark palettes
    source_col = colors.get("source_color", colors.get("primary", "#bac2de"))
    generated_colors = {}
    try:
        matugen_out = subprocess.check_output(
            ["matugen", "color", "hex", source_col, "-j", "hex"],
            text=True
        )
        matugen_data = json.loads(matugen_out)
        generated_colors = matugen_data.get("colors", {})
    except Exception as e:
        print(f"Warning: could not run matugen to generate opposite colors: {e}")

    for key, val in colors.items():
        if isinstance(val, str) and val.startswith("#"):
            color_data_active = {
                "hex": val,
                "hex_stripped": val.lstrip("#"),
                "rgb": hex_to_rgb_str(val),
                "rgba": hex_to_rgba_str(val)
            }
            
            # Synthesize the opposite mode color
            opp_mode = "light" if is_dark else "dark"
            opp_hex = val # fallback
            if key in generated_colors:
                opp_color_obj = generated_colors[key].get(opp_mode, {})
                if "color" in opp_color_obj:
                    opp_hex = opp_color_obj["color"]
            
            color_data_opposite = {
                "hex": opp_hex,
                "hex_stripped": opp_hex.lstrip("#"),
                "rgb": hex_to_rgb_str(opp_hex),
                "rgba": hex_to_rgba_str(opp_hex)
            }
            
            if is_dark:
                nested["colors"][key] = {
                    "default": color_data_active,
                    "dark": color_data_active,
                    "light": color_data_opposite
                }
            else:
                nested["colors"][key] = {
                    "default": color_data_active,
                    "light": color_data_active,
                    "dark": color_data_opposite
                }
            
    # Write to a temporary file
    temp_json_path = Path("/tmp/matugen_nested_colors.json")
    with open(temp_json_path, "w") as f:
        json.dump(nested, f, indent=2)
        
    print(f"Generated nested colors JSON at {temp_json_path}")
    
def hex_to_ansi256_exact(hex_str):
    hex_str = hex_str.lstrip('#')
    r = int(hex_str[0:2], 16)
    g = int(hex_str[2:4], 16)
    b = int(hex_str[4:6], 16)
    
    # 16 standard colors (approximations)
    standard_rgbs = [
        (0, 0, 0),       # 0
        (128, 0, 0),     # 1
        (0, 128, 0),     # 2
        (128, 128, 0),   # 3
        (0, 0, 128),     # 4
        (128, 0, 128),   # 5
        (0, 128, 128),   # 6
        (192, 192, 192), # 7
        (128, 128, 128), # 8
        (255, 0, 0),     # 9
        (0, 255, 0),     # 10
        (255, 255, 0),   # 11
        (0, 0, 255),     # 12
        (255, 0, 255),   # 13
        (0, 255, 255),   # 14
        (255, 255, 255)  # 15
    ]
    
    best_color = 0
    min_dist = 3 * 255 * 255
    
    # Check standard colors
    for i, rgb in enumerate(standard_rgbs):
        dist = (r - rgb[0])**2 + (g - rgb[1])**2 + (b - rgb[2])**2
        if dist < min_dist:
            min_dist = dist
            best_color = i
            
    # Check 6x6x6 color cube
    cube_levels = [0, 95, 135, 175, 215, 255]
    for r_idx in range(6):
        for g_idx in range(6):
            for b_idx in range(6):
                cr = cube_levels[r_idx]
                cg = cube_levels[g_idx]
                cb = cube_levels[b_idx]
                dist = (r - cr)**2 + (g - cg)**2 + (b - cb)**2
                color_num = 16 + 36 * r_idx + 6 * g_idx + b_idx
                if dist < min_dist:
                    min_dist = dist
                    best_color = color_num
                    
    # Check grayscale ramp
    for i in range(24):
        val = 8 + i * 10
        dist = (r - val)**2 + (g - val)**2 + (b - val)**2
        color_num = 232 + i
        if dist < min_dist:
            min_dist = dist
            best_color = color_num
            
    return best_color

def rebuild_cmus_theme(colors):
    # Map necessary colors
    on_surface = hex_to_ansi256_exact(colors.get("on_surface", "#e6e1e1"))
    tertiary = hex_to_ansi256_exact(colors.get("tertiary", "#8D76AD"))
    primary = hex_to_ansi256_exact(colors.get("primary", "#B52755"))
    on_primary = hex_to_ansi256_exact(colors.get("on_primary", "#ffffff"))
    surface_container_highest = hex_to_ansi256_exact(colors.get("surface_container_highest", "#4d4b4d"))
    secondary = hex_to_ansi256_exact(colors.get("secondary", "#A97363"))
    surface_container = hex_to_ansi256_exact(colors.get("surface_container", "#201f20"))
    surface = hex_to_ansi256_exact(colors.get("surface", "#141313"))
    error = hex_to_ansi256_exact(colors.get("error", "#ffb4ab"))
    surface_variant = hex_to_ansi256_exact(colors.get("surface_variant", "#49464a"))

    theme_content = f"""# Matugen-generated theme for cmus
# Matches the active system wallpaper palette (256-color compatible)

# Background and text colors
set color_win_bg=default
set color_win_fg={on_surface}

# Directory and Category headers (views 1 and 2)
set color_win_dir={tertiary}

# Selected row (focused window)
set color_win_sel_bg={primary}
set color_win_sel_fg={on_primary}

# Selected row (unfocused window)
set color_win_inactive_sel_bg={surface_container_highest}
set color_win_inactive_sel_fg={on_surface}

# Currently playing track (unselected)
set color_win_cur={secondary}

# Currently playing track (selected)
set color_win_cur_sel_bg={primary}
set color_win_cur_sel_fg={on_primary}

# Inactive currently playing track (selected)
set color_win_inactive_cur_sel_bg={surface_container_highest}
set color_win_inactive_cur_sel_fg={secondary}

# Title line at the top
set color_titleline_bg={surface_container}
set color_titleline_fg={primary}

# Status line at the bottom
set color_statusline_bg={surface_container}
set color_statusline_fg={secondary}

# Command line / search input at the very bottom
set color_cmdline_bg={surface}
set color_cmdline_fg={on_surface}

# Warnings and errors
set color_error={error}
set color_info={secondary}

# Separator lines
set color_separator={surface_variant}
"""
    cmus_theme_path = Path.home() / ".config/cmus/rose-terracotta.theme"
    cmus_theme_path.parent.mkdir(parents=True, exist_ok=True)
    cmus_theme_path.write_text(theme_content)
    
    # Reload cmus-remote
    subprocess.run("timeout 1s cmus-remote -C 'colorscheme rose-terracotta' 2>/dev/null || true", shell=True)

def main():
    state_dir = Path.home() / ".local/state/quickshell"
    if len(sys.argv) > 1:
        colors_json_path = Path(sys.argv[1])
    else:
        colors_json_path = state_dir / "user/generated/colors.json"
    
    if not colors_json_path.exists():
        print(f"Error: {colors_json_path} does not exist.")
        return 1
        
    try:
        with open(colors_json_path) as f:
            colors = json.load(f)
    except Exception as e:
        print(f"Error loading colors.json: {e}")
        return 1
        
    # Construct the nested structure that matugen template variables expect
    nested = {
        "colors": {}
    }
    
    # Read active wallpaper path if it exists to satisfy templates using {{image}}
    wallpaper_path = ""
    wallpaper_txt_path = state_dir / "user/generated/wallpaper/path.txt"
    if wallpaper_txt_path.exists():
        try:
            wallpaper_path = wallpaper_txt_path.read_text().strip()
        except Exception as e:
            print(f"Warning: could not read wallpaper path: {e}")
            
    if wallpaper_path:
        nested["image"] = wallpaper_path
    else:
        nested["image"] = ""
    
    # Synthesize source_color if missing to prevent template resolution failures
    if "source_color" not in colors:
        if "primary" in colors:
            colors["source_color"] = colors["primary"]
        else:
            for k, v in colors.items():
                if isinstance(v, str) and v.startswith("#"):
                    colors["source_color"] = v
                    break
                    
    if "source_color" in colors:
        nested["source_color"] = colors["source_color"]
    
    # Detect the current color scheme mode (prefer-light or prefer-dark)
    is_dark = True
    try:
        mode_out = subprocess.check_output(
            ["gsettings", "get", "org.gnome.desktop.interface", "color-scheme"],
            text=True
        ).strip().strip("'")
        is_dark = "light" not in mode_out.lower()
    except Exception:
        pass

    # Run matugen color to generate light/dark palettes
    source_col = colors.get("source_color", colors.get("primary", "#bac2de"))
    generated_colors = {}
    try:
        matugen_out = subprocess.check_output(
            ["matugen", "color", "hex", source_col, "-j", "hex"],
            text=True
        )
        matugen_data = json.loads(matugen_out)
        generated_colors = matugen_data.get("colors", {})
    except Exception as e:
        print(f"Warning: could not run matugen to generate opposite colors: {e}")

    for key, val in colors.items():
        if isinstance(val, str) and val.startswith("#"):
            color_data_active = {
                "hex": val,
                "hex_stripped": val.lstrip("#"),
                "rgb": hex_to_rgb_str(val),
                "rgba": hex_to_rgba_str(val)
            }
            
            # Synthesize the opposite mode color
            opp_mode = "light" if is_dark else "dark"
            opp_hex = val # fallback
            if key in generated_colors:
                opp_color_obj = generated_colors[key].get(opp_mode, {})
                if "color" in opp_color_obj:
                    opp_hex = opp_color_obj["color"]
            
            color_data_opposite = {
                "hex": opp_hex,
                "hex_stripped": opp_hex.lstrip("#"),
                "rgb": hex_to_rgb_str(opp_hex),
                "rgba": hex_to_rgba_str(opp_hex)
            }
            
            if is_dark:
                nested["colors"][key] = {
                    "default": color_data_active,
                    "dark": color_data_active,
                    "light": color_data_opposite
                }
            else:
                nested["colors"][key] = {
                    "default": color_data_active,
                    "light": color_data_active,
                    "dark": color_data_opposite
                }
            
    # Write to a temporary file
    temp_json_path = Path("/tmp/matugen_nested_colors.json")
    with open(temp_json_path, "w") as f:
        json.dump(nested, f, indent=2)
        
    print(f"Generated nested colors JSON at {temp_json_path}")
    
    # Run matugen json using the temporary file to regenerate all templates
    try:
        res = subprocess.run(
            ["matugen", "json", str(temp_json_path)],
            capture_output=True,
            text=True,
            check=True
        )
        print("Successfully rebuilt all matugen templates!")
        print(res.stdout)
    except subprocess.CalledProcessError as e:
        print("Failed to run matugen json:")
        print(e.stderr)
        print(e.stdout)
        return 1
        
    # Clean up
    if temp_json_path.exists():
        temp_json_path.unlink()
        
    # Rebuild cmus theme (256 color compatible)
    try:
        rebuild_cmus_theme(colors)
        print("Successfully rebuilt cmus 256 theme!")
    except Exception as e:
        print(f"Warning: could not rebuild cmus theme: {e}")
        
    return 0

if __name__ == "__main__":
    sys.exit(main())
