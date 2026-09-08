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
    # The blue poster, which rides the covered page; confined to the poster
    # row so the incoming page's blue back chevron is not counted.
    "aurora":  {"hue": (205, 225), "sat": (0.5, 1.0), "val": (0.4, 1.0), "region": (0, 250, 402, 430)},
}
# A patch of the covered page that is plain background at rest, for the
# dim: against the left edge, below the poster row, so it stays uncovered
# for as long as anything does during a push, and beside the card during
# a zoom. Only meaningful while the incoming page has not reached it.
DIM_PATCH = (2, 520, 20, 40)  # x, y, w, h in points
# Scanlines along which the first matching pixel of a class is reported,
# as <class>_x<y>: the leading edge of a sliding page along one row is
# immune to whatever else in the frame shares its colour.
SCANLINES = {"push_pg": (300, 600), "zoom_pg": (600,)}
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


def mask_for(spec, rgb, h, s, v, scale=3.0):
    if "rgb" in spec:
        t = spec["tol"]
        mask = np.all(np.abs(rgb.astype(int) - np.array(spec["rgb"])) <= t, axis=-1)
    else:
        mask = ((h >= spec["hue"][0]) & (h <= spec["hue"][1]) &
                (s >= spec["sat"][0]) & (s <= spec["sat"][1]) &
                (v >= spec["val"][0]) & (v <= spec["val"][1]))
    if "region" in spec:
        x0, y0, x1, y1 = (int(c * scale) for c in spec["region"])
        clipped = np.zeros_like(mask)
        clipped[y0:y1, x0:x1] = mask[y0:y1, x0:x1]
        mask = clipped
    return mask


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
    masks = {name: mask_for(spec, rgb, h, s, v, scale) for name, spec in PALETTE.items()}
    boxes = [box(masks[name], scale) for name in PALETTE]
    edges = []
    for cls, ys in SCANLINES.items():
        for y in ys:
            row = masks[cls][int(y * scale)]
            hit = np.nonzero(row)[0]
            edges.append(f"{hit[0] / scale:.1f}" if len(hit) else "")
    x, y, pw, ph = (int(c * scale) for c in DIM_PATCH)
    patch = rgb[y:y + ph, x:x + pw].astype(np.float32)
    lum = (0.2126 * patch[..., 0] + 0.7152 * patch[..., 1] + 0.0722 * patch[..., 2]).mean()
    return int(name.stem), app_patch_white, boxes, edges, lum


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
        for name, ys in SCANLINES.items():
            cols += [f"{name}_x{y}" for y in ys]
        cols += ["dim_y", "app"]
        w.writerow(cols)
        app_up = False
        for i, white, boxes, edges, lum in results:
            app_up = app_up or white
            row = [i, f"{times.get(i, 0):.4f}"]
            for b in boxes:
                row += b if app_up else [""] * 4
            row += edges if app_up else [""] * len(edges)
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
