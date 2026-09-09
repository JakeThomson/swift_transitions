"""Stage 9: the card's outline against the covered page, frame by frame.

    python3 analyze_outline.py frames/ out.csv [--rest=1] [--from=t] [--to=t]

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
from PIL import Image

THRESHOLD = 40  # of 255, per channel: past the dim (38) and the shadow
MIN_RUN = 8  # points of a row or column that must differ, past stray text


def load(path, scale):
    a = np.asarray(Image.open(path).convert("RGB"), dtype=np.int16)
    return a[::scale, ::scale]


def outline(frame, rest):
    diff = np.abs(frame - rest).max(axis=2) > THRESHOLD
    rows = np.nonzero(diff.sum(axis=1) >= MIN_RUN)[0]
    cols = np.nonzero(diff.sum(axis=0) >= MIN_RUN)[0]
    if not len(rows) or not len(cols):
        return None
    return cols[0], rows[0], cols[-1] + 1, rows[-1] + 1


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    opts = dict(a[2:].split("=") for a in sys.argv[1:] if a.startswith("--"))
    frames, out = Path(args[0]), args[1]
    scale = int(opts.get("scale", 3))
    times = {int(r["index"]): float(r["t"]) for r in csv.DictReader(open(frames / "times.csv"))}
    keep = [i for i, t in sorted(times.items())
            if float(opts.get("from", -1)) <= t <= float(opts.get("to", 1e9))]
    rest = load(frames / f"{int(opts.get('rest', keep[0])):06d}.png", scale)
    with open(out, "w", newline="") as f:
        w = csv.writer(f)
        w.writerow(["index", "t", "l", "t_", "r", "b"])
        for i in keep:
            box = outline(load(frames / f"{i:06d}.png", scale), rest)
            w.writerow([i, f"{times[i]:.4f}"] + (list(box) if box else ["", "", "", ""]))
    print(f"{len(keep)} frames -> {out}")


if __name__ == "__main__":
    main()
