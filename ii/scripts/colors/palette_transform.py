#!/usr/bin/env python3
# Transforms a generated palette in-place: applies a Color Theory rotation
# (mono / analogous / complementary / triadic / split-comp / tetradic),
# a Style HSL filter (pastel / muted / bright / colorful / material), and
# a Practical pass (high-contrast / duotone). Operates on:
#   - matugen's colors.json (snake_case keys, JSON)
#   - generate_colors_material.py's material_colors.scss ("$key: #hex;" lines)
#
# Usage:
#   palette_transform.py [--theory NAME] [--style NAME] [--practical NAME]
#                        [--json /path/colors.json] [--scss /path/material_colors.scss]
#
# All transforms are no-ops when the corresponding flag is empty / "material" / "none".

import argparse, colorsys, json, re, sys
from pathlib import Path

# Which keys are "accent" colors we rotate per group.
# Keys are normalized: lowercased, snake_case (so SCSS "primaryContainer" -> "primary_container").
GROUP_PRIMARY   = ("primary",   "inverse_primary")
GROUP_SECONDARY = ("secondary",)
GROUP_TERTIARY  = ("tertiary",)
ACCENT_GROUPS = {
    "primary":   GROUP_PRIMARY,
    "secondary": GROUP_SECONDARY,
    "tertiary":  GROUP_TERTIARY,
}

# A key belongs to a group if it starts with that group root (after camel→snake).
def classify(key_snake):
    for group, roots in ACCENT_GROUPS.items():
        for r in roots:
            if key_snake == r or key_snake.startswith(r):
                return group
    return None

def camel_to_snake(s):
    return re.sub(r"(?<!^)(?=[A-Z])", "_", s).lower()

def hex_to_rgb(h):
    h = h.lstrip("#")
    if len(h) == 8: h = h[:6]   # drop alpha
    return tuple(int(h[i:i+2], 16) / 255.0 for i in (0, 2, 4))

def rgb_to_hex(r, g, b):
    clamp = lambda x: max(0, min(255, round(x * 255)))
    return "#{:02x}{:02x}{:02x}".format(clamp(r), clamp(g), clamp(b))

def shift_hue(hex_in, deg):
    r, g, b = hex_to_rgb(hex_in)
    h, l, s = colorsys.rgb_to_hls(r, g, b)
    h = (h + (deg / 360.0)) % 1.0
    return rgb_to_hex(*colorsys.hls_to_rgb(h, l, s))

def set_hue(hex_in, h_target):
    r, g, b = hex_to_rgb(hex_in)
    _, l, s = colorsys.rgb_to_hls(r, g, b)
    return rgb_to_hex(*colorsys.hls_to_rgb(h_target, l, s))

def style_filter(hex_in, style):
    if not style or style == "material":
        return hex_in
    r, g, b = hex_to_rgb(hex_in)
    h, l, s = colorsys.rgb_to_hls(r, g, b)
    if style == "pastel":
        s = min(s, 0.45)
        # Lift mid-tones, leave very dark/bright alone so onPrimary stays readable
        if 0.25 < l < 0.75:
            l = l * 0.5 + 0.5 * 0.78
    elif style == "muted":
        s = min(s, 0.35)
    elif style == "bright":
        s = max(s, min(1.0, s * 1.5 + 0.2))
    elif style == "colorful":
        s = min(1.0, s * 1.25 + 0.15)
    return rgb_to_hex(*colorsys.hls_to_rgb(h, l, s))

def practical_filter(hex_in, key_group, key_snake, mode, primary_hue):
    if not mode or mode == "none":
        return hex_in
    r, g, b = hex_to_rgb(hex_in)
    h, l, s = colorsys.rgb_to_hls(r, g, b)
    if mode == "high_contrast":
        # Boost saturation; push lightness toward extremes for "on_*" keys.
        s = min(1.0, s * 1.2 + 0.05)
        if key_snake.startswith("on_"):
            l = 0.05 if l < 0.5 else 0.96
        else:
            # Pull mid-tones outward by ~10%
            l = max(0, l - 0.05) if l < 0.5 else min(1, l + 0.05)
    elif mode == "duotone":
        # Collapse tertiary onto primary's complementary hue.
        if key_group == "tertiary":
            h = (primary_hue + 0.5) % 1.0
    return rgb_to_hex(*colorsys.hls_to_rgb(h, l, s))

# Color-theory mapping: returns hue delta (degrees) per group, OR a callable
# that returns the new hex from (orig_hex, primary_hue).
def theory_deltas(theory):
    if not theory or theory == "material":
        return None
    table = {
        "mono":             {"primary": 0,   "secondary": 0,   "tertiary": 0},
        "analogous":        {"primary": 0,   "secondary": 30,  "tertiary": -30},
        "complementary":    {"primary": 0,   "secondary": 180, "tertiary": 180},
        "triadic":          {"primary": 0,   "secondary": 120, "tertiary": 240},
        "split":            {"primary": 0,   "secondary": 150, "tertiary": 210},
        "tetradic":         {"primary": 0,   "secondary": 90,  "tertiary": 180},
    }
    return table.get(theory)

def load_palette_colors(palette_name):
    script_dir = Path(__file__).parent.resolve()
    palettes_file = script_dir / "palettes.json"
    if not palettes_file.exists():
        return None
    try:
        with open(palettes_file) as f:
            palettes = json.load(f)
        if palette_name in palettes:
            colors = []
            for h in palettes[palette_name]:
                colors.append((h, hex_to_rgb(h)))
            return colors
    except Exception:
        pass
    return None

def find_nearest_color(hex_in, palette_rgb_list):
    if not palette_rgb_list:
        return hex_in
    r, g, b = hex_to_rgb(hex_in)
    min_dist = float('inf')
    best_hex = hex_in
    for p_hex, (pr, pg, pb) in palette_rgb_list:
        rmean = (r + pr) / 2.0
        dr, dg, db = r - pr, g - pg, b - pb
        dist = (2.0 + rmean) * (dr**2) + 4.0 * (dg**2) + (3.0 - rmean) * (db**2)
        if dist < min_dist:
            min_dist = dist
            best_hex = p_hex
    return best_hex

# Apply transforms to one (key, hex) pair, returning the new hex.
# ── Pipeline steps ──────────────────────────────────────────────────────────
# Each step is (out_hex, ctx) -> out_hex. They are applied in an order the
# caller chooses (the WallTune "Active mix" chips are draggable, and their
# on-screen order is passed through as --mix-order). An inactive step (e.g.
# theory="" so deltas is None) is a no-op, so the full step list can always be
# passed and only the enabled chips actually change anything.
def _step_theory(out, ctx):
    deltas, group = ctx["deltas"], ctx["group"]
    if deltas is not None and group is not None:
        # mono special-case: collapse all accent hues onto the primary hue.
        # Detect by deltas pattern (all zero across primary/sec/tert).
        if all(deltas.get(g, 0) == 0 for g in ("primary", "secondary", "tertiary")):
            out = set_hue(out, ctx["primary_hue"])
        else:
            out = shift_hue(out, deltas.get(group, 0))
    return out

def _step_style(out, ctx):
    # Style applies to accents (group set), not bare on_* foregrounds.
    if ctx["group"] is not None:
        out = style_filter(out, ctx["style"])
    return out

def _step_practical(out, ctx):
    if ctx["group"] is not None or ctx["key_snake"].startswith("on_"):
        out = practical_filter(out, ctx["group"] or "", ctx["key_snake"],
                               ctx["practical"], ctx["primary_hue"])
    return out

def _step_remap(out, ctx):
    if ctx["remap_colors"]:
        out = find_nearest_color(out, ctx["remap_colors"])
    return out

STEP_FUNCS = {
    "theory":    _step_theory,
    "style":     _step_style,
    "practical": _step_practical,
    "remap":     _step_remap,
}
# Canonical order, used when --mix-order is absent (preserves old behaviour).
DEFAULT_ORDER = ["theory", "style", "practical", "remap"]

def transform_one(key_snake, hex_in, primary_hue, deltas, style, practical,
                  remap_colors=None, order=None):
    ctx = {
        "group":       classify(key_snake),
        "deltas":      deltas,
        "style":       style,
        "practical":   practical,
        "primary_hue": primary_hue,
        "remap_colors": remap_colors,
        "key_snake":   key_snake,
    }
    out = hex_in
    for step in (order or DEFAULT_ORDER):
        fn = STEP_FUNCS.get(step)
        if fn:
            out = fn(out, ctx)
    return out

# ── JSON file (matugen colors.json, snake_case keys) ────────────────────────
def transform_json_file(path, deltas, style, practical, remap_colors=None, order=None):
    p = Path(path)
    if not p.exists(): return False
    data = json.loads(p.read_text())
    if "primary" not in data: return False
    primary_h = colorsys.rgb_to_hls(*hex_to_rgb(data["primary"]))[0]
    out = {}
    for k, v in data.items():
        if isinstance(v, str) and v.startswith("#"):
            out[k] = transform_one(k, v, primary_h, deltas, style, practical, remap_colors, order)
        else:
            out[k] = v
    p.write_text(json.dumps(out, indent=2) + "\n")
    return True

# ── SCSS file ($key: #hex;) ─────────────────────────────────────────────────
SCSS_LINE = re.compile(r'^\$([A-Za-z_][A-Za-z0-9_]*)\s*:\s*(#[0-9A-Fa-f]{3,8})\s*;\s*$')
def transform_scss_file(path, deltas, style, practical, remap_colors=None, order=None):
    p = Path(path)
    if not p.exists(): return False
    lines = p.read_text().splitlines()
    # Find primary first
    primary_h = None
    for line in lines:
        m = SCSS_LINE.match(line)
        if m and camel_to_snake(m.group(1)) == "primary":
            primary_h = colorsys.rgb_to_hls(*hex_to_rgb(m.group(2)))[0]
            break
    if primary_h is None: return False
    new_lines = []
    for line in lines:
        m = SCSS_LINE.match(line)
        if m:
            key_snake = camel_to_snake(m.group(1))
            new_hex = transform_one(key_snake, m.group(2), primary_h, deltas, style, practical, remap_colors, order)
            new_lines.append(f"${m.group(1)}: {new_hex};")
        else:
            new_lines.append(line)
    p.write_text("\n".join(new_lines) + "\n")
    return True

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--theory",    default="")
    ap.add_argument("--style",     default="")
    ap.add_argument("--practical", default="")
    ap.add_argument("--remap",     default="")
    ap.add_argument("--json",      default="")
    ap.add_argument("--scss",      default="")
    # Comma-separated apply order for the transforms, e.g. "remap,theory,style".
    # Mirrors the on-screen order of the WallTune "Active mix" chips. Unknown or
    # missing entries fall back to the canonical order; omitted steps are simply
    # appended so behaviour is never silently dropped.
    ap.add_argument("--mix-order", default="")
    args = ap.parse_args()

    # Short-circuit: nothing to do
    if args.theory in ("", "material") and args.style in ("", "material") and args.practical in ("", "none") and not args.remap:
        return 0

    order = [s.strip() for s in args.mix_order.split(",") if s.strip() in STEP_FUNCS]
    # Append any canonical steps the caller omitted, keeping their relative order.
    for s in DEFAULT_ORDER:
        if s not in order:
            order.append(s)

    remap_colors = None
    if args.remap and args.remap != "matugen":
        remap_colors = load_palette_colors(args.remap)

    deltas = theory_deltas(args.theory)
    if args.json:
        transform_json_file(args.json, deltas, args.style, args.practical, remap_colors, order)
    if args.scss:
        transform_scss_file(args.scss, deltas, args.style, args.practical, remap_colors, order)
    return 0

if __name__ == "__main__":
    sys.exit(main())
