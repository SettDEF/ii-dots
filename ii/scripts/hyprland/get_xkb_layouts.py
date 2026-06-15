#!/usr/bin/env python3
"""
get_xkb_layouts.py — list every installed XKB layout (and its variants) by
parsing /usr/share/X11/xkb/rules/evdev.lst. Output is a flat JSON list, one
entry per (layout, variant) combo:

    [
        { "layout": "us", "variant": "",        "code": "us",          "name": "English (US)" },
        { "layout": "us", "variant": "dvorak",  "code": "us(dvorak)",  "name": "English (Dvorak)" },
        { "layout": "de", "variant": "",        "code": "de",          "name": "German" },
        ...
    ]

Used by the KeyboardLayout picker so a user can pick from any installed layout,
not just the ones currently in Hyprland's kb_layout.
"""
import json
import sys

EVDEV_LST = "/usr/share/X11/xkb/rules/evdev.lst"


def parse() -> dict:
    layouts: dict[str, dict] = {}
    section = None
    try:
        with open(EVDEV_LST, encoding="utf-8") as f:
            for raw in f:
                line = raw.rstrip("\n")
                stripped = line.strip()
                if line.startswith("! layout"):
                    section = "layout"; continue
                if line.startswith("! variant"):
                    section = "variant"; continue
                if line.startswith("!"):
                    section = None; continue
                if not section or not stripped:
                    continue
                parts = stripped.split(None, 1)
                if len(parts) < 2:
                    continue
                code, rest = parts[0], parts[1].strip()
                if section == "layout":
                    layouts.setdefault(code, {
                        "code": code, "name": rest, "variants": []
                    })
                else:  # variant — "parent: Variant Name"
                    if ":" not in rest:
                        continue
                    parent, vname = rest.split(":", 1)
                    parent = parent.strip()
                    vname = vname.strip()
                    layouts.setdefault(parent, {
                        "code": parent, "name": parent, "variants": []
                    })
                    layouts[parent]["variants"].append({
                        "code": code, "name": vname
                    })
    except FileNotFoundError:
        return {}
    return layouts


def main() -> None:
    layouts = parse()
    if not layouts:
        print("[]"); return
    out = []
    for layout in sorted(layouts.values(), key=lambda x: x["code"]):
        out.append({
            "layout":  layout["code"],
            "variant": "",
            "code":    layout["code"],
            "name":    layout["name"],
        })
        for v in sorted(layout["variants"], key=lambda x: x["code"]):
            out.append({
                "layout":  layout["code"],
                "variant": v["code"],
                "code":    f'{layout["code"]}({v["code"]})',
                "name":    v["name"],
            })
    json.dump(out, sys.stdout, ensure_ascii=False)


if __name__ == "__main__":
    main()
