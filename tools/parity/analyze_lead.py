"""Stage 9: a zoom flight's vertical lead, from a tracked recording.

    python3 analyze_lead.py outline.csv [outline2.csv ...]

One line per flight: the card's height against its width, as the lead
`zoomVerticalProgress` models — `ty = tx + lead·sin(pi·tx)`, negative
pushing, positive popping. The boxes are [analyze_outline.py]'s, the
card against the covered page, and each axis is normalised on the
flight's own first and last frame.
"""
import csv
import os
import sys

import numpy as np

STILL = 0.35


def box(r):
    return [float(r[k]) for k in ("l", "t_", "r", "b")]


def flights(rows):
    """Runs of change in the card's width, ended by [STILL] of stillness."""
    seen = [r for r in rows if r["r"]]
    out, run = [], []
    for a, b in zip(seen, seen[1:]):
        wide = abs((box(b)[2] - box(b)[0]) - (box(a)[2] - box(a)[0]))
        if wide > 1.5:
            run.append(b)
        elif run and float(b["t"]) - float(run[-1]["t"]) > STILL:
            out.append(run)
            run = []
    return [f for f in out + [run] if len(f) > 8]


def lead(flight):
    w = np.array([box(r)[2] - box(r)[0] for r in flight])
    h = np.array([box(r)[3] - box(r)[1] for r in flight])
    if abs(w[-1] - w[0]) < 100 or abs(h[-1] - h[0]) < 100:
        return None
    tx = (w - w[0]) / (w[-1] - w[0])
    ty = (h - h[0]) / (h[-1] - h[0])
    keep = (tx > 0.05) & (tx < 0.95)
    tx, ty = tx[keep], ty[keep]
    if len(tx) < 5:
        return None
    best = min((np.sqrt(np.mean((tx + v * np.sin(np.pi * tx) - ty) ** 2)), v)
               for v in np.arange(-0.2, 0.2, 0.005))
    return w[0] < w[-1], best[1], best[0], len(tx)


def main():
    for path in sys.argv[1:]:
        name = os.path.basename(path)
        rows = list(csv.DictReader(open(path)))
        for flight in flights(rows):
            fit = lead(flight)
            if fit is None:
                continue
            pushing, v, rms, n = fit
            print(f"{name:30s} {'push' if pushing else 'pop ':4s} lead {v:+.3f}  rms {rms:.3f} of the travel  ({n} frames)")


if __name__ == "__main__":
    main()
