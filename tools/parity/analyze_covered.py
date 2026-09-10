"""The covered page's scale under a zoom, from the grid it carries.

    python3 analyze_covered.py run.csv frames/

The poster row's outer edges — the blue poster's left and the green
poster's right, 16.0 and 400.0 pt apart at rest — move together when the
page behind the card is scaled, and the card never covers both until it
is nearly full screen. Their separation gives the scale and their
positions the point it scales about. Prints one line per frame the two
are visible, against the card's width.
"""
import csv
import os
import sys

import numpy as np
from PIL import Image

BLUE_L, GREEN_R = 16.0, 400.0     # at rest, in points
ROW = (200, 520)                  # the poster row's band, in points
SCALE = 3


def edges(img):
    a = np.asarray(img.convert("RGB")).astype(int)
    band = a[ROW[0] * SCALE:ROW[1] * SCALE]
    r, g, b = band[..., 0], band[..., 1], band[..., 2]
    blue = (b > r + 40) & (b > g + 20)
    green = (g > r + 20) & (g > b + 20)
    if blue.sum() < 300 or green.sum() < 300:
        return None
    return np.nonzero(blue.any(0))[0].min() / SCALE, np.nonzero(green.any(0))[0].max() / SCALE


def main():
    rows = [r for r in csv.DictReader(open(sys.argv[1])) if r["app"] == "1"]
    frames = sys.argv[2]
    print(f"{'t':>8s} {'cardw':>7s} {'blue_l':>7s} {'green_r':>8s} {'scale':>6s} {'about':>6s}")
    for r in rows:
        got = edges(Image.open(os.path.join(frames, f"{int(r['index']):06d}.png")))
        if got is None:
            continue
        l, right = got
        scale = (right - l) / (GREEN_R - BLUE_L)
        about = (l - BLUE_L * scale) / (1 - scale) if abs(1 - scale) > 1e-3 else float("nan")
        w = float(r["card_r"]) - float(r["card_l"]) if r["card_l"] else float("nan")
        print(f"{float(r['t']):8.3f} {w:7.1f} {l:7.1f} {right:8.1f} {scale:6.3f} {about:6.1f}")


if __name__ == "__main__":
    main()
