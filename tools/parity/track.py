"""Per-frame boxes of colour classes, and the luminance of a patch.

    python3 track.py frames/ out.csv [--scale 3]

Classes are the flat-palette colours the two apps share (see PALETTE).
Each column is in points (the simulator records at the device's scale).
A box is empty (blank cells) when fewer than MIN_PIXELS pixels match.
"""
import csv
import sys
from pathlib import Path

import numpy as np
from PIL import Image

# Hue in degrees, saturation and value in 0..1. Poster orange is the Dunes
# card in either palette (its gradient keeps the hue); the page tints are
# the flat palette only.
PALETTE = {
    "card":    {"hue": (20, 42), "sat": (0.45, 1.0), "val": (0.3, 1.0)},
    "zoom_pg": {"rgb": (0xEE, 0xF4, 0xFF), "tol": 10},   # zoomed page background, flat mode
    "push_pg": {"rgb": (0xE8, 0xFF, 0xEE), "tol": 10},   # pushed page background, flat mode
    "ring":    {"hue": (100, 140), "sat": (0.7, 1.0), "val": (0.7, 1.0)},  # touch rings
}
# A patch of the covered page that is plain background at rest, for the dim.
DIM_PATCH = (300, 150, 60, 30)  # x, y, w, h in points
# A patch of the navigation bar left of its title, white in both apps at
# rest. The first frame it is near white is the app's first frame; frames
# before that are the simulator's home screen and launch (the wallpaper is
# orange) and get no boxes. Latched, since the bar dims during flights.
APP_PATCH = (40, 64, 90, 34)
# Below this many matching pixels a box is noise (anti-aliased text edges
# blend toward the palette colours).
MIN_PIXELS = 300


def hsv(rgb):
    rgb = rgb.astype(np.float32) / 255
    mx = rgb.max(-1)
    mn = rgb.min(-1)
    d = mx - mn
    h = np.zeros_like(mx)
    r, g, b = rgb[..., 0], rgb[..., 1], rgb[..., 2]
    m = d > 1e-6
    rc = np.where(m & (mx == r), ((g - b) / np.where(m, d, 1)) % 6, 0)
    gc = np.where(m & (mx == g) & (mx != r), (b - r) / np.where(m, d, 1) + 2, 0)
    bc = np.where(m & (mx == b) & (mx != r) & (mx != g), (r - g) / np.where(m, d, 1) + 4, 0)
    h = (rc + gc + bc) * 60
    s = np.where(mx > 0, d / np.where(mx > 0, mx, 1), 0)
    return h, s, mx


def mask_for(spec, rgb, h, s, v):
    if "rgb" in spec:
        t = spec["tol"]
        return np.all(np.abs(rgb.astype(int) - np.array(spec["rgb"])) <= t, axis=-1)
    return ((h >= spec["hue"][0]) & (h <= spec["hue"][1]) &
            (s >= spec["sat"][0]) & (s <= spec["sat"][1]) &
            (v >= spec["val"][0]) & (v <= spec["val"][1]))


def box(mask, scale):
    ys, xs = np.nonzero(mask)
    if len(xs) < MIN_PIXELS:
        return [""] * 4
    return [f"{xs.min() / scale:.1f}", f"{ys.min() / scale:.1f}",
            f"{(xs.max() + 1) / scale:.1f}", f"{(ys.max() + 1) / scale:.1f}"]


def track_frame(args):
    name, scale = args
    rgb = np.asarray(Image.open(name).convert("RGB"))
    ax, ay, aw, ah = (int(c * scale) for c in APP_PATCH)
    app_patch_white = bool(rgb[ay:ay + ah, ax:ax + aw].min() > 225)
    h, s, v = hsv(rgb)
    boxes = [box(mask_for(spec, rgb, h, s, v), scale) for spec in PALETTE.values()]
    x, y, pw, ph = (int(c * scale) for c in DIM_PATCH)
    patch = rgb[y:y + ph, x:x + pw].astype(np.float32)
    lum = (0.2126 * patch[..., 0] + 0.7152 * patch[..., 1] + 0.0722 * patch[..., 2]).mean()
    return int(name.stem), app_patch_white, boxes, lum


def main(frames, out, scale=3.0):
    from multiprocessing import Pool

    frames = Path(frames)
    times = {int(r["index"]): float(r["t"]) for r in csv.DictReader(open(frames / "times.csv"))}
    names = sorted(frames.glob("*.png"))
    with Pool() as pool:
        results = pool.map(track_frame, [(n, scale) for n in names], chunksize=4)
    with open(out, "w", newline="") as f:
        w = csv.writer(f)
        cols = ["index", "t"]
        for name in PALETTE:
            cols += [f"{name}_l", f"{name}_t", f"{name}_r", f"{name}_b"]
        cols += ["dim_y", "app"]
        w.writerow(cols)
        app_up = False
        for i, white, boxes, lum in results:
            app_up = app_up or white
            row = [i, f"{times.get(i, 0):.4f}"]
            for b in boxes:
                row += b if app_up else [""] * 4
            row += [f"{lum:.1f}", int(app_up)]
            w.writerow(row)
    print(f"tracked {len(names)} frames -> {out}")


if __name__ == "__main__":
    args = sys.argv[1:]
    scale = 3.0
    if "--scale" in args:
        k = args.index("--scale")
        scale = float(args[k + 1])
        del args[k:k + 2]
    main(args[0], args[1], scale)
