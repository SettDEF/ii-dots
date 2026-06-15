#!/usr/bin/env python3
# Tone-curve helpers for WallTune.
#
# Subcommands:
#   histogram <image_path>
#       Prints a JSON list of 256 luminance-bin counts (downsampled 64x64).
#
#   lut <points> <out.pgm>
#       Writes a 256x1 grayscale PGM that maps input luminance -> output
#       luminance using the given control points. <points> is a
#       semicolon-separated list of "x,y" pairs in [0,1], e.g.
#         "0,0;0.25,0.18;0.75,0.85;1,1"
#       Used with `magick INPUT ... LUT.pgm -clut OUTPUT`.
#
# Stdlib only (subprocess for ImageMagick).

import json, subprocess, sys


def histogram(path: str) -> None:
    proc = subprocess.run(
        ["magick", path, "-colorspace", "Gray",
         "-resize", "64x64!", "-depth", "8", "gray:-"],
        capture_output=True, check=False,
    )
    bins = [0] * 256
    for b in proc.stdout:
        bins[b] += 1
    sys.stdout.write(json.dumps(bins))


def lut(points_str: str, out_path: str) -> None:
    pts = sorted(
        tuple(float(v) for v in p.split(","))
        for p in points_str.split(";")
        if p.strip()
    )
    if len(pts) < 2:
        pts = [(0.0, 0.0), (1.0, 1.0)]

    def interp(x: float) -> float:
        if x <= pts[0][0]:
            return pts[0][1]
        if x >= pts[-1][0]:
            return pts[-1][1]
        for i in range(len(pts) - 1):
            x0, y0 = pts[i]
            x1, y1 = pts[i + 1]
            if x0 <= x <= x1:
                t = 0.0 if x1 == x0 else (x - x0) / (x1 - x0)
                return y0 + t * (y1 - y0)
        return x

    with open(out_path, "wb") as f:
        f.write(b"P5\n256 1\n255\n")
        f.write(bytes(
            max(0, min(255, int(round(interp(i / 255.0) * 255))))
            for i in range(256)
        ))


def main() -> int:
    if len(sys.argv) < 2:
        sys.stderr.write("usage: walltune-curve.py histogram <img> | lut <pts> <out>\n")
        return 2
    cmd = sys.argv[1]
    if cmd == "histogram":
        histogram(sys.argv[2])
    elif cmd == "lut":
        lut(sys.argv[2], sys.argv[3])
    else:
        sys.stderr.write(f"unknown command: {cmd}\n")
        return 2
    return 0


if __name__ == "__main__":
    sys.exit(main())
