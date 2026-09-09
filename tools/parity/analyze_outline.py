"""Stage 9: the card's outline against the covered page, frame by frame.

    python3 analyze_outline.py frames/ out.csv [--rest=1] [--from=t] [--to=t]
                              [--threshold=12]

The colour classes cannot see a zoom card once the source's copy has
faded: the card is then the page, whose tint is only part of it. This
reads the card's box as the pixels that differ from the covered page at
rest, well past the dim and the card's shadow, and writes one row per
frame (index, t, l, t, r, b, in points) for [analyze_lead.py].
"""
import csv
import sys
from pathlib import Path

import numpy as np
from PIL import Image, ImageFilter

THRESHOLD = 12  # of 255, per channel: past the noise, under the page's tint
# A patch of the covered page the card never reaches, for the dim: the
# rest frame is scaled by what the dim has done to it before differencing,
# so a dimmed page reads as unchanged and only the card is left.
DIM_PATCH = (2, 820, 20, 40)  # x, y, w, h in points
ERODE = 5  # points: thinner differences than this are text and hairlines
# The card is the one solid block in the mask: read its edges as the
# longest unbroken run across the fullest row and down the fullest column,
# which the covered page's own changes cannot lengthen.


def load(path, scale):
    a = np.asarray(Image.open(path).convert("RGB"), dtype=np.int16)
    return a[::scale, ::scale]


def dimmed(rest, frame):
    """[rest] darkened by as much as the dim has darkened [frame]."""
    x, y, w, h = DIM_PATCH
    patch = (slice(y, y + h), slice(x, x + w))
    was, now = rest[patch].mean(), frame[patch].mean()
    return rest if was <= 0 else np.clip(rest * (now / was), 0, 255)


def outline(frame, rest, threshold):
    diff = np.abs(frame - dimmed(rest, frame)).max(axis=2) > threshold
    # The bar's title and the rows' labels change under a flight too, and
    # every edge on the covered page shifts by a pixel: eroding the mask
    # leaves the card, which is the only solid area of it.
    eroded = Image.fromarray((diff * 255).astype(np.uint8)).filter(
        ImageFilter.MinFilter(ERODE))
    diff = np.asarray(eroded) > 0
    if not diff.any():
        return None
    down = run(diff[:, diff.sum(axis=0).argmax()])
    if down is None:
        return None
    across = run(diff[(down[0] + down[1]) // 2])
    if across is None:
        return None
    return across[0], down[0], across[1], down[1]


def run(line):
    """The longest unbroken run of True in [line], as (start, end)."""
    best = here = None
    for i, on in enumerate(line):
        if on:
            here = (here or (i, i))[0], i + 1
            if best is None or here[1] - here[0] > best[1] - best[0]:
                best = here
        else:
            here = None
    return best


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    opts = dict(a[2:].split("=") for a in sys.argv[1:] if a.startswith("--"))
    frames, out = Path(args[0]), args[1]
    scale = int(opts.get("scale", 3))
    threshold = int(opts.get("threshold", THRESHOLD))
    times = {int(r["index"]): float(r["t"]) for r in csv.DictReader(open(frames / "times.csv"))}
    keep = [i for i, t in sorted(times.items())
            if float(opts.get("from", -1)) <= t <= float(opts.get("to", 1e9))]
    rest = load(frames / f"{int(opts.get('rest', keep[0])):06d}.png", scale)
    with open(out, "w", newline="") as f:
        w = csv.writer(f)
        w.writerow(["index", "t", "l", "t_", "r", "b"])
        for i in keep:
            box = outline(load(frames / f"{i:06d}.png", scale), rest, threshold)
            w.writerow([i, f"{times[i]:.4f}"] + (list(box) if box else ["", "", "", ""]))
    print(f"{len(keep)} frames -> {out}")


if __name__ == "__main__":
    main()
